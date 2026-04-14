import '../../domain/entities/media_item.dart';
import '../../domain/repositories/i_media_repository.dart';

class EmptyMediaRepositoryImpl implements IMediaRepository {
  const EmptyMediaRepositoryImpl();

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    return item;
  }

  @override
  Future<List<MediaItem>> getRecentWatching() async {
    return const [];
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
}
