import 'package:flutter/foundation.dart';

import '../data/datasources/emby_watch_history_remote_data_source.dart';
import '../data/datasources/local_watch_history_data_source.dart';
import '../data/repositories/watch_history_repository_impl.dart';
import '../domain/entities/watch_history_item.dart';
import '../domain/repositories/watch_history_repository.dart';
import '../domain/repositories/media_service_manager.dart';
import '../domain/usecases/update_watch_progress.dart';
import '../models/media_item.dart';

/// 用户个人数据 Provider
/// 管理用户的收藏、观看历史、播放进度等个人数据
class UserDataProvider extends ChangeNotifier {
  UserDataProvider({
    required MediaServiceManager mediaServiceManager,
    WatchHistoryRepository? watchHistoryRepository,
  }) : _mediaServiceManager = mediaServiceManager {
    _watchHistoryRepository =
        watchHistoryRepository ?? _buildWatchHistoryRepository();
    _updateWatchProgress = UpdateWatchProgressUseCase(_watchHistoryRepository);
    _loadWatchHistory();
  }

  final MediaServiceManager _mediaServiceManager;
  late final WatchHistoryRepository _watchHistoryRepository;
  late final UpdateWatchProgressUseCase _updateWatchProgress;

  final Map<int, MediaItem> _favoriteItems = {};
  final Map<String, int> _recentEpisodeIndices = {'1002': 2, '1007': 0};
  List<WatchHistoryItem> _watchHistory = const [];

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
        .map((item) => '${item.sourceType.name}:${item.id}')
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
    return '${latest.sourceType.name}:${latest.id}';
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
    final item = _watchHistoryItemFor(
      mediaItem.dataSourceId,
      sourceType: mediaItem.sourceType,
    );
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

  double progressFractionFor(int mediaId) {
    return playbackProgressFor(mediaId)?.fraction ?? 0;
  }

  double progressFractionForItem(MediaItem mediaItem) {
    return playbackProgressForItem(mediaItem)?.fraction ?? 0;
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
    );

    await updateProgress(historyItem, episodeIndex: episodeIndex);
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
    );

    await updateProgress(historyItem, episodeIndex: episodeIndex);
  }

  void clearPlaybackProgress(int mediaId) {
    final targetId = mediaId.toString();
    final previousLength = _watchHistory.length;
    _watchHistory = _watchHistory
        .where((item) => item.id != targetId)
        .toList(growable: false);
    _recentEpisodeIndices.remove(targetId);

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
    _recentEpisodeIndices.remove(targetId);

    if (previousLength != _watchHistory.length) {
      notifyListeners();
    }
  }

  Future<void> updatePlaybackProgressForItem(
    MediaItem mediaItem, {
    required Duration position,
    Duration duration = Duration.zero,
    int? episodeIndex,
  }) async {
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

    final historyItem = WatchHistoryItem(
      id: mediaItem.dataSourceId,
      title: mediaItem.title.isNotEmpty
          ? mediaItem.title
          : previous?.title ?? '未知视频',
      poster: mediaItem.posterUrl ?? previous?.poster ?? '',
      position: normalizedPosition,
      duration: normalizedDuration,
      updatedAt: DateTime.now(),
      sourceType: mediaItem.sourceType,
    );

    await updateProgress(historyItem, episodeIndex: episodeIndex);
  }

  // Private methods
  Future<void> _loadWatchHistory() async {
    try {
      debugPrint('MeowHub-Log: 开始获取观看历史...');
      _watchHistory = await _watchHistoryRepository.getHistoryBySource(
        WatchSourceType.emby,
      );

      debugPrint('MeowHub-Log: 获取成功，数量: ${_watchHistory.length}');
      if (_watchHistory.isNotEmpty) {
        debugPrint('MeowHub-Log: 第一条数据标题: ${_watchHistory.first.title}');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('MeowHub-Log: 获取历史失败，错误详情: $e');
    }
  }

  WatchHistoryRepository _buildWatchHistoryRepository() {
    final mediaService = _mediaServiceManager.currentService;
    if (mediaService != null) {
      return WatchHistoryRepositoryImpl(
        embyRemoteDataSource: RemoteWatchHistoryDataSourceAdapter(
          mediaService: mediaService,
        ),
        localDataSource: InMemoryLocalWatchHistoryDataSource(),
      );
    }

    return WatchHistoryRepositoryImpl(
      embyRemoteDataSource: MockEmbyWatchHistoryRemoteDataSource(
        initialHistory: [
          WatchHistoryItem(
            id: '1002',
            title: 'Moonlit Harbor',
            poster: '',
            position: Duration(minutes: 34, seconds: 12),
            duration: Duration(hours: 1, minutes: 52, seconds: 18),
            updatedAt: DateTime(2026, 4, 12, 20, 30),
            sourceType: WatchSourceType.emby,
          ),
          WatchHistoryItem(
            id: '1007',
            title: 'Glass Kingdom',
            poster: '',
            position: Duration(minutes: 12, seconds: 5),
            duration: Duration(hours: 2, minutes: 6, seconds: 40),
            updatedAt: DateTime(2026, 4, 11, 21, 10),
            sourceType: WatchSourceType.emby,
          ),
        ],
      ),
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

  void _upsertWatchHistory(WatchHistoryItem item, {int? episodeIndex}) {
    _watchHistory = <WatchHistoryItem>[
      item,
      ..._watchHistory.where(
        (historyItem) => historyItem.uniqueKey != item.uniqueKey,
      ),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    if (episodeIndex != null) {
      _recentEpisodeIndices[item.id] = episodeIndex;
    }

    notifyListeners();
  }
}

class MediaPlaybackProgress {
  const MediaPlaybackProgress({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration <= Duration.zero) {
      return 0;
    }

    final rawFraction = position.inMilliseconds / duration.inMilliseconds;
    return rawFraction.clamp(0.0, 1.0).toDouble();
  }

  MediaPlaybackProgress copyWith({Duration? position, Duration? duration}) {
    return MediaPlaybackProgress(
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }
}
