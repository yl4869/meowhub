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
  Future<List<MediaItem>> getRecentWatching() async {
    await _apiClient.authenticate();
    final accessToken = await _securityService.readAccessToken(
      namespace: _apiClient.securityNamespace,
    );
    final items = await _apiClient.getResumeItems();

    return items
        .map((item) => _mapResumeItemToEntity(item, accessToken: accessToken))
        .whereType<MediaItem>()
        .toList(growable: false);
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

    return baseItem.copyWith(
      subtitles: subtitles,
      playableItems: playableItems,
    );
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

    return episodes.isEmpty ? [item] : episodes;
  }

  Future<List<MediaItem>> _fetchByType(String type) async {
    await _apiClient.authenticate();
    final accessToken = await _securityService.readAccessToken(
      namespace: _apiClient.securityNamespace,
    );
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

  MediaItem? _mapResumeItemToEntity(
    Map<String, dynamic> item, {
    required String? accessToken,
  }) {
    final itemId = item['Id']?.toString().trim() ?? '';
    if (itemId.isEmpty) {
      return null;
    }

    final typeValue = item['Type']?.toString();
    final isEpisode = typeValue?.toLowerCase() == 'episode';
    final title = isEpisode
        ? (item['SeriesName']?.toString().trim().isNotEmpty == true
              ? item['SeriesName'].toString().trim()
              : item['Name']?.toString().trim() ?? '未命名视频')
        : (item['Name']?.toString().trim().isNotEmpty == true
              ? item['Name'].toString().trim()
              : '未命名视频');

    final playbackPositionTicks =
        (item['UserData'] as Map?)?['PlaybackPositionTicks'] as num? ?? 0;
    final runTimeTicks = item['RunTimeTicks'] as num? ?? 0;
    final progress = runTimeTicks.toInt() > 0
        ? MediaPlaybackProgress(
            position: Duration(
              milliseconds: playbackPositionTicks.toInt() ~/ 10000,
            ),
            duration: Duration(milliseconds: runTimeTicks.toInt() ~/ 10000),
          )
        : null;

    return MediaItem(
      id: _stableNumericId(itemId),
      sourceId: itemId,
      title: title,
      originalTitle: item['OriginalTitle']?.toString().trim().isNotEmpty == true
          ? item['OriginalTitle'].toString().trim()
          : title,
      type: MediaType.fromValue(typeValue),
      sourceType: WatchSourceType.emby,
      posterUrl: _buildResumePrimaryImageUrl(item),
      backdropUrl: _buildResumeBackdropUrl(item),
      year: (item['ProductionYear'] as num?)?.toInt(),
      overview: item['Overview']?.toString() ?? '',
      playUrl: _buildPlaybackUrl(_apiClient.serverUrl, itemId, accessToken),
      playbackProgress: progress,
      parentTitle: item['SeriesName']?.toString(),
      indexNumber: (item['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (item['ParentIndexNumber'] as num?)?.toInt(),
    );
  }

  bool _isEpisodeItem(MediaItem item) {
    if (item.type != MediaType.series) {
      return false;
    }
    return item.parentTitle != null || item.indexNumber != null;
  }

  String? _buildResumePrimaryImageUrl(Map<String, dynamic> item) {
    final itemId = item['Id']?.toString();
    if (itemId == null || itemId.isEmpty) {
      return null;
    }
    final imageTags = item['ImageTags'];
    final primaryTag = imageTags is Map
        ? imageTags['Primary']?.toString()
        : null;
    if (primaryTag != null && primaryTag.isNotEmpty) {
      return '${_apiClient.serverUrl}/emby/Items/$itemId/Images/Primary?tag=$primaryTag&maxHeight=720';
    }
    final seriesPrimaryTag = item['SeriesPrimaryImageTag']?.toString();
    final seriesId = item['SeriesId']?.toString();
    if (seriesPrimaryTag != null &&
        seriesPrimaryTag.isNotEmpty &&
        seriesId != null &&
        seriesId.isNotEmpty) {
      return '${_apiClient.serverUrl}/emby/Items/$seriesId/Images/Primary?tag=$seriesPrimaryTag&maxHeight=720';
    }
    return null;
  }

  String? _buildResumeBackdropUrl(Map<String, dynamic> item) {
    final itemId = item['Id']?.toString();
    if (itemId == null || itemId.isEmpty) {
      return null;
    }
    final rawTags = item['BackdropImageTags'] as List<dynamic>? ?? const [];
    final backdropTag = rawTags
        .map((tag) => tag.toString())
        .firstWhere((tag) => tag.isNotEmpty, orElse: () => '');
    if (backdropTag.isEmpty) {
      return null;
    }
    return '${_apiClient.serverUrl}/emby/Items/$itemId/Images/Backdrop/0?tag=$backdropTag&maxWidth=1280';
  }

  String? _buildPlaybackUrl(
    String serverUrl,
    String itemId,
    String? accessToken,
  ) {
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }

    return '$serverUrl/emby/Videos/$itemId/stream?Static=true&api_key=$accessToken';
  }

  int _stableNumericId(String value) {
    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
