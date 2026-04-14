import '../entities/media_item.dart';

abstract class IMediaRepository {
  Future<List<MediaItem>> getMovies();

  Future<List<MediaItem>> getSeries();

  Future<MediaItem> getMediaDetail(MediaItem item);

  Future<List<MediaItem>> getPlayableItems(MediaItem item);
}
