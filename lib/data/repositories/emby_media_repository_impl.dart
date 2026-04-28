import '../../core/services/security_service.dart';
import '../../data/datasources/emby_api_client.dart';
import '../../data/models/emby/emby_media_item_dto.dart';
import '../../data/models/emby/emby_media_mapper.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_library_info.dart';
import '../../domain/entities/season_info.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../models/emby/emby_resume_item_dto.dart';

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
    return _fetchByType('Movie');
  }

  @override
  Future<List<MediaItem>> getSeries() {
    return _fetchByType('Series');
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
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
    return result;
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (item.type == MediaType.movie || _isEpisodeItem(item)) {
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
    return result;
  }

  Future<List<MediaItem>> _fetchByType(String type) async {
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
      return result;
    } catch (error) {
      rethrow;
    }
  }

  bool _isEpisodeItem(MediaItem item) {
    if (item.type != MediaType.series) {
      return false;
    }
    return item.parentTitle != null || item.indexNumber != null;
  }

  @override
  Future<List<MediaItem>> getRecentWatching({int limit = 50}) async {
    try {
      await _apiClient.authenticate();
      final accessToken = await _securityService.readAccessToken(
        namespace: _apiClient.securityNamespace,
      );
      final resumeItems = await _apiClient.getContinueWatching();

      return resumeItems
          .take(limit)
          .map((dto) => _mapResumeItemToEntity(dto, accessToken))
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<List<MediaItem>> getEpisodesForSeason(
    String seriesId,
    int seasonNumber,
  ) async {
    try {
      await _apiClient.authenticate();
      final accessToken = await _securityService.readAccessToken(
        namespace: _apiClient.securityNamespace,
      );
      final dtos = await _apiClient.getEpisodes(
        seriesId,
        seasonNumber: seasonNumber,
      );
      return dtos
          .map(
            (dto) => dto.toEntity(
              serverUrl: _apiClient.serverUrl,
              sourceType: WatchSourceType.emby,
              accessToken: accessToken,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<List<SeasonInfo>> getSeasons(String seriesId) async {
    try {
      await _apiClient.authenticate();
      final dtos = await _apiClient.getSeasons(seriesId);

      return dtos
          .map(
            (dto) => SeasonInfo(
              id: dto.id,
              name: dto.name,
              seriesId: seriesId,
              indexNumber: dto.indexNumber ?? 0,
              posterUrl: dto.imageTags?.primary != null
                  ? '${_apiClient.serverUrl}/emby/Items/${dto.id}/Images/Primary?tag=${dto.imageTags!.primary}&maxHeight=720'
                  : null,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<List<MediaItem>> search(String query, {int limit = 50}) async {
    try {
      await _apiClient.authenticate();
      final accessToken = await _securityService.readAccessToken(
        namespace: _apiClient.securityNamespace,
      );

      final dtos = await _fetchSearchResults(query, limit);

      return dtos
          .map(
            (dto) => dto.toEntity(
              serverUrl: _apiClient.serverUrl,
              sourceType: WatchSourceType.emby,
              accessToken: accessToken,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
  }

  Future<List<EmbyMediaItemDto>> _fetchSearchResults(
    String query,
    int limit,
  ) async {
    try {
      return await _apiClient.getMediaItems(
        includeItemTypes: 'Movie,Series,Episode',
        searchTerm: query,
        limit: limit,
      );
    } catch (_) {
      return await _apiClient.getSearchHints(
        searchTerm: query,
        includeItemTypes: 'Movie,Series,Episode',
        limit: limit,
      );
    }
  }

  @override
  Future<List<MediaLibraryInfo>> getMediaLibraries() async {
    try {
      await _apiClient.authenticate();
      final libraryList = await _apiClient.getMediaLibraries();

      return libraryList.items
          .map(
            (dto) => MediaLibraryInfo(
              id: dto.id,
              name: dto.name,
              collectionType: (dto.collectionType ?? dto.type ?? 'mixed')
                  .toLowerCase(),
              imageUrl: dto.id.isNotEmpty
                  ? '${_apiClient.serverUrl}/emby/Items/${dto.id}/Images/Primary'
                  : null,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      rethrow;
    }
  }

  @override
  Future<List<MediaItem>> getItems({
    String? libraryId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      await _apiClient.authenticate();
      final accessToken = await _securityService.readAccessToken(
        namespace: _apiClient.securityNamespace,
      );

      // 优先用类型过滤，兼容现有 getMediaItems 签名
      final effectiveTypes = includeItemTypes ?? 'Movie,Series,Episode';
      final items = await _apiClient.getMediaItems(
        includeItemTypes: effectiveTypes,
        libraryId: libraryId,
        limit: limit ?? 100,
      );

      final result = items
          .map(
            (dto) => dto.toEntity(
              serverUrl: _apiClient.serverUrl,
              sourceType: WatchSourceType.emby,
              accessToken: accessToken,
            ),
          )
          .toList(growable: false);

      // 简易排序（服务端已排，客户端只做 fallback）
      if (sortBy == 'DateCreated' && sortOrder == 'Descending') {
        result.sort(
          (a, b) => (b.year ?? 0).compareTo(a.year ?? 0),
        );
      }

      return result;
    } catch (error) {
      rethrow;
    }
  }

  MediaItem _mapResumeItemToEntity(
    EmbyResumeItemDto dto,
    String? accessToken,
  ) {
    final durationTicks = dto.runTimeTicks;
    final positionTicks = dto.playbackPositionTicks;

    return MediaItem(
      id: _stableHash(dto.id),
      sourceId: dto.id,
      title: dto.name,
      originalTitle: dto.originalTitle?.trim().isNotEmpty == true
          ? dto.originalTitle!.trim()
          : dto.name,
      type: MediaType.fromValue(dto.type),
      sourceType: WatchSourceType.emby,
      posterUrl: dto.posterUrl,
      backdropUrl: dto.backdropUrl,
      overview: dto.overview ?? '',
      year: dto.productionYear,
      seriesId: dto.seriesId,
      parentTitle: dto.seriesName,
      indexNumber: dto.indexNumber,
      parentIndexNumber: dto.parentIndexNumber,
      lastPlayedAt: dto.lastPlayedDate != null
          ? DateTime.tryParse(dto.lastPlayedDate!)
          : null,
      playbackProgress: durationTicks > 0
          ? MediaPlaybackProgress(
              position: Duration(milliseconds: positionTicks ~/ 10000),
              duration: Duration(milliseconds: durationTicks ~/ 10000),
            )
          : null,
    );
  }

  static int _stableHash(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;

    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
