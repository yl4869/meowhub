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

  static const Set<String> _imageSubtitleCodecs = {
    'pgs',
    'pgssub',
    'sup',
    'dvdsub',
    'sub',
    'idx',
  };

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
    bool preferTranscoding = false,
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
      preferTranscoding: preferTranscoding,
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
      preferTranscoding: preferTranscoding,
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
    bool preferTranscoding = false,
  }) async {
    final info = await _apiClient.getPlaybackInfo(
      itemId: item.dataSourceId,
      maxStreamingBitrate: maxStreamingBitrate,
      requireAvc: requireAvc,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      playSessionId: playSessionId,
      preferTranscoding: preferTranscoding,
    );

    final source = _pickBestSource(
      info,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    final transcodingUrl = _resolveTranscodingUrl(info, source);

    final token =
        await _securityService.readAccessToken(
          namespace: _apiClient.securityNamespace,
        ) ??
        '';
    final userId = await _securityService.readUserId(
      namespace: _apiClient.securityNamespace,
    );

    final resolvedAccess = _resolvePlaybackAccess(
      item,
      info,
      source,
      token: token,
      userId: userId,
      transcodingUrl: transcodingUrl,
      playSessionId: info.playSessionId ?? playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      maxStreamingBitrate: maxStreamingBitrate,
    );

    // 1. 映射音轨与字幕（注入全量元数据）
    var audio = _mapAudioStreams(source.mediaStreams);
    if (audio.isEmpty) {
      final allStreams = info.mediaSources
          .expand((s) => s.mediaStreams)
          .toList();
      audio = _mapAudioStreams(allStreams);
    }
    var subs = await _mapMergedSubtitleStreams(
      itemId: item.dataSourceId,
      selectedSourceId: source.id,
      mediaSources: info.mediaSources,
      token: token,
      playSessionId: info.playSessionId ?? playSessionId,
    );
    final detail = await _apiClient.getMediaItemDetail(item.dataSourceId);
    if (detail.mediaSources.isNotEmpty) {
      final detailSubs = await _mapMergedSubtitleStreams(
        itemId: item.dataSourceId,
        selectedSourceId: source.id,
        mediaSources: detail.mediaSources,
        token: token,
        playSessionId: info.playSessionId ?? playSessionId,
      );
      subs = _mergeSubtitleStreams(subs, detailSubs);
    }
    // 2. 解析章节与标记 (直接调用类末尾的方法)
    final chapters = _parseChapters(source.chapters);
    final markers = _parseMarkers(source.markers);
    final videoInfo = _resolveVideoInfo(
      source,
      playbackUrl: resolvedAccess.url,
      isTranscoding: resolvedAccess.isTranscoding,
    );

    return PlaybackPlan(
      url: resolvedAccess.url,
      isTranscoding: resolvedAccess.isTranscoding,
      playSessionId: info.playSessionId ?? playSessionId,
      mediaSourceId: source.id,
      audioStreams: audio,
      subtitleStreams: subs,
      chapters: chapters,
      markers: markers,
      videoInfo: videoInfo,
    );
  }

  void _evictExpiredEntries() {
    _resolvedPlans.removeWhere((_, entry) => entry.isExpired);
  }

  // --- 提炼后的私有映射方法 ---

  List<PlaybackStream> _mapAudioStreams(List<EmbyMediaStreamDto> streams) {
    return streams
        .where((s) => s.type.toLowerCase() == 'audio')
        .map(
          (s) => PlaybackStream(
            index: s.index,
            title: _buildAudioStreamTitle(s),
            language: _pickRawLanguageLabel(s),
            codec: s.codec,
            channels: s.channels,
            bitrate: s.bitrate,
            isDefault: s.isDefault,
          ),
        )
        .toList(growable: false);
  }

  Future<List<PlaybackStream>> _mapMergedSubtitleStreams({
    required String itemId,
    required String selectedSourceId,
    required List<EmbyMediaSourceDto> mediaSources,
    required String token,
    required String? playSessionId,
  }) async {
    final mapped = <PlaybackStream>[];
    final seenKeys = <String>{};

    Future<void> collectFromSource(EmbyMediaSourceDto source) async {
      for (final stream in source.mediaStreams) {
        if (stream.type.toLowerCase() != 'subtitle') {
          continue;
        }
        final resolvedDeliveryUrl = await _resolveSubtitleDeliveryUrl(
          itemId: itemId,
          stream: stream,
          mediaSourceId: source.id,
          token: token,
          playSessionId: playSessionId,
          sourceSupportsDirectPlay: source.supportsDirectPlay,
        );
        final playbackStream = PlaybackStream(
          index: stream.index,
          title: _buildSubtitleStreamTitle(stream),
          language: _pickRawLanguageLabel(stream),
          codec: stream.codec,
          deliveryMethod: stream.deliveryMethod,
          subtitleLocationType: stream.subtitleLocationType,
          supportsExternalStream: stream.supportsExternalStream,
          isDefault: stream.isDefault,
          isExternal: stream.isExternal,
          isTextSubtitleStream: stream.isTextSubtitleStream,
          deliveryUrl: resolvedDeliveryUrl,
        );
        final dedupeKey = [
          playbackStream.index,
          playbackStream.title,
          playbackStream.language ?? '',
          (playbackStream.codec ?? '').toLowerCase(),
          playbackStream.isExternal,
          playbackStream.isTextSubtitleStream,
        ].join('|');
        if (seenKeys.add(dedupeKey)) {
          mapped.add(playbackStream);
        }
      }
    }

    final selectedSource = mediaSources.where(
      (source) => source.id == selectedSourceId,
    );
    for (final source in selectedSource) {
      await collectFromSource(source);
    }
    for (final source in mediaSources) {
      if (source.id == selectedSourceId) {
        continue;
      }
      await collectFromSource(source);
    }

    return mapped;
  }

  Future<String?> _resolveSubtitleDeliveryUrl({
    required String itemId,
    required EmbyMediaStreamDto stream,
    required String mediaSourceId,
    required String token,
    required String? playSessionId,
    required bool sourceSupportsDirectPlay,
  }) async {
    final codec = stream.codec?.trim().toLowerCase();
    final shouldUseInternalSelection = _shouldUseInternalSubtitleSelection(
      stream,
      codec: codec,
      sourceSupportsDirectPlay: sourceSupportsDirectPlay,
    );
    if (shouldUseInternalSelection) {
      return null;
    }
    final shouldPreferTranscodedDelivery =
        _shouldPreferTranscodedSubtitleDelivery(
          stream,
          codec: codec,
          sourceSupportsDirectPlay: sourceSupportsDirectPlay,
        );
    final directDeliveryUrl = stream.deliveryUrl?.trim();
    if (!shouldPreferTranscodedDelivery &&
        directDeliveryUrl != null &&
        directDeliveryUrl.isNotEmpty) {
      return _buildAuthorizedSubtitleUrl(
        directDeliveryUrl,
        token,
        playSessionId: playSessionId,
      );
    }

    if (mediaSourceId.trim().isEmpty) {
      return null;
    }
    if (shouldPreferTranscodedDelivery) {
      return _apiClient.buildSubtitleVttUrl(
        itemId: itemId,
        streamIndex: stream.index,
        mediaSourceId: mediaSourceId,
        deliveryUrl: directDeliveryUrl,
        playSessionId: playSessionId,
      );
    }
    return _apiClient.buildSubtitleStreamUrl(
      itemId: itemId,
      streamIndex: stream.index,
      mediaSourceId: mediaSourceId,
      deliveryUrl: directDeliveryUrl,
      codec: codec,
      playSessionId: playSessionId,
    );
  }

  bool _shouldPreferTranscodedSubtitleDelivery(
    EmbyMediaStreamDto stream, {
    String? codec,
    required bool sourceSupportsDirectPlay,
  }) {
    if (_shouldUseInternalSubtitleSelection(
      stream,
      codec: codec,
      sourceSupportsDirectPlay: sourceSupportsDirectPlay,
    )) {
      return false;
    }
    if (stream.isTextSubtitleStream) {
      return false;
    }
    if (codec != null && _imageSubtitleCodecs.contains(codec)) {
      return false;
    }
    final deliveryMethod = stream.deliveryMethod?.trim().toLowerCase();
    return deliveryMethod == 'encode';
  }

  bool _shouldUseInternalSubtitleSelection(
    EmbyMediaStreamDto stream, {
    String? codec,
    required bool sourceSupportsDirectPlay,
  }) {
    if (!sourceSupportsDirectPlay || stream.isExternal) {
      return false;
    }
    final normalizedLocation = stream.subtitleLocationType
        ?.trim()
        .toLowerCase();
    if (normalizedLocation == 'internalstream') {
      return true;
    }
    final deliveryMethod = stream.deliveryMethod?.trim().toLowerCase();
    if (deliveryMethod != 'embed') {
      return false;
    }
    if (stream.isTextSubtitleStream) {
      return false;
    }
    return codec == null || _imageSubtitleCodecs.contains(codec);
  }

  List<PlaybackStream> _mergeSubtitleStreams(
    List<PlaybackStream> primary,
    List<PlaybackStream> fallback,
  ) {
    final merged = <PlaybackStream>[...primary];
    final seenKeys = primary
        .map(
          (stream) => [
            stream.index,
            stream.title,
            stream.language ?? '',
            (stream.codec ?? '').toLowerCase(),
            stream.isExternal,
            stream.isTextSubtitleStream,
          ].join('|'),
        )
        .toSet();
    for (final stream in fallback) {
      final key = [
        stream.index,
        stream.title,
        stream.language ?? '',
        (stream.codec ?? '').toLowerCase(),
        stream.isExternal,
        stream.isTextSubtitleStream,
      ].join('|');
      if (seenKeys.add(key)) {
        merged.add(stream);
      }
    }
    return merged;
  }

  List<VideoChapter> _parseChapters(List<EmbyChapterDto>? dtos) {
    if (dtos == null) return const [];
    return dtos
        .map(
          (c) => VideoChapter(
            title: c.name ?? '',
            startTime: embyTicksToDuration(c.startTicks),
          ),
        )
        .toList(growable: false);
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

  PlaybackVideoInfo? _resolveVideoInfo(
    EmbyMediaSourceDto source, {
    required String playbackUrl,
    required bool isTranscoding,
  }) {
    final videoStream = source.mediaStreams
        .cast<EmbyMediaStreamDto?>()
        .firstWhere(
          (stream) => stream?.type.toLowerCase() == 'video',
          orElse: () => null,
        );
    if (videoStream == null) {
      return null;
    }

    final playbackUri = Uri.tryParse(playbackUrl);
    final query = playbackUri?.queryParameters ?? const <String, String>{};

    return PlaybackVideoInfo(
      width: _firstPositiveInt(
        query['MaxWidth'],
        query['Width'],
        videoStream.width?.toString(),
      ),
      height: _firstPositiveInt(
        query['MaxHeight'],
        query['Height'],
        videoStream.height?.toString(),
      ),
      sourceWidth: videoStream.width,
      sourceHeight: videoStream.height,
      bitrate: _firstPositiveInt(
        query['VideoBitrate'],
        query['Bitrate'],
        videoStream.bitrate?.toString(),
      ),
      codec: videoStream.codec,
      isTranscoding: isTranscoding,
    );
  }

  EmbyMediaSourceDto _pickBestSource(
    EmbyPlaybackInfoDto info, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    if (info.mediaSources.isEmpty) {
      throw StateError('No media sources available');
    }

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

    return uri.replace(queryParameters: qp).toString();
  }

  String _buildAuthorizedSubtitleUrl(
    String rawUrl,
    String token, {
    String? playSessionId,
  }) {
    return _buildAuthorizedUrl(rawUrl, token, playSessionId: playSessionId);
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

  _ResolvedPlaybackAccess _resolvePlaybackAccess(
    MediaItem item,
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source, {
    required String token,
    String? userId,
    String? transcodingUrl,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? maxStreamingBitrate,
  }) {
    final serverSuggestedUrl = _resolveServerSuggestedPlaybackUrl(
      info,
      source,
      token: token,
      userId: userId,
      playSessionId: playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
    final directUrl = _buildDirectPlaybackUrl(
      item,
      source,
      token: token,
      userId: userId,
      playSessionId: playSessionId,
    );
    final directPlayableUrl = _resolveServerSuggestedDirectUrl(
      source,
      token: token,
      userId: userId,
      playSessionId: playSessionId,
    );
    final shouldPreferServerUrl = _shouldPreferServerSuggestedUrl(
      source,
      transcodingUrl: transcodingUrl,
      subtitleStreamIndex: subtitleStreamIndex,
      maxStreamingBitrate: maxStreamingBitrate,
    );

    final resolved = shouldPreferServerUrl && serverSuggestedUrl != null
        ? _ResolvedPlaybackAccess(
            url: serverSuggestedUrl,
            isTranscoding: true,
            mode: 'ServerSuggested',
            reason: 'emby_playback_info_recommended',
          )
        : _ResolvedPlaybackAccess(
            url: directPlayableUrl ?? directUrl,
            isTranscoding: false,
            mode: directPlayableUrl != null
                ? 'ServerDirectStream'
                : 'ClientDirect',
            reason: shouldPreferServerUrl
                ? 'server_url_missing_fallback_to_direct'
                : directPlayableUrl != null
                ? 'playback_info_direct_stream'
                : 'client_prefers_direct',
          );

    return resolved;
  }

  String _buildDirectPlaybackUrl(
    MediaItem item,
    EmbyMediaSourceDto source, {
    required String token,
    String? userId,
    String? playSessionId,
  }) {
    final uri = Uri.parse(
      '${_apiClient.serverUrl}/emby/Videos/${item.dataSourceId}/stream',
    );
    final qp = <String, String>{
      'Static': 'true',
      if (token.isNotEmpty) 'api_key': token,
      if (userId != null && userId.isNotEmpty) 'UserId': userId,
      if (source.id.isNotEmpty) 'MediaSourceId': source.id,
      if (playSessionId != null && playSessionId.isNotEmpty)
        'PlaySessionId': playSessionId,
    };

    return uri.replace(queryParameters: qp).toString();
  }

  String? _resolveServerSuggestedDirectUrl(
    EmbyMediaSourceDto source, {
    required String token,
    String? userId,
    String? playSessionId,
  }) {
    final candidate = source.directStreamUrl?.trim();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    return _buildAuthorizedUrl(
      candidate,
      token,
      userId: userId,
      mediaSourceId: source.id,
      playSessionId: playSessionId,
    );
  }

  String? _resolveServerSuggestedPlaybackUrl(
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source, {
    required String token,
    String? userId,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final candidate = source.transcodingUrl?.trim().isNotEmpty == true
        ? source.transcodingUrl!.trim()
        : info.transcodingUrl?.trim();
    if (candidate == null || candidate.isEmpty) {
      return null;
    }
    return _buildAuthorizedUrl(
      candidate,
      token,
      userId: userId,
      mediaSourceId: source.id,
      playSessionId: playSessionId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
  }

  bool _shouldPreferServerSuggestedUrl(
    EmbyMediaSourceDto source, {
    required String? transcodingUrl,
    required int? subtitleStreamIndex,
    required int? maxStreamingBitrate,
  }) {
    if ((transcodingUrl ?? '').isEmpty) {
      return false;
    }
    if (!source.supportsDirectPlay) {
      return true;
    }
    // 内嵌图像字幕（PGS 等）需要服务端烧录，必须走转码
    if (subtitleStreamIndex != null) {
      final subtitleStream = source.mediaStreams
          .cast<EmbyMediaStreamDto?>()
          .firstWhere(
            (s) =>
                s != null &&
                s.type.toLowerCase() == 'subtitle' &&
                s.index == subtitleStreamIndex,
            orElse: () => null,
          );
      if (subtitleStream != null) {
        final codec = (subtitleStream.codec ?? '').trim().toLowerCase();
        if (_imageSubtitleCodecs.contains(codec) &&
            !subtitleStream.isExternal &&
            subtitleStream.subtitleLocationType
                    ?.trim()
                    .toLowerCase() ==
                'internalstream') {
          return true;
        }
      }
    }
    final sourceBitrate = source.bitrate;
    if (maxStreamingBitrate != null &&
        maxStreamingBitrate > 0 &&
        sourceBitrate != null &&
        sourceBitrate > maxStreamingBitrate) {
      return true;
    }
    return false;
  }

  int? _normalizeSelectedIndex(int? index) =>
      (index == null || index < 0) ? null : index;

  int? _firstPositiveInt(String? first, String? second, String? fallback) {
    for (final value in [first, second, fallback]) {
      final parsed = int.tryParse(value ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  String? _resolveTranscodingUrl(
    EmbyPlaybackInfoDto info,
    EmbyMediaSourceDto source,
  ) {
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

class _ResolvedPlaybackAccess {
  const _ResolvedPlaybackAccess({
    required this.url,
    required this.isTranscoding,
    required this.mode,
    required this.reason,
  });

  final String url;
  final bool isTranscoding;
  final String mode;
  final String reason;
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
    required this.preferTranscoding,
  });

  final String namespace;
  final String itemId;
  final int? maxStreamingBitrate;
  final bool? requireAvc;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? playSessionId;
  final bool preferTranscoding;

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
        other.preferTranscoding == preferTranscoding;
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
    preferTranscoding,
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
