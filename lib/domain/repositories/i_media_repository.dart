import '../entities/media_item.dart';
import '../entities/media_library_info.dart';
import '../entities/season_info.dart';

abstract class IMediaRepository {
  // --- 基础查询 ---

  Future<List<MediaItem>> getMovies();

  Future<List<MediaItem>> getSeries();

  Future<MediaItem> getMediaDetail(MediaItem item);

  Future<List<MediaItem>> getPlayableItems(MediaItem item);

  // --- 通用查询 ---

  /// 获取继续观看 / 最近播放列表（跨后端通用）
  Future<List<MediaItem>> getRecentWatching({int limit = 50});

  /// 获取媒体库列表（电影库、剧集库、音乐库等）
  Future<List<MediaLibraryInfo>> getMediaLibraries();

  /// 获取指定剧集的季列表
  Future<List<SeasonInfo>> getSeasons(String seriesId);

  /// 获取指定季的剧集列表
  Future<List<MediaItem>> getEpisodesForSeason(
    String seriesId,
    int seasonNumber,
  );

  /// 按名称搜索媒体项
  Future<List<MediaItem>> search(String query, {int limit = 50});

  /// 通用媒体项查询，映射到各后端的原生 API
  ///
  /// [libraryId] 指定媒体库，为空则查询全部
  /// [includeItemTypes] 逗号分隔的类型，如 "Movie,Series,Episode,MusicAlbum"
  /// [limit] / [startIndex] 分页
  /// [sortBy] / [sortOrder] 排序
  Future<List<MediaItem>> getItems({
    String? libraryId,
    String? includeItemTypes,
    int? limit,
    int? startIndex,
    String? sortBy,
    String? sortOrder,
  });
}
