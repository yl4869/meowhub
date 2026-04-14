import '../../core/services/security_service.dart';
import 'package:flutter/foundation.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/repositories/playback_repository.dart';
import '../datasources/emby_api_client.dart';
import '../models/emby/emby_playback_info_dto.dart';

class EmbyPlaybackRepositoryImpl implements PlaybackRepository {
  EmbyPlaybackRepositoryImpl({
    required EmbyApiClient apiClient,
    required SecurityService securityService,
  }) : _apiClient = apiClient,
       _securityService = securityService;

  final EmbyApiClient _apiClient;
  final SecurityService _securityService;

  @override
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final normalizedAudioIndex = _normalizeSelectedIndex(audioStreamIndex);
    final normalizedSubtitleIndex = _normalizeSelectedIndex(
      subtitleStreamIndex,
    );
    final info = await _apiClient.getPlaybackInfo(
      itemId: item.dataSourceId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: normalizedAudioIndex,
      subtitleStreamIndex: normalizedSubtitleIndex,
    );

    final source = _pickBestSource(info);
    final url = await _buildFinalUrl(
      item,
      info,
      source,
      audioStreamIndex: normalizedAudioIndex,
      subtitleStreamIndex: normalizedSubtitleIndex,
    );

    // 预读 token 以拼接外部字幕的绝对地址
    final token = await _securityService.readAccessToken() ?? '';

    // 优先用所选 Source 的流；若为空，回退到汇总所有 Source 的流（部分服务器会把外挂字幕挂到不同 Source）。
    List<PlaybackStream> mapAudioStreams(List<EmbyMediaStreamDto> streams) {
      return streams
          .where((s) => s.type.toLowerCase() == 'audio')
          .map(
            (s) => PlaybackStream(
              index: s.index,
              title: s.displayTitle ?? '音轨 ${s.index}',
              language: s.language,
              codec: s.codec,
              channels: s.channels,
              isDefault: s.isDefault,
            ),
          )
          .toList(growable: false);
    }

    List<PlaybackStream> mapSubtitleStreams(List<EmbyMediaStreamDto> streams) {
      return streams
          .where((s) => s.type.toLowerCase() == 'subtitle')
          .map((s) {
            final title = (s.displayTitle?.isNotEmpty == true)
                ? s.displayTitle!
                : '字幕 ${s.index}';
            // 解析外链字幕的可访问地址
            String? resolvedDeliveryUrl;
            final raw = s.deliveryUrl;
            if (raw != null && raw.isNotEmpty) {
              final isAbs =
                  raw.startsWith('http://') || raw.startsWith('https://');
              final base = isAbs ? raw : '${_apiClient.serverUrl}$raw';
              final u = Uri.parse(base);
              final qp = Map<String, String>.from(u.queryParameters);
              if (!qp.containsKey('api_key') && token.isNotEmpty) {
                qp['api_key'] = token;
              }
              resolvedDeliveryUrl = u.replace(queryParameters: qp).toString();
            }
            return PlaybackStream(
              index: s.index,
              title: title,
              language: s.language,
              codec: s.codec,
              isDefault: s.isDefault,
              isExternal: s.isExternal,
              isTextSubtitleStream: s.isTextSubtitleStream,
              deliveryUrl: resolvedDeliveryUrl,
            );
          })
          .toList(growable: false);
    }

    var audio = mapAudioStreams(source.mediaStreams);
    var subs = mapSubtitleStreams(source.mediaStreams);
    if (audio.isEmpty || subs.isEmpty) {
      final allStreams = info.mediaSources.expand((s) => s.mediaStreams);
      if (audio.isEmpty) audio = mapAudioStreams(allStreams.toList());
      if (subs.isEmpty) subs = mapSubtitleStreams(allStreams.toList());
    }

    // Debug: mapped stream counts & selected source
    if (kDebugMode) {
      debugPrint(
        '[PlaybackPlan] url=$url source=${source.id} audio=${audio.length} subs=${subs.length}',
      );
    }

    return PlaybackPlan(
      url: url,
      playSessionId: info.playSessionId,
      mediaSourceId: source.id,
      audioStreams: audio,
      subtitleStreams: subs,
    );
  }

  EmbyMediaSourceDto _pickBestSource(EmbyPlaybackInfoDto info) {
    if (info.mediaSources.isEmpty) {
      throw StateError('No media sources available for playback');
    }
    final transcodingSource = info.mediaSources.firstWhere(
      (s) => (s.transcodingUrl ?? '').isNotEmpty,
      orElse: () => const EmbyMediaSourceDto(id: ''),
    );
    if (transcodingSource.id.isNotEmpty) {
      return transcodingSource;
    }
    // 简单策略：优先直链，其次首个源
    return info.mediaSources.firstWhere(
      (s) => s.supportsDirectPlay,
      orElse: () => info.mediaSources.first,
    );
  }

  Future<String> _buildFinalUrl(
    MediaItem item,
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final token = await _securityService.readAccessToken() ?? '';
    final transcodingUrl = _pickTranscodingUrl(info, source);
    if (transcodingUrl != null) {
      return _resolveAuthorizedUrl(transcodingUrl, token);
    }

    final directUrl = Uri.parse(
      '${_apiClient.serverUrl}/emby/Videos/${item.dataSourceId}/stream',
    );
    final queryParameters = <String, String>{
      'Static': 'true',
      if (source.id.isNotEmpty) 'MediaSourceId': source.id,
      if (audioStreamIndex != null) 'AudioStreamIndex': '$audioStreamIndex',
      if (subtitleStreamIndex != null)
        'SubtitleStreamIndex': '$subtitleStreamIndex',
      if (token.isNotEmpty) 'api_key': token,
    };
    return directUrl.replace(queryParameters: queryParameters).toString();
  }

  int? _normalizeSelectedIndex(int? index) {
    if (index == null || index < 0) {
      return null;
    }
    return index;
  }

  String? _pickTranscodingUrl(
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source,
  ) {
    final candidates = <String?>[
      info.transcodingUrl,
      source.transcodingUrl,
      ...info.mediaSources.map((s) => s.transcodingUrl),
    ];
    for (final candidate in candidates) {
      if (candidate != null && candidate.isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  String _resolveAuthorizedUrl(String rawUrl, String token) {
    final isAbsolute =
        rawUrl.startsWith('http://') || rawUrl.startsWith('https://');
    final base = isAbsolute ? rawUrl : '${_apiClient.serverUrl}$rawUrl';
    final uri = Uri.parse(base);
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (token.isNotEmpty) {
      queryParameters['api_key'] = token;
    }
    return uri.replace(queryParameters: queryParameters).toString();
  }
}
