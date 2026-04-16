import 'package:flutter/foundation.dart';

import '../data/datasources/emby_watch_history_remote_data_source.dart';
import '../data/datasources/local_watch_history_data_source.dart';
import '../data/repositories/watch_history_repository_impl.dart';
import '../domain/entities/watch_history_item.dart';
import '../domain/entities/media_service_config.dart';
import '../domain/repositories/watch_history_repository.dart';
import '../domain/repositories/media_service_manager.dart';
import '../domain/usecases/update_watch_progress.dart';
import '../domain/entities/media_item.dart';

/// 用户个人数据 Provider
/// 管理用户的收藏、观看历史、播放进度等个人数据
class UserDataProvider extends ChangeNotifier {
  UserDataProvider({
    required MediaServiceManager mediaServiceManager,
    WatchHistoryRepository? watchHistoryRepository,
  }) : _mediaServiceManager = mediaServiceManager {
    _activeConfigNamespace = mediaServiceManager
        .getSavedConfig()
        ?.credentialNamespace;
    _watchHistoryRepository =
        watchHistoryRepository ?? _buildWatchHistoryRepository();
    _updateWatchProgress = UpdateWatchProgressUseCase(_watchHistoryRepository);
    _loadWatchHistory();
  }

  MediaServiceManager _mediaServiceManager;
  late WatchHistoryRepository _watchHistoryRepository;
  late UpdateWatchProgressUseCase _updateWatchProgress;
  String? _activeConfigNamespace;

  final Map<int, MediaItem> _favoriteItems = {};
  final Map<String, int> _recentEpisodeIndices = {};
  final Map<String, String> _recentPlayableItemIds = {};
  List<WatchHistoryItem> _watchHistory = const [];
  bool _isLoading = false; // 防并发加载锁
  // 每个作品的音轨/字幕选择（仅内存保存，退出播放器后继续生效）
  final Map<String, TrackSelection> _trackSelections = {};

  // Getters
  List<MediaItem> get favoriteItems => _favoriteItems.values.toList();
  int get favoriteCount => _favoriteItems.length;

  List<WatchHistoryItem> get watchHistory => _watchHistory;
  int get inProgressCount {
    return _watchHistory.where((item) => item.position > Duration.zero).length;
  }

  List<int> get recentPlaybackMediaIds {
    return _watchHistory
        .map((item) => int.tryParse(item.id))
        .whereType<int>()
        .toList(growable: false);
  }

  List<String> get recentPlaybackMediaKeys {
    return _watchHistory
        .map((item) {
          final targetId = item.seriesId ?? item.id;
          return '${item.sourceType.name}:$targetId';
        })
        .toList(growable: false);
  }

  int? get latestRecentMediaId {
    if (_watchHistory.isEmpty) {
      return null;
    }
    return int.tryParse(_watchHistory.first.id);
  }

  String? get latestRecentMediaKey {
    if (_watchHistory.isEmpty) {
      return null;
    }

    final latest = _watchHistory.first;
    final targetId = latest.seriesId ?? latest.id;
    return '${latest.sourceType.name}:$targetId';
  }

  // Query methods
  bool isFavorite(int mediaId) => _favoriteItems.containsKey(mediaId);

  MediaPlaybackProgress? playbackProgressFor(int mediaId) {
    final item = _watchHistoryItemFor(mediaId.toString());
    if (item == null) {
      return null;
    }

    return MediaPlaybackProgress(
      position: item.position,
      duration: item.duration,
    );
  }

  MediaPlaybackProgress? playbackProgressForItem(MediaItem mediaItem) {
    final directItem = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    final item = directItem ?? _watchHistoryItemForSeries(mediaItem);
    if (item == null) {
      return null;
    }

    return MediaPlaybackProgress(
      position: item.position,
      duration: item.duration,
    );
  }

  int episodeIndexFor(int mediaId) {
    return _recentEpisodeIndices[mediaId.toString()] ?? 0;
  }

  int episodeIndexForItem(MediaItem mediaItem) {
    return _recentEpisodeIndices[mediaItem.dataSourceId] ?? 0;
  }

  String? resumePlayableItemIdForItem(MediaItem mediaItem) {
    return _recentPlayableItemIds[mediaItem.dataSourceId];
  }

  double progressFractionFor(int mediaId) {
    return playbackProgressFor(mediaId)?.fraction ?? 0;
  }

