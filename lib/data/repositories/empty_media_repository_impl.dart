import 'package:flutter/foundation.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/repositories/i_media_repository.dart';

class EmptyMediaRepositoryImpl implements IMediaRepository {
  const EmptyMediaRepositoryImpl();

  @override
  Future<MediaItem> getMediaDetail(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmptyMediaRepository] getMediaDetail | '
        'itemId=${item.dataSourceId}',
      );
    }
    return item;
  }

  @override
  Future<List<MediaItem>> getMovies() async {
    if (kDebugMode) {
      debugPrint('[Diag][EmptyMediaRepository] getMovies');
    }
    return const [];
  }

  @override
  Future<List<MediaItem>> getPlayableItems(MediaItem item) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmptyMediaRepository] getPlayableItems | '
        'itemId=${item.dataSourceId}, type=${item.type.name}',
      );
    }
    return item.type == MediaType.movie ? [item] : const [];
  }

  @override
  Future<List<MediaItem>> getSeries() async {
    if (kDebugMode) {
      debugPrint('[Diag][EmptyMediaRepository] getSeries');
    }
    return const [];
  }
}
