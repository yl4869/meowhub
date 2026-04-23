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
    _mediaLibraryProvider.addListener(_updateCache);
    _userDataProvider.addListener(_updateCache);
    _updateCache(); // 初始化缓存
  }

  final MediaLibraryProvider _mediaLibraryProvider;
  final UserDataProvider _userDataProvider;


  // --- 优化 1: 使用缓存变量，避免每次 Getter 调用都重新循环 ---
  List<MediaItem> _cachedMovies = [];
  List<MediaItem> _cachedSeries = [];
  List<MediaItem> _cachedRecent = [];

  List<MediaItem> get enrichedMovies => _cachedMovies;
  List<MediaItem> get enrichedSeries => _cachedSeries;
  List<MediaItem> get recentWatching => _cachedRecent;

  List<MediaItem> get allItems => [..._cachedSeries, ..._cachedMovies];

  bool get isLoading => _mediaLibraryProvider.state.isLoading;
  String? get errorMessage => _mediaLibraryProvider.state.errorMessage;

  /// --- 核心优化：统一的缓存更新逻辑 ---
  void _updateCache() {
    // 1. 批量处理电影和剧集
    _cachedMovies = _enrichMediaItems(_mediaLibraryProvider.state.movies);
    _cachedSeries = _enrichMediaItems(_mediaLibraryProvider.state.series);

    // 2. 优化最近播放查询
    // 创建一个临时 Map 加快索引速度 (O(n))
    final itemLookup = {for (final item in [..._cachedMovies, ..._cachedSeries]) item.mediaKey: item};
    
    final resolvedRecent = <MediaItem>[];
    final seenMediaKeys = <String>{};

    for (final history in _userDataProvider.watchHistory) {
      // 优先匹配剧集，其次匹配单集/电影
      final targetKey = history.seriesId != null 
          ? '${history.sourceType.name}:${history.seriesId}' 
          : history.uniqueKey;

      final matched = itemLookup[targetKey];
      if (matched != null && seenMediaKeys.add(matched.mediaKey)) {
        resolvedRecent.add(matched);
      }
    }
    _cachedRecent = resolvedRecent;

    // 只有在数据真正改变时才通知 UI (这里可以加深层对比判断)
    notifyListeners();
  }

  // Private methods
  List<MediaItem> _enrichMediaItems(List<MediaItem> items) {
    return items.map((item) {
      // 利用 UserDataProvider 优化后的 O(1) 查询
      return item.copyWith(
        isFavorite: _userDataProvider.isFavorite(item.id),
        playbackProgress: _userDataProvider.playbackProgressForItem(item),
      );
    }).toList(growable: false);
  }

  void _onMediaLibraryChanged() {
    // 自动将库里的进度同步到 UserDataProvider 的 Map 中
    // 这样即便服务器没返回，本地库里的初始进度也能被记录
    _userDataProvider.initializeProgress([
      ..._mediaLibraryProvider.state.movies,
      ..._mediaLibraryProvider.state.series,
    ]);
    _updateCache();
  }


  @override
  void dispose() {
    _mediaLibraryProvider.removeListener(_updateCache);
    _userDataProvider.removeListener(_updateCache);
    super.dispose();
  }
}
