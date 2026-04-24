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

    final source = _pickBestSource(
      info,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    final transcodingUrl = _resolveTranscodingUrl(info, source);

    final token = await _securityService.readAccessToken(namespace: _apiClient.securityNamespace) ?? '';
    final userId = await _securityService.readUserId(
      namespace: _apiClient.securityNamespace,
    );

    // 构建最终播放 URL
    final url = await _buildFinalUrl(
      item, info, source,
      token: token,
      userId: userId,
      transcodingUrl: transcodingUrl,
      playSessionId: info.playSessionId ?? playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      startPosition: startPosition,
    );

    // 1. 映射音轨与字幕（注入全量元数据）
    var audio = _mapAudioStreams(source.mediaStreams);
    var subs = _mapSubtitleStreams(source.mediaStreams, token);
    // 如果当前 Source 没流，尝试合并所有 Source（Emby 处理外挂字幕的常见行为）
    if (audio.isEmpty || subs.isEmpty) {
      final allStreams = info.mediaSources.expand((s) => s.mediaStreams).toList();
      if (audio.isEmpty) audio = _mapAudioStreams(allStreams);
      if (subs.isEmpty) subs = _mapSubtitleStreams(allStreams, token);
    }
    // 2. 解析章节与标记 (直接调用类末尾的方法)
    final chapters = _parseChapters(source.chapters);
    final markers = _parseMarkers(source.markers);
    
    return PlaybackPlan(
      url: url,
      isTranscoding: transcodingUrl != null,
      playSessionId: info.playSessionId ?? playSessionId,
      mediaSourceId: source.id,
      audioStreams: audio,
      subtitleStreams: subs,
      chapters: chapters,
      markers: markers,
    );
  }

  void _evictExpiredEntries() {
    _resolvedPlans.removeWhere((_, entry) => entry.isExpired);
  }

  // --- 提炼后的私有映射方法 ---

  List<PlaybackStream> _mapAudioStreams(List<EmbyMediaStreamDto> streams) {
    return streams
        .where((s) => s.type.toLowerCase() == 'audio')
        .map((s) => PlaybackStream(
              index: s.index,
              title: _buildAudioStreamTitle(s),
              language: _pickRawLanguageLabel(s),
              codec: s.codec,
              channels: s.channels,
              bitrate: s.bitrate,
              isDefault: s.isDefault,
            ))
        .toList(growable: false);
  }

  List<PlaybackStream> _mapSubtitleStreams(List<EmbyMediaStreamDto> streams, String token) {
    return streams
        .where((s) => s.type.toLowerCase() == 'subtitle')
        .map((s) => PlaybackStream(
              index: s.index,
              title: _buildSubtitleStreamTitle(s),
              language: _pickRawLanguageLabel(s),
              codec: s.codec,
              isDefault: s.isDefault,
              isExternal: s.isExternal,
              isTextSubtitleStream: s.isTextSubtitleStream,
              deliveryUrl: s.deliveryUrl != null
                  ? _buildAuthorizedSubtitleVttUrl(s.deliveryUrl!, token)
                  : null,
            ))
        .toList(growable: false);
  }

  List<VideoChapter> _parseChapters(List<EmbyChapterDto>? dtos) {
    if (dtos == null) return const [];
    return dtos.map((c) => VideoChapter(
      title: c.name ?? '',
      startTime: embyTicksToDuration(c.startTicks),
    )).toList(growable: false);
  }

  Map<String, DurationRange> _parseMarkers(List<EmbyMarkerDto>? dtos) {
    final markers = <String, DurationRange>{};
    if (dtos == null) return markers;
    for (final m in dtos) {
      final type = m.type?.toLowerCase();
      if (type == 'intro' || type == 'outro') {
        markers[type!] = DurationRange(
          start: embyTicksToDuration(m.startTicks),
          end: embyTicksToDuration(m.endTicks),
        );
      }
    }
    return markers;
  }

  EmbyMediaSourceDto _pickBestSource(
    EmbyPlaybackInfoDto info, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    if (info.mediaSources.isEmpty) throw StateError('No media sources available');

    final matchedSources = info.mediaSources.where(
      (source) => _sourceMatchesSelection(
        source,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      ),
    );
    final candidates = matchedSources.isEmpty
        ? info.mediaSources
        : matchedSources.toList(growable: false);

    return candidates.firstWhere(
      (s) => s.supportsDirectPlay,
      orElse: () => candidates.firstWhere(
        (s) => (s.transcodingUrl ?? '').isNotEmpty,
        orElse: () => candidates.first,
      ),
    );
  }

  // ---URL部分---
  String _buildAuthorizedUrl(
    String rawUrl,
    String token, {
    String? userId,
    Duration? startPosition,
    String? mediaSourceId,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final isAbs = rawUrl.startsWith('http://') || rawUrl.startsWith('https://');
    final base = isAbs ? rawUrl : '${_apiClient.serverUrl}$rawUrl';
    final uri = Uri.parse(base);
    final qp = Map<String, String>.from(uri.queryParameters);
    
    if (token.isNotEmpty) qp['api_key'] = token;
    if (userId != null && userId.isNotEmpty) {
      qp['UserId'] = userId;
    }
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      qp['MediaSourceId'] = mediaSourceId;
    }
    if (playSessionId != null && playSessionId.isNotEmpty) {
      qp['PlaySessionId'] = playSessionId;
    }
    if (audioStreamIndex != null) {
      qp['AudioStreamIndex'] = '$audioStreamIndex';
    }
    if (subtitleStreamIndex != null) {
      qp['SubtitleStreamIndex'] = '$subtitleStreamIndex';
    }
    if (startPosition != null && startPosition > Duration.zero) {
      qp['StartTimeTicks'] = '${durationToEmbyTicks(startPosition)}';
    }
    // 强制外部字幕模式以兼容更多播放器
    if (qp.containsKey('SubtitleCodec')) qp['SubtitleMethod'] = 'External';

    return uri.replace(queryParameters: qp).toString();
  }

  String _buildAuthorizedSubtitleVttUrl(String rawUrl, String token) {
    final authorizedUrl = _buildAuthorizedUrl(rawUrl, token);
    final uri = Uri.parse(authorizedUrl);
    final rewrittenPath = uri.path.replaceFirst(
      RegExp(r'Stream\.[^/?.]+$'),
      'Stream.vtt',
    );
    return uri.replace(
      path: rewrittenPath == uri.path ? '${uri.path}.vtt' : rewrittenPath,
    ).toString();
  }

  String _buildAudioStreamTitle(EmbyMediaStreamDto stream) {
    final rawTitle = _composeRawStreamTitle(stream);
    if (rawTitle != null) {
      return rawTitle;
    }

    final lang = (_pickRawLanguageLabel(stream) ?? '').trim();
    final codec = (stream.codec ?? '').trim().toUpperCase();
    final channelShort = switch (stream.channels) {
      2 => 'stereo',
      final int channels? => '${channels}ch',
      _ => '',
    };
    final channelLabel = switch (stream.channels) {
      1 => '单声道',
      2 => '立体声',
      6 => '5.1 环绕声',
      8 => '7.1 环绕声',
      final int channels? => '$channels 声道',
      _ => '',
    };
    final bitrate = stream.bitrate != null
        ? '${(stream.bitrate! / 1000).round()}kbps'
        : '';

    final segments = <String>[
      [lang, codec, channelShort].where((value) => value.isNotEmpty).join(' '),
      if (channelLabel.isNotEmpty) '· $channelLabel',
      if (bitrate.isNotEmpty) '@$bitrate',
    ].where((value) => value.isNotEmpty).toList(growable: false);

    return segments.isEmpty ? '音轨 ${stream.index}' : segments.join(' ').trim();
  }

  String _buildSubtitleStreamTitle(EmbyMediaStreamDto stream) {
    return _composeRawStreamTitle(stream) ?? '字幕 ${stream.index}';
  }

  String? _composeRawStreamTitle(EmbyMediaStreamDto stream) {
    final title = stream.title?.trim();
    final displayTitle = stream.displayTitle?.trim();

    if (title != null && title.isNotEmpty) {
      if (displayTitle != null &&
          displayTitle.isNotEmpty &&
          displayTitle != title) {
        return '$title | $displayTitle';
      }
      return title;
    }

    if (displayTitle != null && displayTitle.isNotEmpty) {
      return displayTitle;
    }
    return null;
  }

  String? _pickRawLanguageLabel(EmbyMediaStreamDto stream) {
    final displayLanguage = stream.displayLanguage?.trim();
    if (displayLanguage != null && displayLanguage.isNotEmpty) {
      return displayLanguage;
    }

    final language = stream.language?.trim();
    if (language != null && language.isNotEmpty) {
      return language;
    }
    return null;
  }

  Future<String> _buildFinalUrl(
    MediaItem item,
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source, {
    required String token,
    String? userId,
    String? transcodingUrl,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    Duration startPosition = Duration.zero,
  }) async {
    final uri = Uri.parse('${_apiClient.serverUrl}/emby/Videos/${item.dataSourceId}/stream');
    final qp = <String, String>{
      'Static': 'true',
      if (token.isNotEmpty) 'api_key': token,
      if (userId != null && userId.isNotEmpty) 'UserId': userId,
      if (source.id.isNotEmpty) 'MediaSourceId': source.id,
      if (playSessionId != null && playSessionId.isNotEmpty)
        'PlaySessionId': playSessionId,
      if (startPosition > Duration.zero)
        'StartTimeTicks': '${durationToEmbyTicks(startPosition)}',
    };

    final finalUrl = uri.replace(queryParameters: qp).toString();

    if (kDebugMode) {
      debugPrint('[Diag][Playback] Final URL: $finalUrl');
      debugPrint('[Diag][Playback] Mode: Static (Direct)');
    }

    return finalUrl;
  }

  int? _normalizeSelectedIndex(int? index) => (index == null || index < 0) ? null : index;

  String? _resolveTranscodingUrl(
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source,
  ) {
    if (source.supportsDirectPlay) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][Playback] selected direct source | '
          'sourceId=${source.id}, container=${source.container}, '
          'ignoringTranscodingUrl=true',
        );
      }
      return null;
    }

    final sourceUrl = source.transcodingUrl?.trim();
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      return sourceUrl;
    }

    final topLevelUrl = info.transcodingUrl?.trim();
    if (topLevelUrl != null && topLevelUrl.isNotEmpty) {
      return topLevelUrl;
    }

    for (final candidate in info.mediaSources) {
      final candidateUrl = candidate.transcodingUrl?.trim();
      if (candidateUrl != null && candidateUrl.isNotEmpty) {
        return candidateUrl;
      }
    }

    return null;
  }

  bool _sourceMatchesSelection(
    EmbyMediaSourceDto source, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    if (audioStreamIndex != null &&
        !source.mediaStreams.any(
          (stream) =>
              stream.type.toLowerCase() == 'audio' &&
              stream.index == audioStreamIndex,
        )) {
      return false;
    }
    if (subtitleStreamIndex != null &&
        !source.mediaStreams.any(
          (stream) =>
              stream.type.toLowerCase() == 'subtitle' &&
              stream.index == subtitleStreamIndex,
        )) {
      return false;
    }
    return true;
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
