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
  }) async {
    final info = await _apiClient.getPlaybackInfo(
      itemId: item.dataSourceId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
    );

    final source = _pickBestSource(info);
    final url = await _buildFinalUrl(item, info, source);

    // 预读 token 以拼接外部字幕的绝对地址
    final token = await _securityService.readAccessToken() ?? '';

    // 优先用所选 Source 的流；若为空，回退到汇总所有 Source 的流（部分服务器会把外挂字幕挂到不同 Source）。
    List<PlaybackStream> _mapAudioStreams(List<EmbyMediaStreamDto> streams) {
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

    List<PlaybackStream> _mapSubtitleStreams(List<EmbyMediaStreamDto> streams) {
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
              final isAbs = raw.startsWith('http://') || raw.startsWith('https://');
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

    var audio = _mapAudioStreams(source.mediaStreams);
    var subs = _mapSubtitleStreams(source.mediaStreams);
    if (audio.isEmpty || subs.isEmpty) {
      final allStreams = info.mediaSources.expand((s) => s.mediaStreams);
      if (audio.isEmpty) audio = _mapAudioStreams(allStreams.toList());
      if (subs.isEmpty) subs = _mapSubtitleStreams(allStreams.toList());
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
    // 简单策略：优先直链，其次转码
    return info.mediaSources.firstWhere(
      (s) => s.supportsDirectPlay,
      orElse: () => info.mediaSources.first,
    );
  }

  Future<String> _buildFinalUrl(
    MediaItem item,
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source,
  ) async {
    // 若服务端提供转码地址，通常是相对路径，拼成绝对 URL
    if ((source.transcodingUrl ?? '').isNotEmpty) {
      final rel = source.transcodingUrl!;
      final token = await _securityService.readAccessToken() ?? '';
      // TranscodingUrl 可能没有附带 api_key，这里统一追加
      final u = Uri.parse('${_apiClient.serverUrl}$rel');
      final qp = Map<String, String>.from(u.queryParameters);
      qp.putIfAbsent('api_key', () => token);
      return u.replace(queryParameters: qp).toString();
    }
    // 否则走直链：/Videos/{itemId}/stream?Static=true&api_key=...&MediaSourceId=...
    final token = await _securityService.readAccessToken();
    final apiKey = token ?? '';
    return '${_apiClient.serverUrl}/emby/Videos/${item.dataSourceId}/stream?Static=true&MediaSourceId=${source.id}&api_key=$apiKey';
  }
}
