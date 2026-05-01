import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import '../domain/entities/media_library_info.dart';
import '../domain/entities/watch_history_item.dart';
import 'media_library_provider.dart';
import 'user_data_provider.dart';

class MediaWithUserDataProvider extends ChangeNotifier {
  MediaWithUserDataProvider({
    required MediaLibraryProvider mediaLibraryProvider,
    required UserDataProvider userDataProvider,
  }) : _mediaLibraryProvider = mediaLibraryProvider,
       _userDataProvider = userDataProvider {
    _attachListeners();
    _initialSync();
  }

  static const Duration _updateCoalesceWindow = Duration(seconds: 2);

  MediaLibraryProvider _mediaLibraryProvider;
  UserDataProvider _userDataProvider;

  List<MediaItem> _cachedContinueWatching = [];
  List<MediaItem> _cachedRecentlyAdded = [];
  Map<String, List<MediaItem>> _cachedLibraryItems = {};
  List<MediaItem> _cachedAllItems = [];
  int _cachedFavoriteCount = 0;

  DateTime _lastUpdateCacheTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pendingUpdateCache = false;

  List<MediaLibraryInfo> get libraries => _mediaLibraryProvider.state.libraries;
  List<MediaItem> get continueWatching => _cachedContinueWatching;
  List<MediaItem> get recentlyAdded => _cachedRecentlyAdded;
  Map<String, List<MediaItem>> get libraryItems => _cachedLibraryItems;
  List<MediaItem> get allItems => _cachedAllItems;
  int get favoriteCount => _cachedFavoriteCount;
  bool get isLoading => _mediaLibraryProvider.state.isLoading;
  String? get errorMessage => _mediaLibraryProvider.state.errorMessage;

  void updateDependencies({
    required MediaLibraryProvider mediaLibrary,
    required UserDataProvider userData,
  }) {
    if (identical(_mediaLibraryProvider, mediaLibrary) &&
        identical(_userDataProvider, userData)) {
      return;
    }

    _detachListeners();
    _mediaLibraryProvider = mediaLibrary;
    _userDataProvider = userData;
    _attachListeners();

    _initialSync();
  }

  void _attachListeners() {
    _mediaLibraryProvider.addListener(_handleLibraryUpdate);
    _userDataProvider.addListener(_scheduleUpdateCache);
  }

  void _detachListeners() {
    _mediaLibraryProvider.removeListener(_handleLibraryUpdate);
    _userDataProvider.removeListener(_scheduleUpdateCache);
  }

  void _handleLibraryUpdate() {
    debugPrint('[MediaWithUserData] _handleLibraryUpdate: 媒体库状态变更, libraries=${_mediaLibraryProvider.state.libraries.length}, totalItems=${_mediaLibraryProvider.state.libraryItems.values.expand((i) => i).length}');
    _initialSync();
    _doUpdateCache();
  }

  void _scheduleUpdateCache() {
    final elapsed = DateTime.now().difference(_lastUpdateCacheTime);
    if (elapsed >= _updateCoalesceWindow) {
      _doUpdateCache();
      return;
    }
    if (_pendingUpdateCache) return;
    _pendingUpdateCache = true;
    Future<void>.delayed(_updateCoalesceWindow - elapsed, () {
      _pendingUpdateCache = false;
      _doUpdateCache();
    });
  }

  void _initialSync() {
    final allItems = _mediaLibraryProvider.state.libraryItems.values
        .expand((items) => items)
        .toList(growable: false);
    _userDataProvider.initializeProgress([
      ...allItems,
      ..._mediaLibraryProvider.state.continueWatching,
      ..._mediaLibraryProvider.state.recentlyAdded,
    ]);
  }

