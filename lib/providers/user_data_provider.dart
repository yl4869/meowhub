import 'dart:async';

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
  static const Duration _serverWatchHistorySyncInterval = Duration(seconds: 15);
  static const Duration _manualSeekRegressionThreshold = Duration(seconds: 30);
  static const Duration _optimisticSeekProtectionWindow = Duration(seconds: 2);
  static const Duration _optimisticSeekBackwardTolerance = Duration(
    milliseconds: 900,
  );
  static const Duration _optimisticSeekForwardTolerance = Duration(seconds: 4);

  //心跳同步：进度同步到服务器的实现
  // 记录每个 UniqueKey 对应的最后一次服务器同步时间
  final Map<String, DateTime> _lastServerSyncTimes = {};
  // 定义全局同步频率（例如 15 秒同步一次服务器）
  static const Duration _serverSyncThrottleInterval = Duration(seconds: 15);

  // 核心存储：从 List 变为 Map
  // Key 建议使用 "${sourceType.name}:$id"
  final Map<String, WatchHistoryItem> _historyMap = {};

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
    _restartServerWatchHistorySync();
    _loadWatchHistory();
  }

  MediaServiceManager _mediaServiceManager;
  late WatchHistoryRepository _watchHistoryRepository;
  late UpdateWatchProgressUseCase _updateWatchProgress;
  String? _activeConfigNamespace;

  final Map<int, MediaItem> _favoriteItems = {};
  final Map<String, int> _recentEpisodeIndices = {};
  final Map<String, String> _recentPlayableItemIds = {};
  // List<WatchHistoryItem> _watchHistory = const [];
  bool _isLoading = false; // 防并发加载锁
  final Set<String> _activePlaybackKeys = <String>{};
  Timer? _serverWatchHistorySyncTimer;
  // 每个作品的音轨/字幕选择（仅内存保存，退出播放器后继续生效）
  final Map<String, TrackSelection> _trackSelections = {};
  final Map<String, _OptimisticSeekState> _optimisticSeekStates = {};

  // Getters
  List<MediaItem> get favoriteItems => _favoriteItems.values.toList();
  int get favoriteCount => _favoriteItems.length;

  List<WatchHistoryItem> get watchHistory => _historyMap.values.toList()
  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // 统计逻辑也变简单了
  int get inProgressCount => _historyMap.values
    .where((item) => item.position > Duration.zero)
    .length;

  List<int> get recentPlaybackMediaIds => watchHistory
    .map((item) => int.tryParse(item.id))
    .whereType<int>()
    .toList(growable: false);

  List<String> get recentPlaybackMediaKeys {
    return watchHistory // 使用公共 getter 替代 _watchHistory
        .map((item) {
          final targetId = item.seriesId ?? item.id;
          return '${item.sourceType.name}:$targetId';
        })
        .toList(growable: false);
  }

  int? get latestRecentMediaId {
    final history = watchHistory; // 获取转换后的有序列表
    if (history.isEmpty) {
      return null;
    }
    return int.tryParse(history.first.id);
  }

  String? get latestRecentMediaKey {
  if (_historyMap.isEmpty) return null;
  final latest = watchHistory.first; // 获取排序后的第一条
  return '${latest.sourceType.name}:${latest.seriesId ?? latest.id}';
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
    String? audioTitle,
    String? subtitleTitle,
    String? subtitleLanguage,
    String? subtitleUri,
  }) {
    _trackSelections[mediaItem.mediaKey] = TrackSelection(
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
      audioTitle: audioTitle,
      subtitleTitle: subtitleTitle,
      subtitleLanguage: subtitleLanguage,
      subtitleUri: subtitleUri,
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
  void updateProgressMemoryOnly(
    WatchHistoryItem item, {
    int? episodeIndex,
    bool allowPositionRegression = false,
  }) {
    _upsertWatchHistory(
      item,
      episodeIndex: episodeIndex,
      notify: false,
      allowPositionRegression: allowPositionRegression,
    );
  }

  /// 统一的 MediaItem 播放进度更新入口。
  /// 默认仅更新内存；通过 notify 控制是否同步刷新 UI。
  void updatePlaybackProgressForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    int? episodeIndex,
    bool notify = false,
    bool allowPositionRegression = false,
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

    updateProgressMemoryOnly(
      historyItem,
      episodeIndex: episodeIndex,
      allowPositionRegression: allowPositionRegression,
    );
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

  void registerOptimisticSeekForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    int? episodeIndex,
    bool notify = true,
  }) {
    final historyItem = _buildWatchHistoryItemFromMediaItem(
      mediaItem,
      position: position,
      duration: duration,
    );
    _optimisticSeekStates[historyItem.uniqueKey] = _OptimisticSeekState(
      targetPosition: historyItem.position,
      expiresAt: DateTime.now().add(_optimisticSeekProtectionWindow),
    );
    _upsertWatchHistory(
      historyItem,
      episodeIndex: episodeIndex,
      notify: false,
      allowPositionRegression: true,
    );
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> startPlaybackForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    _setPlaybackActive(mediaItem, active: true);
    final latest = _buildWatchHistoryItemFromMediaItem(
      mediaItem,
      position: position,
      duration: duration,
    );

    _upsertWatchHistory(latest, notify: false, allowPositionRegression: true);
    debugPrint(
      '[Resume][Playback][Start] item=${mediaItem.dataSourceId} '
      'position=${latest.position.inMilliseconds}ms '
      'duration=${latest.duration.inMilliseconds}ms '
      'playSessionId=${playSessionId ?? ''}',
    );
    notifyListeners();
    try {
      await _watchHistoryRepository.startPlayback(
        latest,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    } catch (e) {
      debugPrint(
        '[Resume][Playback][Start][Error] '
        'item=${mediaItem.dataSourceId} error=$e',
      );
    }
  }

  /// 播放过程中的心跳同步：明确走 Progress 通道。
  /// 智能同步：支持频率限制（Throttling）与强制上报（Forced Sync）
  Future<void> syncProgressToServerForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool force = false, // 新增：是否强制立即同步
  }) async {
    final historyItem = _buildWatchHistoryItemFromMediaItem(
      mediaItem,
      position: position,
      duration: duration,
    );

    // 1. 内存更新：无论是否同步服务器，内存数据必须秒级更新
    // 注意：这里 notify 设置为 false，UI 的进度刷新由 updatePlaybackProgressForItem 负责
    _upsertWatchHistory(historyItem, notify: false);

    // 2. 节流判定
    final now = DateTime.now();
    final lastSync = _lastServerSyncTimes[historyItem.uniqueKey];
    
    // 如果不是强制同步，且距离上次同步不足 15s，则拦截网络请求
    if (!force && 
        lastSync != null && 
        now.difference(lastSync) < _serverSyncThrottleInterval) {
      return; 
    }

    // 3. 执行真正的网络同步
    _lastServerSyncTimes[historyItem.uniqueKey] = now; // 更新最后同步时间
    
    try {
      debugPrint('[Resume][Network] 🚀 Syncing to server: ${historyItem.title} @ ${position.inSeconds}s (force: $force)');
      await _watchHistoryRepository.updateProgress(
        historyItem,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    } catch (e) {
      debugPrint('[Resume][Network][Error] Sync failed: $e');
      // 失败后可以考虑重置时间，让下一次心跳能尽快重试
      _lastServerSyncTimes.remove(historyItem.uniqueKey);
    }
  }

  /// 退出播放器时的最终同步：明确走 Stopped 通道。
  Future<void> stopPlaybackForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    String? playSessionId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final latest = _buildWatchHistoryItemFromMediaItem(
      mediaItem,
      position: position,
      duration: duration,
    );

    _upsertWatchHistory(latest, notify: false);
    debugPrint(
      '[Resume][Playback][Stopped] item=${mediaItem.dataSourceId} '
      'position=${latest.position.inMilliseconds}ms '
      'duration=${latest.duration.inMilliseconds}ms',
    );
    notifyListeners();
    try {
      await _watchHistoryRepository.stopPlayback(
        latest,
        playSessionId: playSessionId,
        mediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    } catch (e) {
      debugPrint(
        '[Resume][Playback][Stopped][Error] '
        'item=${mediaItem.dataSourceId} error=$e',
      );
    } finally {
      _setPlaybackActive(mediaItem, active: false);
      unawaited(_loadWatchHistory(rethrowOnError: false));
    }
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
    _historyMap.clear(); // 替换 _watchHistory = const [];
    _isLoading = false;
    _activePlaybackKeys.clear();
    _optimisticSeekStates.clear();
    _recentEpisodeIndices.clear();
    _recentPlayableItemIds.clear();
    _restartServerWatchHistorySync();
    notifyListeners();
    _loadWatchHistory();
  }

  // --- 找到并替换 clearPlaybackProgress ---
void clearPlaybackProgress(int mediaId) {
  // 这里直接从 Map 移除
  final key = 'emby:${mediaId.toString()}'; // 假设默认是 emby
  if (_historyMap.remove(key) != null) {
    _rebuildDerivedProgressState();
    notifyListeners();
  }
}

  void clearPlaybackProgressForItem(MediaItem mediaItem) {
  final key = '${mediaItem.sourceType.name}:${mediaItem.dataSourceId}';
  if (_historyMap.remove(key) != null) {
    _rebuildDerivedProgressState();
    notifyListeners();
  }
}

  // Private methods
  Future<void> _loadWatchHistory({bool rethrowOnError = true}) async {
    if (_isLoading) return;
    _isLoading = true;
    try {
      debugPrint('[Resume][Provider][Load] source=emby start');
      final remoteHistory = await _watchHistoryRepository.getHistoryBySource(
        WatchSourceType.emby,
      );
      _replaceWatchHistoryItemsForSource(
        WatchSourceType.emby,
        remoteHistory,
        notify: false,
      );
      final history = watchHistory; // 获取当前有序历史
      final firstItem = history.isEmpty ? null : history.first;
      debugPrint(
        '[Resume][Provider][Load] source=emby count=${history.length} '
        'firstId=${firstItem?.id ?? ''} '
        'firstTitle=${firstItem?.title ?? ''} '
        'firstPosition=${firstItem?.position.inMilliseconds ?? 0}ms',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Resume][Provider][Load][Error] source=emby error=$e');
      if (rethrowOnError) {
        rethrow;
      }
    } finally {
      _isLoading = false;
    }
  }

  void _restartServerWatchHistorySync() {
    _serverWatchHistorySyncTimer?.cancel();
    final savedConfig = _mediaServiceManager.getSavedConfig();
    if (savedConfig == null || savedConfig.type != MediaServiceType.emby) {
      return;
    }

    _serverWatchHistorySyncTimer = Timer.periodic(
      _serverWatchHistorySyncInterval,
      (_) => _syncWatchHistoryFromServerInBackground(),
    );
  }

  void _syncWatchHistoryFromServerInBackground() {
    if (_activePlaybackKeys.isNotEmpty) {
      return;
    }

    // ignore: discarded_futures
    _loadWatchHistory(rethrowOnError: false);
  }

  void _setPlaybackActive(MediaItem mediaItem, {required bool active}) {
    final key = mediaItem.mediaKey;
    if (active) {
      _activePlaybackKeys.add(key);
      return;
    }
    _activePlaybackKeys.remove(key);
    _optimisticSeekStates.remove(key);
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

  // --- 找到并替换 _watchHistoryItemFor ---
WatchHistoryItem? _watchHistoryItemFor(
  String id, {
  WatchSourceType? sourceType,
}) {
  // 直接通过 Key 从 Map 中获取，不再需要循环！
  final key = '${sourceType?.name ?? "emby"}:$id';
  return _historyMap[key];
}

  // --- 找到并替换 _watchHistoryItemForSeries ---
WatchHistoryItem? _watchHistoryItemForSeries(MediaItem mediaItem) {
  if (mediaItem.type != MediaType.series) return null;

  // 剧集查找稍微特殊，需要遍历一次 values
  WatchHistoryItem? matched;
  for (final item in _historyMap.values) {
    if (item.sourceType != mediaItem.sourceType) continue;
    if (item.seriesId != mediaItem.dataSourceId) continue;
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
              mediaItem.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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
    var changed = false;

    for (final item in items) {
      final existing = _historyMap[item.uniqueKey];
      final preferred = _selectPreferredProgressItem(existing, item);
      
      if (existing == null || !_isSameWatchHistoryItem(existing, preferred)) {
        _historyMap[item.uniqueKey] = preferred;
        changed = true;
      }
    }

    if (!changed) return;

    _rebuildDerivedProgressState();
    if (notify) notifyListeners();
  }

  void _replaceWatchHistoryItemsForSource(
    WatchSourceType sourceType,
    Iterable<WatchHistoryItem> items, {
    bool notify = true,
  }) {
    // 1. 先从 Map 中移除该源的所有旧数据
    _historyMap.removeWhere((key, item) => item.sourceType == sourceType);

    // 2. 填入新数据
    for (final item in items) {
      _historyMap[item.uniqueKey] = item;
    }

    _rebuildDerivedProgressState();
    if (notify) notifyListeners();
  }

  WatchHistoryItem _selectPreferredProgressItem(
    WatchHistoryItem? existing,
    WatchHistoryItem incoming, {
    bool allowPositionRegression = false,
  }) {
    if (existing == null) {
      return incoming;
    }
    final optimisticResolved = _resolveOptimisticSeekConflict(
      existing,
      incoming,
    );
    if (optimisticResolved != null) {
      return optimisticResolved;
    }
    return _mergeWatchHistoryFields(
      existing,
      incoming,
      allowPositionRegression: allowPositionRegression,
    );
  }

  WatchHistoryItem? _resolveOptimisticSeekConflict(
    WatchHistoryItem existing,
    WatchHistoryItem incoming,
  ) {
    final state = _optimisticSeekStates[existing.uniqueKey];
    if (state == null) {
      return null;
    }
    if (DateTime.now().isAfter(state.expiresAt)) {
      _optimisticSeekStates.remove(existing.uniqueKey);
      return null;
    }

    final target = state.targetPosition;
    final lowerBound = target - _optimisticSeekBackwardTolerance;
    final upperBound = target + _optimisticSeekForwardTolerance;
    final isConsistent =
        incoming.position >= lowerBound && incoming.position <= upperBound;
    if (isConsistent) {
      _optimisticSeekStates.remove(existing.uniqueKey);
      return null;
    }

    return _mergeWatchHistoryFields(
      existing,
      incoming.copyWith(position: existing.position),
      allowPositionRegression: false,
    );
  }

  void _upsertWatchHistory(
  WatchHistoryItem item, {
  int? episodeIndex,
  bool notify = true,
  bool allowPositionRegression = false,
}) {
  // 1. 获取旧值（O(1) 速度）
  final existing = _historyMap[item.uniqueKey];

  // 2. 调用判定逻辑（即你现有的 _selectPreferredProgressItem）
  final resolved = _selectPreferredProgressItem(
    existing,
    item,
    allowPositionRegression: allowPositionRegression,
  );

  // 3. 如果没变化，直接跳过，节省性能
  if (existing != null && _isSameWatchHistoryItem(existing, resolved)) {
    return;
  }

  // 4. 直接更新 Map，由于 Key 唯一，它会自动覆盖旧数据
  _historyMap[item.uniqueKey] = resolved;

  // 5. 更新派生状态（如最近剧集索引）
  _registerRecentProgress(resolved, explicitEpisodeIndex: episodeIndex);

  if (notify) notifyListeners();
}

  bool _isMeaningfulProgressRollback(
    WatchHistoryItem existing,
    WatchHistoryItem incoming,
  ) {
    if (existing.uniqueKey != incoming.uniqueKey) {
      return false;
    }
    if (existing.position <= Duration.zero ||
        incoming.position >= existing.position) {
      return false;
    }
    return existing.position - incoming.position >
        _manualSeekRegressionThreshold;
  }

  WatchHistoryItem _mergeWatchHistoryFields(
    WatchHistoryItem existing,
    WatchHistoryItem incoming, {
    required bool allowPositionRegression,
  }) {
    final canAcceptRegression =
        allowPositionRegression &&
        _isMeaningfulProgressRollback(existing, incoming);
    final bestPosition = canAcceptRegression
        ? incoming.position
        : _maxDuration(existing.position, incoming.position);
    final bestDuration = _maxDuration(existing.duration, incoming.duration);
    final bestUpdatedAt = incoming.updatedAt.isAfter(existing.updatedAt)
        ? incoming.updatedAt
        : existing.updatedAt;

    return existing.copyWith(
      title: incoming.title.isNotEmpty ? incoming.title : existing.title,
      poster: incoming.poster.isNotEmpty ? incoming.poster : existing.poster,
      position: bestPosition,
      duration: bestDuration,
      updatedAt: bestUpdatedAt,
      seriesId: incoming.seriesId ?? existing.seriesId,
      parentIndexNumber:
          incoming.parentIndexNumber ?? existing.parentIndexNumber,
      indexNumber: incoming.indexNumber ?? existing.indexNumber,
    );
  }

  Duration _maxDuration(Duration left, Duration right) {
    return left >= right ? left : right;
  }

  bool _isSameWatchHistoryItem(WatchHistoryItem left, WatchHistoryItem right) {
    return left.id == right.id &&
        left.title == right.title &&
        left.poster == right.poster &&
        left.position == right.position &&
        left.duration == right.duration &&
        left.updatedAt == right.updatedAt &&
        left.sourceType == right.sourceType &&
        left.seriesId == right.seriesId &&
        left.parentIndexNumber == right.parentIndexNumber &&
        left.indexNumber == right.indexNumber;
  }

  void _rebuildDerivedProgressState() {
  _recentEpisodeIndices.clear();
  _recentPlayableItemIds.clear();
  // 改为遍历 _historyMap.values
  for (final item in _historyMap.values) {
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

  @override
  void dispose() {
    _serverWatchHistorySyncTimer?.cancel();
    super.dispose();
  }
}

/// 用户在 UI 中选择的音轨/字幕配置（可空表示跟随服务器默认）。
class TrackSelection {
  const TrackSelection({
    this.audioIndex,
    this.subtitleIndex,
    this.audioTitle,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.subtitleUri,
  });

  final int? audioIndex; // null 表示未指定，沿用默认
  final int? subtitleIndex; // null 表示未指定，沿用默认 / -1 表示明确关闭字幕
  final String? audioTitle;
  final String? subtitleTitle;
  final String? subtitleLanguage;
  final String? subtitleUri;
}

class _OptimisticSeekState {
  const _OptimisticSeekState({
    required this.targetPosition,
    required this.expiresAt,
  });

  final Duration targetPosition;
  final DateTime expiresAt;
}
