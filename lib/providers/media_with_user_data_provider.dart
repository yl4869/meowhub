import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
import '../domain/entities/watch_history_item.dart';
import 'media_library_provider.dart';
import 'user_data_provider.dart';

/// 组合 Provider
/// 将媒体库数据与用户个人数据组合，提供带收藏/进度标记的媒体列表
/// 组合 Provider
/// 将媒体库数据与用户个人数据组合，提供带收藏/进度标记的媒体列表
class MediaWithUserDataProvider extends ChangeNotifier {
  MediaWithUserDataProvider({
    required MediaLibraryProvider mediaLibraryProvider,
    required UserDataProvider userDataProvider,
  }) : _mediaLibraryProvider = mediaLibraryProvider,
       _userDataProvider = userDataProvider {
    _attachListeners();
    _initialSync();
  }

  MediaLibraryProvider _mediaLibraryProvider;
  UserDataProvider _userDataProvider;

  // 缓存变量
  List<MediaItem> _cachedMovies = [];
  List<MediaItem> _cachedSeries = [];
  List<MediaItem> _cachedRecent = [];

  // Getters
  List<MediaItem> get enrichedMovies => _cachedMovies;
  List<MediaItem> get enrichedSeries => _cachedSeries;
  List<MediaItem> get recentWatching => _cachedRecent;
  List<MediaItem> get allItems => [..._cachedSeries, ..._cachedMovies];
  bool get isLoading => _mediaLibraryProvider.state.isLoading;
  String? get errorMessage => _mediaLibraryProvider.state.errorMessage;

  /// ✅ 适配 main.dart 的 ProxyProvider 更新机制
  void updateDependencies({
    required MediaLibraryProvider mediaLibrary,
    required UserDataProvider userData,
  }) {
    if (identical(_mediaLibraryProvider, mediaLibrary) && 
        identical(_userDataProvider, userData)) {
      return;
    }

    // 移除旧监听，挂载新监听
    _detachListeners();
    _mediaLibraryProvider = mediaLibrary;
    _userDataProvider = userData;
    _attachListeners();

    _initialSync();
  }

  void _attachListeners() {
    _mediaLibraryProvider.addListener(_handleLibraryUpdate);
    _userDataProvider.addListener(_updateCache);
  }

  void _detachListeners() {
    _mediaLibraryProvider.removeListener(_handleLibraryUpdate);
    _userDataProvider.removeListener(_updateCache);
  }

  /// ✅ 处理媒体库变化：先同步进度，再更新缓存
  void _handleLibraryUpdate() {
    _initialSync();
    _updateCache();
  }

  void _initialSync() {
    // 自动将库里的进度同步到 UserDataProvider
    _userDataProvider.initializeProgress([
      ..._mediaLibraryProvider.state.movies,
      ..._mediaLibraryProvider.state.series,
    ]);
  }

  /// 核心优化：统一的缓存更新逻辑
  void _updateCache() {
    _cachedMovies = _enrichMediaItems(_mediaLibraryProvider.state.movies);
    _cachedSeries = _enrichMediaItems(_mediaLibraryProvider.state.series);

    final itemLookup = {
      for (final item in [..._cachedMovies, ..._cachedSeries]) 
        item.mediaKey: item
    };
    
    final resolvedRecent = <MediaItem>[];
    final seenMediaKeys = <String>{};

    for (final history in _userDataProvider.watchHistory) {
      final resolvedItem = _buildRecentItem(
        history: history,
        itemLookup: itemLookup,
      );
      if (resolvedItem != null && seenMediaKeys.add(resolvedItem.mediaKey)) {
        resolvedRecent.add(resolvedItem);
      } else if (kDebugMode && resolvedItem == null) {
        debugPrint(
          '[Diag][MediaWithUserData] recent:unresolved | '
          'historyKey=${history.uniqueKey}, seriesId=${history.seriesId}',
        );
      }
    }
    _cachedRecent = resolvedRecent;

    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaWithUserData] recent:rebuilt | '
        'historyCount=${_userDataProvider.watchHistory.length}, '
        'resolvedCount=${_cachedRecent.length}',
      );
    }

    notifyListeners();
  }

  List<MediaItem> _enrichMediaItems(List<MediaItem> items) {
    return items.map((item) {
      return item.copyWith(
        isFavorite: _userDataProvider.isFavorite(item.id),
        playbackProgress: _userDataProvider.playbackProgressForItem(item),
      );
    }).toList(growable: false);
  }

  MediaItem? _buildRecentItem({
    required WatchHistoryItem history,
    required Map<String, MediaItem> itemLookup,
  }) {
    final seriesId = history.seriesId;
    if (seriesId != null && seriesId.isNotEmpty) {
      final seriesMatch = itemLookup['${history.sourceType.name}:$seriesId'];
      if (seriesMatch != null) {
        return _applyHistoryToMediaItem(
          base: seriesMatch,
          history: history,
        );
      }

      return _buildFallbackRecentItem(
        history: history,
        sourceId: seriesId,
        title: history.parentTitle ?? history.title,
        originalTitle: history.originalTitle ?? history.parentTitle,
        type: MediaType.series,
      );
    }

    final directMatch = itemLookup[history.uniqueKey];
    if (directMatch != null) {
      return _applyHistoryToMediaItem(
        base: directMatch,
        history: history,
      );
    }

    return _buildFallbackRecentItem(
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

    return base.copyWith(
      playbackProgress: MediaPlaybackProgress(
        position: history.position,
        duration: history.duration,
      ),
      lastPlayedAt: history.updatedAt,
      posterUrl: base.posterUrl ?? (history.poster.isNotEmpty ? history.poster : null),
      backdropUrl: base.backdropUrl ?? history.backdrop,
      overview: base.overview.isNotEmpty
          ? base.overview
          : (history.overview ?? ''),
      year: history.year ?? base.year,
    ).copyWith(
      playbackProgress: progress ??
          MediaPlaybackProgress(
            position: history.position,
            duration: history.duration,
          ),
    );
  }

  MediaItem _buildFallbackRecentItem({
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
