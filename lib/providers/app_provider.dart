import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/datasources/emby_watch_history_remote_data_source.dart';
import '../data/datasources/local_watch_history_data_source.dart';
import '../data/repositories/watch_history_repository_impl.dart';
import '../domain/entities/watch_history_item.dart';
import '../domain/repositories/watch_history_repository.dart';
import '../domain/usecases/get_unified_history.dart';
import '../domain/usecases/update_watch_progress.dart';
import '../models/media_item.dart';

class MediaServerInfo {
  const MediaServerInfo({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.region = '',
  });

  final String id;
  final String name;
  final String baseUrl;
  final String region;
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

class AppProvider extends ChangeNotifier {
  AppProvider({
    WatchHistoryRepository? watchHistoryRepository,
    SharedPreferences? preferences,
  }) : _selectedServer = _defaultServers.first,
       _selectedWatchSource = WatchSourceType.emby,
       _recentEpisodeIndices = {'1002': 2, '1007': 0},
       _preferences = preferences {
    _watchHistoryRepository =
        watchHistoryRepository ?? _buildDefaultWatchHistoryRepository();
    _getUnifiedHistory = GetUnifiedHistoryUseCase(_watchHistoryRepository);
    _updateWatchProgress = UpdateWatchProgressUseCase(_watchHistoryRepository);
    _initializeWatchSource();
  }

  static const String _watchSourceKey = 'selected_watch_source';

  static const List<MediaServerInfo> _defaultServers = [
    MediaServerInfo(
      id: 'meow-main',
      name: '喵云主线',
      baseUrl: 'https://media-main.meowhub.app',
      region: '全球',
    ),
    MediaServerInfo(
      id: 'meow-cn',
      name: '喵云加速',
      baseUrl: 'https://media-cn.meowhub.app',
      region: '中国大陆',
    ),
    MediaServerInfo(
      id: 'meow-backup',
      name: '喵云备用',
      baseUrl: 'https://media-backup.meowhub.app',
      region: '故障切换',
    ),
  ];

  final Map<int, MediaItem> _favoriteItems = {};
  final Map<String, int> _recentEpisodeIndices;
  late final WatchHistoryRepository _watchHistoryRepository;
  late final GetUnifiedHistoryUseCase _getUnifiedHistory;
  late final UpdateWatchProgressUseCase _updateWatchProgress;
  final SharedPreferences? _preferences;

  MediaServerInfo _selectedServer;
  WatchSourceType _selectedWatchSource;
  List<WatchHistoryItem> _watchHistory = const [];

  UnmodifiableListView<MediaServerInfo> get availableServers {
    return UnmodifiableListView(_defaultServers);
  }

  MediaServerInfo get selectedServer => _selectedServer;

  WatchSourceType get selectedWatchSource => _selectedWatchSource;

  UnmodifiableListView<MediaItem> get favoriteItems {
    return UnmodifiableListView(_favoriteItems.values);
  }

  UnmodifiableListView<WatchHistoryItem> get watchHistory {
    return UnmodifiableListView(_watchHistory);
  }

  int get favoriteCount => _favoriteItems.length;

  int get inProgressCount {
    return _watchHistory
        .where((item) => item.position > Duration.zero)
        .length;
  }

  List<int> get recentPlaybackMediaIds {
    return _watchHistory
        .map((item) => int.tryParse(item.id))
        .whereType<int>()
        .toList(growable: false);
  }

  int? get latestRecentMediaId {
    if (_watchHistory.isEmpty) {
      return null;
    }
    return int.tryParse(_watchHistory.first.id);
  }

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

  int episodeIndexFor(int mediaId) {
    return _recentEpisodeIndices[mediaId.toString()] ?? 0;
  }

  double progressFractionFor(int mediaId) {
    return playbackProgressFor(mediaId)?.fraction ?? 0;
  }

  void selectServer(MediaServerInfo server) {
    if (_selectedServer.id == server.id) {
      return;
    }

    _selectedServer = server;
    notifyListeners();
  }

  void selectWatchSource(WatchSourceType sourceType) {
    if (_selectedWatchSource == sourceType) {
      return;
    }

    _selectedWatchSource = sourceType;
    _saveWatchSource();
    loadWatchHistory();
  }

  Future<void> _initializeWatchSource() async {
    if (_preferences != null) {
      final savedSource = _preferences!.getString(_watchSourceKey);
      if (savedSource != null) {
        _selectedWatchSource = WatchSourceType.fromJson(savedSource);
      }
    }
    await loadWatchHistory();
  }

  Future<void> _saveWatchSource() async {
    if (_preferences != null) {
      await _preferences!.setString(_watchSourceKey, _selectedWatchSource.toJson());
    }
  }

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
    _watchHistory = await _watchHistoryRepository.getHistoryBySource(_selectedWatchSource);
    notifyListeners();
  }

  Future<void> refreshWatchHistory() async {
    await loadWatchHistory();
  }

  Future<void> updateProgress(
    WatchHistoryItem item, {
    int? episodeIndex,
  }) async {
    _upsertWatchHistory(item, episodeIndex: episodeIndex);
    await _updateWatchProgress(item);
    await loadWatchHistory();
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
    final previous = _watchHistoryItemFor(mediaId.toString(), sourceType: sourceType);
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
    final previous = _watchHistoryItemFor(mediaId.toString(), sourceType: sourceType);
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

  WatchHistoryItem? _watchHistoryItemFor(
    String id, {
    WatchSourceType? sourceType,
  }) {
    for (final item in _watchHistory) {
      if (item.id == id && (sourceType == null || item.sourceType == sourceType)) {
        return item;
      }
    }
    return null;
  }

  void _upsertWatchHistory(WatchHistoryItem item, {int? episodeIndex}) {
    _watchHistory = <WatchHistoryItem>[
      item,
      ..._watchHistory.where((historyItem) => historyItem.uniqueKey != item.uniqueKey),
    ]..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    if (episodeIndex != null) {
      _recentEpisodeIndices[item.id] = episodeIndex;
    }

    notifyListeners();
  }

  static WatchHistoryRepository _buildDefaultWatchHistoryRepository() {
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
}