  double progressFractionForItem(MediaItem mediaItem) {
    return playbackProgressForItem(mediaItem)?.fraction ?? 0;
  }

  void initializeProgress(List<MediaItem> items) {
    final hydratedItems = <WatchHistoryItem>[];
    for (final item in items) {
      _collectHydratedProgressItems(item, hydratedItems);
    }
    _mergeWatchHistoryItems(hydratedItems);
  }

  // Track selection APIs
  TrackSelection? trackSelectionForItem(MediaItem mediaItem) {
    return _trackSelections[mediaItem.mediaKey];
  }

  void setTrackSelectionForItem(
    MediaItem mediaItem, {
    int? audioIndex,
    int? subtitleIndex,
  }) {
    _trackSelections[mediaItem.mediaKey] = TrackSelection(
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
    );
  }

  // Actions
  bool toggleFavorite(MediaItem mediaItem) {
    if (isFavorite(mediaItem.id)) {
      _favoriteItems.remove(mediaItem.id);
      notifyListeners();
      return false;
    }

    _favoriteItems[mediaItem.id] = mediaItem.copyWith(isFavorite: true);
    notifyListeners();
    return true;
  }

  Future<void> loadWatchHistory() async {
    await _loadWatchHistory();
  }

  Future<void> refreshWatchHistory() async {
    await _loadWatchHistory();
  }

  Future<void> updateProgress(
    WatchHistoryItem item, {
    int? episodeIndex,
  }) async {
    // 保持原有的“完整更新”路径：本地写入 + 服务器持久化 + 列表刷新
    _upsertWatchHistory(item, episodeIndex: episodeIndex);
    await _updateWatchProgress(item);
    await _loadWatchHistory();
  }

  Future<void> updatePlaybackProgress({
    required int mediaId,
    required Duration position,
    Duration duration = Duration.zero,
    int? episodeIndex,
    String? title,
    String? poster,
    WatchSourceType sourceType = WatchSourceType.emby,
  }) async {
    final previous = _watchHistoryItemFor(
      mediaId.toString(),
      sourceType: sourceType,
    );
    final normalizedPosition = position < Duration.zero
        ? Duration.zero
        : position;
    final normalizedDuration = duration > Duration.zero
        ? duration
        : previous?.duration ?? Duration.zero;

    final historyItem = WatchHistoryItem(
      id: mediaId.toString(),
      title: title ?? previous?.title ?? '未知视频',
      poster: poster ?? previous?.poster ?? '',
      position: normalizedPosition,
      duration: normalizedDuration,
      updatedAt: DateTime.now(),
      sourceType: sourceType,
      seriesId: previous?.seriesId,
      parentIndexNumber: previous?.parentIndexNumber,
      indexNumber: previous?.indexNumber,
    );

    // 内存更新：禁止 notifyListeners，禁止任何 IO
    _upsertWatchHistory(historyItem, episodeIndex: episodeIndex, notify: false);
  }

  Future<void> markRecentlyWatched(
    int mediaId, {
    int episodeIndex = 0,
    String? title,
    String? poster,
    WatchSourceType sourceType = WatchSourceType.emby,
  }) async {
    final previous = _watchHistoryItemFor(
      mediaId.toString(),
      sourceType: sourceType,
    );
    final historyItem = WatchHistoryItem(
      id: mediaId.toString(),
      title: title ?? previous?.title ?? '未知视频',
      poster: poster ?? previous?.poster ?? '',
      position: previous?.position ?? Duration.zero,
      duration: previous?.duration ?? Duration.zero,
      updatedAt: DateTime.now(),
      sourceType: sourceType,
      seriesId: previous?.seriesId,
      parentIndexNumber: previous?.parentIndexNumber,
      indexNumber: previous?.indexNumber,
    );

    await updateProgress(historyItem, episodeIndex: episodeIndex);
  }

  Future<void> markRecentlyWatchedItem(
    MediaItem mediaItem, {
    int episodeIndex = 0,
  }) async {
    final previous = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    final historyItem = WatchHistoryItem(
      id: mediaItem.dataSourceId,
      title: mediaItem.title.isNotEmpty
          ? mediaItem.title
          : previous?.title ?? '未知视频',
      poster: mediaItem.posterUrl ?? previous?.poster ?? '',
      position: previous?.position ?? Duration.zero,
      duration: previous?.duration ?? Duration.zero,
      updatedAt: DateTime.now(),
      sourceType: mediaItem.sourceType,
      seriesId: mediaItem.seriesId ?? previous?.seriesId,
      parentIndexNumber:
          mediaItem.parentIndexNumber ?? previous?.parentIndexNumber,
      indexNumber: mediaItem.indexNumber ?? previous?.indexNumber,
    );

    await updateProgress(historyItem, episodeIndex: episodeIndex);
  }