  void _doUpdateCache() {
    _lastUpdateCacheTime = DateTime.now();

    _cachedRecentlyAdded =
        _enrichMediaItems(_mediaLibraryProvider.state.recentlyAdded);

    _cachedLibraryItems = _mediaLibraryProvider.state.libraryItems.map(
      (key, items) => MapEntry(key, _enrichMediaItems(items)),
    );

    _cachedAllItems =
        _cachedLibraryItems.values.expand((items) => items).toList(growable: false);

    _cachedFavoriteCount =
        _cachedAllItems.where((item) => item.isFavorite).length;

    final itemLookup = <String, MediaItem>{};
    for (final items in _cachedLibraryItems.values) {
      for (final item in items) {
        itemLookup[item.mediaKey] = item;
      }
    }
    for (final item in _cachedRecentlyAdded) {
      itemLookup[item.mediaKey] = item;
    }

    final resolvedContinueWatching = <MediaItem>[];
    final seenMediaKeys = <String>{};

    for (final history in _userDataProvider.watchHistory) {
      final resolvedItem = _buildContinueWatchingItem(
        history: history,
        itemLookup: itemLookup,
      );
      if (resolvedItem != null && seenMediaKeys.add(resolvedItem.mediaKey)) {
        resolvedContinueWatching.add(resolvedItem);
      }
    }
    _cachedContinueWatching = resolvedContinueWatching;

    debugPrint('[MediaWithUserData] _doUpdateCache: continueWatching=${_cachedContinueWatching.length}, recentlyAdded=${_cachedRecentlyAdded.length}, libraryItems=${_cachedLibraryItems.length}, allItems=${_cachedAllItems.length}, favorites=$_cachedFavoriteCount');
    notifyListeners();
  }

  List<MediaItem> _enrichMediaItems(List<MediaItem> items) {
    return items
        .map((item) {
          return item.copyWith(
            isFavorite: _userDataProvider.isFavorite(item.id),
            playbackProgress: _userDataProvider.playbackProgressForItem(item),
          );
        })
        .toList(growable: false);
  }

  MediaItem? _buildContinueWatchingItem({
    required WatchHistoryItem history,
    required Map<String, MediaItem> itemLookup,
  }) {
    final seriesId = history.seriesId;
    if (seriesId != null && seriesId.isNotEmpty) {
      final seriesMatch = itemLookup['${history.sourceType.name}:$seriesId'];
      if (seriesMatch != null) {
        return _applyHistoryToMediaItem(base: seriesMatch, history: history);
      }

      return _buildFallbackContinueWatchingItem(
        history: history,
        sourceId: seriesId,
        title: history.parentTitle ?? history.title,
        originalTitle: history.originalTitle ?? history.parentTitle,
        type: MediaType.series,
      );
    }

    final directMatch = itemLookup[history.uniqueKey];
    if (directMatch != null) {
      return _applyHistoryToMediaItem(base: directMatch, history: history);
    }

    return _buildFallbackContinueWatchingItem(
      history: history,
      sourceId: history.id,
      title: history.title,
      originalTitle: history.originalTitle,
      type: MediaType.movie,
    );
  }

  MediaItem _applyHistoryToMediaItem({
    required MediaItem base,
    required WatchHistoryItem history,
  }) {
    final progress = _userDataProvider.playbackProgressForItem(base);

    return base
        .copyWith(
          playbackProgress: MediaPlaybackProgress(
            position: history.position,
            duration: history.duration,
          ),
          lastPlayedAt: history.updatedAt,
          posterUrl:
              base.posterUrl ??
              (history.poster.isNotEmpty ? history.poster : null),
          backdropUrl: base.backdropUrl ?? history.backdrop,
          overview: base.overview.isNotEmpty
              ? base.overview
              : (history.overview ?? ''),
          year: history.year ?? base.year,
        )
        .copyWith(
          playbackProgress:
              progress ??
              MediaPlaybackProgress(
                position: history.position,
                duration: history.duration,
              ),
        );
  }

  MediaItem _buildFallbackContinueWatchingItem({
    required WatchHistoryItem history,
    required String sourceId,
    required String title,
    required String? originalTitle,
    required MediaType type,
  }) {
    return MediaItem(
      id: _stableNumericId(sourceId),
      sourceId: sourceId,
      title: title.isNotEmpty ? title : history.title,
      originalTitle: (originalTitle?.isNotEmpty == true)
          ? originalTitle!
          : (title.isNotEmpty ? title : history.title),
      type: type,
      sourceType: history.sourceType,
      posterUrl: history.poster.isNotEmpty ? history.poster : null,
      backdropUrl: history.backdrop,
      overview: history.overview ?? '',
      year: history.year,
      parentTitle: history.parentTitle,
      seriesId: history.seriesId,
      parentIndexNumber: history.parentIndexNumber,
      indexNumber: history.indexNumber,
      playbackProgress: MediaPlaybackProgress(
        position: history.position,
        duration: history.duration,
      ),
      lastPlayedAt: history.updatedAt,
    );
  }

  int _stableNumericId(String value) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      return parsed;
    }

    var hash = 0x811C9DC5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  @override
  void dispose() {
    _detachListeners();
    super.dispose();
  }
}
