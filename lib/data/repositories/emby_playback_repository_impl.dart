import 'package:flutter/foundation.dart';

import '../../core/utils/emby_ticks.dart';
import '../../core/services/security_service.dart';
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

  static const Duration _cacheTtl = Duration(seconds: 12);
  static final Map<_PlaybackPlanCacheKey, _PlaybackPlanCacheEntry>
  _resolvedPlans = {};
  static final Map<_PlaybackPlanCacheKey, Future<PlaybackPlan>> _ongoingPlans =
      {};

  final EmbyApiClient _apiClient;
  final SecurityService _securityService;

  @visibleForTesting
  static void clearPlaybackPlanCache() {
    _resolvedPlans.clear();
    _ongoingPlans.clear();
  }

  @override
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    Duration startPosition = Duration.zero,
  }) async {
    final normalizedAudioIndex = _normalizeSelectedIndex(audioStreamIndex);
    final normalizedSubtitleIndex = _normalizeSelectedIndex(
      subtitleStreamIndex,
    );
    final cacheKey = _PlaybackPlanCacheKey(
      namespace: _apiClient.securityNamespace,
      itemId: item.dataSourceId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: normalizedAudioIndex,
      subtitleStreamIndex: normalizedSubtitleIndex,
      playSessionId: playSessionId,
      startPositionTicks: durationToEmbyTicks(startPosition),
    );
    _evictExpiredEntries();

    final cached = _resolvedPlans[cacheKey];
    if (cached != null && !cached.isExpired) {
      return cached.plan;
    }

    final ongoing = _ongoingPlans[cacheKey];
    if (ongoing != null) {
      return ongoing;
    }

    final future = _loadPlaybackPlan(
      item,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: normalizedAudioIndex,
      subtitleStreamIndex: normalizedSubtitleIndex,
      playSessionId: playSessionId,
      startPosition: startPosition,
    );
    _ongoingPlans[cacheKey] = future;

    try {
      final plan = await future;
      _resolvedPlans[cacheKey] = _PlaybackPlanCacheEntry(
        plan: plan,
        cachedAt: DateTime.now(),
      );
      return plan;
    } finally {
      if (identical(_ongoingPlans[cacheKey], future)) {
        _ongoingPlans.remove(cacheKey);
      }
    }
  }

  Future<PlaybackPlan> _loadPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    Duration startPosition = Duration.zero,
  }) async {
    final info = await _apiClient.getPlaybackInfo(
      itemId: item.dataSourceId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      playSessionId: playSessionId,
      startPosition: startPosition,
    );

    final source = _pickBestSource(info);
    final transcodingUrl = _pickTranscodingUrl(info, source);
    final url = await _buildFinalUrl(
      item,
      info,
      source,
      transcodingUrl: transcodingUrl,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      startPosition: startPosition,
    );

    // 预读 token 以拼接外部字幕的绝对地址
    final token =
        await _securityService.readAccessToken(
          namespace: _apiClient.securityNamespace,
        ) ??
        '';

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
    return PlaybackPlan(
      url: url,
      isTranscoding: transcodingUrl != null,
      playSessionId: info.playSessionId ?? playSessionId,
      mediaSourceId: source.id,
      audioStreams: audio,
      subtitleStreams: subs,
    );
  }

  void _evictExpiredEntries() {
    final expiredKeys = _resolvedPlans.entries
        .where((entry) => entry.value.isExpired)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final key in expiredKeys) {
      _resolvedPlans.remove(key);
    }
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
    String? transcodingUrl,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    Duration startPosition = Duration.zero,
  }) async {
    final token =
        await _securityService.readAccessToken(
          namespace: _apiClient.securityNamespace,
        ) ??
        '';
    if (transcodingUrl != null) {
      return _resolveAuthorizedUrl(
        transcodingUrl,
        token,
        startPosition: startPosition,
      );
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
      if (startPosition > Duration.zero)
        'StartTimeTicks': '${durationToEmbyTicks(startPosition)}',
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

  String _resolveAuthorizedUrl(
    String rawUrl,
    String token, {
    Duration startPosition = Duration.zero,
  }) {
    final isAbsolute =
        rawUrl.startsWith('http://') || rawUrl.startsWith('https://');
    final base = isAbsolute ? rawUrl : '${_apiClient.serverUrl}$rawUrl';
    final uri = Uri.parse(base);
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (startPosition > Duration.zero) {
      queryParameters['StartTimeTicks'] =
          '${durationToEmbyTicks(startPosition)}';
    }
    if (token.isNotEmpty) {
      queryParameters['api_key'] = token;
    }
    return uri.replace(queryParameters: queryParameters).toString();
  }
}

class _PlaybackPlanCacheKey {
  const _PlaybackPlanCacheKey({
    required this.namespace,
    required this.itemId,
    required this.maxStreamingBitrate,
    required this.requireAvc,
    required this.audioStreamIndex,
    required this.subtitleStreamIndex,
    required this.playSessionId,
    required this.startPositionTicks,
  });

  final String namespace;
  final String itemId;
  final int? maxStreamingBitrate;
  final bool? requireAvc;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? playSessionId;
  final int startPositionTicks;

  @override
  bool operator ==(Object other) {
    return other is _PlaybackPlanCacheKey &&
        other.namespace == namespace &&
        other.itemId == itemId &&
        other.maxStreamingBitrate == maxStreamingBitrate &&
        other.requireAvc == requireAvc &&
        other.audioStreamIndex == audioStreamIndex &&
        other.subtitleStreamIndex == subtitleStreamIndex &&
        other.playSessionId == playSessionId &&
        other.startPositionTicks == startPositionTicks;
  }

  @override
  int get hashCode => Object.hash(
    namespace,
    itemId,
    maxStreamingBitrate,
    requireAvc,
    audioStreamIndex,
    subtitleStreamIndex,
    playSessionId,
    startPositionTicks,
  );
}

class _PlaybackPlanCacheEntry {
  const _PlaybackPlanCacheEntry({required this.plan, required this.cachedAt});

  final PlaybackPlan plan;
  final DateTime cachedAt;

  bool get isExpired =>
      DateTime.now().difference(cachedAt) >
      EmbyPlaybackRepositoryImpl._cacheTtl;
}