  /// 仅在内存中标记最近观看项，避免在真正开始播放前把服务器上的续播点覆盖掉。
  void markRecentlyWatchedItemMemoryOnly(
    MediaItem mediaItem, {
    int episodeIndex = 0,
  }) {
    final previous = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    final historyItem = WatchHistoryItem(
      id: mediaItem.dataSourceId,
      title: mediaItem.title.isNotEmpty
          ? mediaItem.title
          : previous?.title ?? '未知视频',
      poster: mediaItem.posterUrl ?? previous?.poster ?? '',
      position:
          mediaItem.playbackProgress?.position ??
          previous?.position ??
          Duration.zero,
      duration:
          mediaItem.playbackProgress?.duration ??
          previous?.duration ??
          Duration.zero,
      updatedAt: DateTime.now(),
      sourceType: mediaItem.sourceType,
      seriesId: mediaItem.seriesId ?? previous?.seriesId,
      parentIndexNumber:
          mediaItem.parentIndexNumber ?? previous?.parentIndexNumber,
      indexNumber: mediaItem.indexNumber ?? previous?.indexNumber,
    );

    updateProgressMemoryOnly(historyItem, episodeIndex: episodeIndex);
    notifyListeners();
  }

  // ---------------- 新增：仅内存更新，不触发 IO ----------------
  /// 仅在内存中更新观看进度，不做任何网络/数据库 IO，也不触发重绘风暴。
  void updateProgressMemoryOnly(WatchHistoryItem item, {int? episodeIndex}) {
    _upsertWatchHistory(item, episodeIndex: episodeIndex, notify: false);
  }

