import 'package:flutter/foundation.dart';

import '../domain/entities/media_item.dart';
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
    // 1. 批量处理电影和剧集
    _cachedMovies = _enrichMediaItems(_mediaLibraryProvider.state.movies);
    _cachedSeries = _enrichMediaItems(_mediaLibraryProvider.state.series);

    // 2. 优化最近播放查询
    final itemLookup = {
      for (final item in [..._cachedMovies, ..._cachedSeries]) 
        item.mediaKey: item
    };
    
    final resolvedRecent = <MediaItem>[];
    final seenMediaKeys = <String>{};

    for (final history in _userDataProvider.watchHistory) {
      final targetKey = history.seriesId != null 
          ? '${history.sourceType.name}:${history.seriesId}' 
          : history.uniqueKey;

      final matched = itemLookup[targetKey];
      if (matched != null && seenMediaKeys.add(matched.mediaKey)) {
        resolvedRecent.add(matched);
      }
    }
    _cachedRecent = resolvedRecent;

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

  @override
  void dispose() {
    _detachListeners();
    super.dispose();
  }
}
