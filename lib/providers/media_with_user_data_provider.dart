import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import 'media_library_provider.dart';
import 'user_data_provider.dart';

/// 组合 Provider
/// 将媒体库数据与用户个人数据组合，提供带收藏/进度标记的媒体列表
class MediaWithUserDataProvider extends ChangeNotifier {
  MediaWithUserDataProvider({
    required MediaLibraryProvider mediaLibraryProvider,
    required UserDataProvider userDataProvider,
  }) : _mediaLibraryProvider = mediaLibraryProvider,
       _userDataProvider = userDataProvider {
    _mediaLibraryProvider.addListener(_onMediaLibraryChanged);
    _userDataProvider.addListener(_onUserDataChanged);
  }

  final MediaLibraryProvider _mediaLibraryProvider;
  final UserDataProvider _userDataProvider;

  // Computed properties
  List<MediaItem> get enrichedMovies {
    return _enrichMediaItems(_mediaLibraryProvider.state.movies);
  }

  List<MediaItem> get enrichedSeries {
    return _enrichMediaItems(_mediaLibraryProvider.state.series);
  }

  List<MediaItem> get allItems {
    return [...enrichedSeries, ...enrichedMovies];
  }

  List<MediaItem> get recentWatching {
    final itemByKey = {for (final item in allItems) item.mediaKey: item};
    final resolvedItems = <MediaItem>[];
    final seenKeys = <String>{};

    for (final historyItem in _userDataProvider.watchHistory) {
      final exactKey = '${historyItem.sourceType.name}:${historyItem.id}';
      final seriesKey = historyItem.seriesId == null
          ? null
          : '${historyItem.sourceType.name}:${historyItem.seriesId}';
      final matched =
          itemByKey[exactKey] ??
          (seriesKey == null ? null : itemByKey[seriesKey]);
      if (matched == null || !seenKeys.add(matched.mediaKey)) {
        continue;
      }
      resolvedItems.add(matched);
    }

    return resolvedItems;
  }

  bool get isLoading => _mediaLibraryProvider.state.isLoading;
  String? get errorMessage => _mediaLibraryProvider.state.errorMessage;

  // Private methods
  List<MediaItem> _enrichMediaItems(List<MediaItem> items) {
    return items
        .map((item) {
          final isFavorite = _userDataProvider.isFavorite(item.id);
          final progress = _userDataProvider.playbackProgressForItem(item);

          return item.copyWith(
            isFavorite: isFavorite,
            playbackProgress: progress,
          );
        })
        .toList(growable: false);
  }

  void _onMediaLibraryChanged() {
    _userDataProvider.initializeProgress([
      ..._mediaLibraryProvider.state.movies,
      ..._mediaLibraryProvider.state.series,
      ..._mediaLibraryProvider.state.recentWatching,
    ]);
    notifyListeners();
  }

  void _onUserDataChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _mediaLibraryProvider.removeListener(_onMediaLibraryChanged);
    _userDataProvider.removeListener(_onUserDataChanged);
    super.dispose();
  }
}
