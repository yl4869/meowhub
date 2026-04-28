import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_library_info.dart';
import '../../domain/entities/season_info.dart';
import '../../domain/repositories/i_media_repository.dart';

class EmptyMediaRepositoryImpl implements IMediaRepository {
  const EmptyMediaRepositoryImpl();

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    return item;
  }

  @override
  Future<List<MediaItem>> getMovies() async {
    return const [];
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    return item.type == MediaType.movie ? [item] : const [];
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    return const [];
  }

  @override
  Future<List<MediaItem>> getRecentWatching({int limit = 50}) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> getEpisodesForSeason(
    String seriesId,
    int seasonNumber,
  ) async {
    return const [];
  }

  @override
  Future<List<MediaItem>> search(String query, {int limit = 50}) async {
    return const [];
  }

  @override
  Future<List<SeasonInfo>> getSeasons(String seriesId) async {
    return const [];
  }

  @override
  Future<List<MediaLibraryInfo>> getMediaLibraries() async {
    return const [];
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
    return const [];
  }
}
