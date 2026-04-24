import 'package:flutter/foundation.dart';

import '../../core/utils/app_diagnostics.dart';
import '../../core/services/security_service.dart';
import '../../data/datasources/emby_api_client.dart';
import '../../data/models/emby/emby_media_mapper.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/i_media_repository.dart';

/// Refactor reason:
/// The concrete Emby repository owns all remote orchestration and DTO mapping,
/// so upper layers depend only on `IMediaRepository`.
class EmbyMediaRepositoryImpl implements IMediaRepository {
  EmbyMediaRepositoryImpl({
    required EmbyApiClient apiClient,
    required SecurityService securityService,
  }) : _apiClient = apiClient,
       _securityService = securityService;

  final EmbyApiClient _apiClient;
  final SecurityService _securityService;

  @override
  Future<List<MediaItem>> getMovies() {
    if (kDebugMode) {
      debugPrint('[Diag][EmbyMediaRepository] getMovies:start');
    }
    return _fetchByType('Movie');
  }

  @override
  Future<List<MediaItem>> getSeries() {
    if (kDebugMode) {
      debugPrint('[Diag][EmbyMediaRepository] getSeries:start');
    }
    return _fetchByType('Series');
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyMediaRepository] getMediaDetail:start | '
        'itemId=${item.dataSourceId}, type=${item.type.name}',
      );
    }
    final accessToken = await _securityService.readAccessToken(
      namespace: _apiClient.securityNamespace,
    );
    final detailDto = await _apiClient.getMediaItemDetail(item.dataSourceId);
    final detailItem = detailDto.toEntity(
      serverUrl: _apiClient.serverUrl,
      sourceType: item.sourceType,
      accessToken: accessToken,
      subtitles: const [],
    );
    final baseItem = detailItem.copyWith(
      playbackProgress: item.playbackProgress,
      posterUrl: detailItem.posterUrl ?? item.posterUrl,
      backdropUrl: detailItem.backdropUrl ?? item.backdropUrl,
    );
    final playableItems = await getPlayableItems(baseItem);

    // Emby 的 PlaybackInfo 需要针对可播放项请求。
    // 对剧集容器直接请求常会触发 500，因此这里只对电影详情预拉字幕。
    List<SubtitleInfo> subtitles = const [];
    if (!_isEpisodeItem(item) && item.type == MediaType.movie) {
      try {
        final info = await _apiClient.getPlaybackInfo(
          itemId: item.dataSourceId,
        );
        final allStreams = info.mediaSources.expand((s) => s.mediaStreams);
        subtitles = allStreams
            .where((s) => s.type.toLowerCase() == 'subtitle')
            .map(
              (s) => SubtitleInfo(
                mediaSourceId: info.mediaSources
                    .firstWhere((ms) => ms.mediaStreams.contains(s))
                    .id,
                streamIndex: s.index,
                title: s.displayTitle ?? '字幕 ${s.index}',
                language: s.language,
                codec: s.codec,
                isExternal: s.isExternal,
                isDefault: s.isDefault,
              ),
            )
            .toList(growable: false);
      } catch (_) {
        // 字幕获取失败不影响主体详情
      }
    }

    final result = baseItem.copyWith(
      subtitles: subtitles,
      playableItems: playableItems,
    );
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyMediaRepository] getMediaDetail:success | '
        'itemId=${item.dataSourceId}, '
        'playableItemCount=${playableItems.length}, '
        'subtitleCount=${subtitles.length}',
      );
    }
    return result;
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyMediaRepository] getPlayableItems:start | '
        'itemId=${item.dataSourceId}, type=${item.type.name}',
      );
    }
    if (item.type == MediaType.movie || _isEpisodeItem(item)) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyMediaRepository] getPlayableItems:single_item | '
          'itemId=${item.dataSourceId}',
        );
      }
      return [item];
    }

    final accessToken = await _securityService.readAccessToken(
      namespace: _apiClient.securityNamespace,
    );
    final items = await _apiClient.getEpisodes(item.dataSourceId);
    final episodes = items
        .map(
          (dto) => dto.toEntity(
            serverUrl: _apiClient.serverUrl,
            sourceType: item.sourceType,
            accessToken: accessToken,
          ),
        )
        .toList(growable: false);

    final result = episodes.isEmpty ? [item] : episodes;
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyMediaRepository] getPlayableItems:success | '
        'itemId=${item.dataSourceId}, count=${result.length}',
      );
    }
    return result;
  }

  Future<List<MediaItem>> _fetchByType(String type) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyMediaRepository] fetchByType:start | type=$type',
      );
    }
    try {
      await _apiClient.authenticate();
      final accessToken = await _securityService.readAccessToken(
        namespace: _apiClient.securityNamespace,
      );
      final items = await _apiClient.getMediaItems(includeItemTypes: type);

      final result = items
          .map(
            (dto) => dto.toEntity(
              serverUrl: _apiClient.serverUrl,
              sourceType: WatchSourceType.emby,
              accessToken: accessToken,
            ),
          )
          .toList(growable: false);
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyMediaRepository] fetchByType:success | '
          'type=$type, count=${result.length}',
        );
      }
      return result;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyMediaRepository] fetchByType:failed | '
          'type=$type, error=${AppDiagnostics.summarizeError(error)}',
        );
        debugPrint(stackTrace.toString());
      }
      rethrow;
    }
  }

  bool _isEpisodeItem(MediaItem item) {
    if (item.type != MediaType.series) {
      return false;
    }
    return item.parentTitle != null || item.indexNumber != null;
  }
}
