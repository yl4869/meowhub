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
    return _fetchByType('Movie');
  }

  @override
  Future<List<MediaItem>> getSeries() {
    return _fetchByType('Series');
  }

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    final accessToken = await _securityService.readAccessToken();
    final detailDto = await _apiClient.getMediaItemDetail(item.dataSourceId);
    final playableItems = await getPlayableItems(item);

    // 额外：尝试用 PlaybackInfo 聚合字幕信息，映射为实体的 subtitles 字段，便于 UI 直接获取
    List<SubtitleInfo> subtitles = const [];
    try {
      final info = await _apiClient.getPlaybackInfo(itemId: item.dataSourceId);
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

    return detailDto
        .toEntity(
          serverUrl: _apiClient.serverUrl,
          sourceType: item.sourceType,
          accessToken: accessToken,
          subtitles: subtitles,
        )
        .copyWith(playableItems: playableItems);
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (item.type == MediaType.movie) {
      return [item];
    }

    final accessToken = await _securityService.readAccessToken();
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

    return episodes.isEmpty ? [item] : episodes;
  }

  Future<List<MediaItem>> _fetchByType(String type) async {
    await _apiClient.authenticate();
    final accessToken = await _securityService.readAccessToken();
    final items = await _apiClient.getMediaItems(includeItemTypes: type);

    return items
        .map(
          (dto) => dto.toEntity(
            serverUrl: _apiClient.serverUrl,
            sourceType: WatchSourceType.emby,
            accessToken: accessToken,
          ),
        )
        .toList(growable: false);
  }
}