  /// 统一的 MediaItem 播放进度更新入口。
  /// 默认仅更新内存；通过 notify 控制是否同步刷新 UI。
  void updatePlaybackProgressForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    int? episodeIndex,
    bool notify = false,
  }) {
    final historyItem = _buildWatchHistoryItemFromMediaItem(
      mediaItem,
      position: position,
      duration: duration,
    );
    final previous = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );

    updateProgressMemoryOnly(historyItem, episodeIndex: episodeIndex);
    if (notify) {
      debugPrint(
        '[Resume][Progress][Update] item=${mediaItem.dataSourceId} '
        'from=${previous?.position.inMilliseconds ?? 0}ms '
        'position=${historyItem.position.inMilliseconds}ms '
        'duration=${historyItem.duration.inMilliseconds}ms '
        'notify=$notify',
      );
    }
    if (notify) {
      notifyListeners();
    }
  }

  /// 在退出播放时，将内存中的最终进度一次性写入服务器。
  Future<void> syncProgressToServerForItem(MediaItem mediaItem) async {
    final latest = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    if (latest == null) return;

    // 先把内存里的最新进度通知给 UI，避免返回详情页时还看到旧值。
    debugPrint(
      '[Resume][Progress][Sync] item=${mediaItem.dataSourceId} '
      'ui-update position=${latest.position.inMilliseconds}ms '
      'duration=${latest.duration.inMilliseconds}ms',
    );
    notifyListeners();
    await _updateWatchProgress(latest);
    // 单次刷新以同步最新状态到 UI（非高频）。
    await _loadWatchHistory();
    final refreshed = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    debugPrint(
      '[Resume][Progress][Sync] item=${mediaItem.dataSourceId} '
      'server-refresh position=${refreshed?.position.inMilliseconds ?? 0}ms '
      'duration=${refreshed?.duration.inMilliseconds ?? 0}ms',
    );
  }

  void updateMediaServiceManager(MediaServiceManager manager) {
    final nextNamespace = manager.getSavedConfig()?.credentialNamespace;
    if (identical(_mediaServiceManager, manager) &&
        _activeConfigNamespace == nextNamespace) {
      return;
    }

    _mediaServiceManager = manager;
    _activeConfigNamespace = nextNamespace;
    _watchHistoryRepository = _buildWatchHistoryRepository();
    _updateWatchProgress = UpdateWatchProgressUseCase(_watchHistoryRepository);
    _watchHistory = const [];
    _isLoading = false;
    _recentEpisodeIndices.clear();
    _recentPlayableItemIds.clear();
    notifyListeners();
    _loadWatchHistory();
  }

  void clearPlaybackProgress(int mediaId) {
    final targetId = mediaId.toString();
    final previousLength = _watchHistory.length;
    _watchHistory = _watchHistory
        .where((item) => item.id != targetId)
        .toList(growable: false);
    _rebuildDerivedProgressState();

    if (previousLength != _watchHistory.length) {
      notifyListeners();
    }
  }

  void clearPlaybackProgressForItem(MediaItem mediaItem) {
    final targetId = mediaItem.dataSourceId;
    final previousLength = _watchHistory.length;
    _watchHistory = _watchHistory
        .where(
          (item) =>
              !(item.id == targetId && item.sourceType == mediaItem.sourceType),
        )
        .toList(growable: false);
    _rebuildDerivedProgressState();

    if (previousLength != _watchHistory.length) {
      notifyListeners();
    }
  }

  // Private methods
  Future<void> _loadWatchHistory() async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      debugPrint('[Resume][Provider][Load] source=emby start');
      final remoteHistory = await _watchHistoryRepository.getHistoryBySource(
        WatchSourceType.emby,
      );
      _mergeWatchHistoryItems(remoteHistory, notify: false);
      final firstItem = _watchHistory.isEmpty ? null : _watchHistory.first;
      debugPrint(
        '[Resume][Provider][Load] source=emby count=${_watchHistory.length} '
        'firstId=${firstItem?.id ?? ''} '
        'firstTitle=${firstItem?.title ?? ''} '
        'firstPosition=${firstItem?.position.inMilliseconds ?? 0}ms',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Resume][Provider][Load][Error] source=emby error=$e');
      rethrow;
    } finally {
      _isLoading = false;
    }
  }

  WatchHistoryRepository _buildWatchHistoryRepository() {
    final savedConfig = _mediaServiceManager.getSavedConfig();
    if (savedConfig != null && savedConfig.type == MediaServiceType.emby) {
      return WatchHistoryRepositoryImpl(
        embyRemoteDataSource: EmbyWatchHistoryRemoteDataSourceImpl(
          config: savedConfig,
          securityService: _mediaServiceManager.securityService,
          sessionExpiredNotifier: _mediaServiceManager.sessionExpiredNotifier,
        ),
        localDataSource: InMemoryLocalWatchHistoryDataSource(),
      );
    }

    return WatchHistoryRepositoryImpl(
      embyRemoteDataSource: MockEmbyWatchHistoryRemoteDataSource(),
      localDataSource: InMemoryLocalWatchHistoryDataSource(),
    );
  }

  WatchHistoryItem? _watchHistoryItemFor(
    String id, {
    WatchSourceType? sourceType,
  }) {
    for (final item in _watchHistory) {
      if (item.id == id &&
          (sourceType == null || item.sourceType == sourceType)) {
        return item;
      }
    }
    return null;
  }

  WatchHistoryItem? _watchHistoryItemForSeries(MediaItem mediaItem) {
    if (mediaItem.type != MediaType.series) {
      return null;
    }

    WatchHistoryItem? matched;
    for (final item in _watchHistory) {
      if (item.sourceType != mediaItem.sourceType) {
        continue;
      }
      if (item.seriesId != mediaItem.dataSourceId) {
        continue;
      }
      if (matched == null || item.updatedAt.isAfter(matched.updatedAt)) {
        matched = item;
      }
    }
    return matched;
  }

  WatchHistoryItem _buildWatchHistoryItemFromMediaItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
  }) {
    final previous = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
    final normalizedPosition = position < Duration.zero
        ? Duration.zero
        : position;
    final normalizedDuration = duration > Duration.zero
        ? duration
        : previous?.duration ?? Duration.zero;

    return WatchHistoryItem(
      id: mediaItem.dataSourceId,
      title: mediaItem.title.isNotEmpty
          ? mediaItem.title
          : previous?.title ?? '未知视频',
      poster: mediaItem.posterUrl ?? previous?.poster ?? '',
      position: normalizedPosition,
      duration: normalizedDuration,
      updatedAt: DateTime.now(),
      sourceType: mediaItem.sourceType,
      seriesId: mediaItem.seriesId ?? previous?.seriesId,
      parentIndexNumber:
          mediaItem.parentIndexNumber ?? previous?.parentIndexNumber,
      indexNumber: mediaItem.indexNumber ?? previous?.indexNumber,
    );
  }

  void _collectHydratedProgressItems(
    MediaItem mediaItem,
    List<WatchHistoryItem> target,
  ) {
    final progress = mediaItem.playbackProgress;
    if (progress != null &&
        progress.position > Duration.zero &&
        progress.duration > Duration.zero) {
      target.add(
        WatchHistoryItem(
          id: mediaItem.dataSourceId,
          title: mediaItem.title.isNotEmpty ? mediaItem.title : '未知视频',
          poster: mediaItem.posterUrl ?? '',
          position: progress.position,
          duration: progress.duration,
          updatedAt:
              mediaItem.lastPlayedAt ??
              DateTime.fromMillisecondsSinceEpoch(0),
          sourceType: mediaItem.sourceType,
          seriesId: mediaItem.seriesId,
          parentIndexNumber: mediaItem.parentIndexNumber,
          indexNumber: mediaItem.indexNumber,
        ),
      );
    }

    for (final playableItem in mediaItem.playableItems) {
      _collectHydratedProgressItems(playableItem, target);
    }
  }

  void _mergeWatchHistoryItems(
    Iterable<WatchHistoryItem> items, {
    bool notify = true,
  }) {
    final merged = <String, WatchHistoryItem>{
      for (final item in _watchHistory) item.uniqueKey: item,
    };
    var changed = false;

    for (final item in items) {
      final existing = merged[item.uniqueKey];
      final preferred = _selectPreferredProgressItem(existing, item);
      if (existing == null || !identical(existing, preferred)) {
        merged[item.uniqueKey] = preferred;
        changed = true;
      }
    }

    if (!changed) {
      return;
    }

    _watchHistory = merged.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    _rebuildDerivedProgressState();

    if (notify) {
      notifyListeners();
    }
  }

  WatchHistoryItem _selectPreferredProgressItem(
    WatchHistoryItem? existing,
    WatchHistoryItem incoming,
  ) {
    if (existing == null) {
      return incoming;
    }
    if (existing.updatedAt.isAfter(incoming.updatedAt)) {
      return existing;
    }
    if (incoming.updatedAt.isAfter(existing.updatedAt)) {
      return incoming;
    }
    if (existing.position >= incoming.position &&
        existing.duration >= incoming.duration) {
      return existing;
    }
    return incoming;
  }

  void _upsertWatchHistory(
    WatchHistoryItem item, {
    int? episodeIndex,
    bool notify = true,
  }) {
    _watchHistory = <WatchHistoryItem>[
      item,
      ..._watchHistory.where(
        (historyItem) => historyItem.uniqueKey != item.uniqueKey,
      ),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    _registerRecentProgress(item, explicitEpisodeIndex: episodeIndex);

    if (notify) {
      notifyListeners();
    }
  }

  void _rebuildDerivedProgressState() {
    _recentEpisodeIndices.clear();
    _recentPlayableItemIds.clear();
    for (final item in _watchHistory) {
      _registerRecentProgress(item);
    }
  }

  void _registerRecentProgress(
    WatchHistoryItem item, {
    int? explicitEpisodeIndex,
  }) {
    if (explicitEpisodeIndex != null) {
      _recentEpisodeIndices[item.id] = explicitEpisodeIndex;
    }

    final seriesId = item.seriesId;
    if (seriesId == null || seriesId.isEmpty) {
      return;
    }

    _recentPlayableItemIds[seriesId] = item.id;
    final resolvedEpisodeIndex =
        explicitEpisodeIndex ??
        ((item.indexNumber != null && item.indexNumber! > 0)
            ? item.indexNumber! - 1
            : null);
    if (resolvedEpisodeIndex != null && resolvedEpisodeIndex >= 0) {
      _recentEpisodeIndices[seriesId] = resolvedEpisodeIndex;
    }
  }
}

/// 用户在 UI 中选择的音轨/字幕索引（可空表示跟随服务器默认）。
class TrackSelection {
  const TrackSelection({this.audioIndex, this.subtitleIndex});

  final int? audioIndex; // null 表示未指定，沿用默认
  final int? subtitleIndex; // null 表示未指定，沿用默认 / -1 表示明确关闭字幕
}
