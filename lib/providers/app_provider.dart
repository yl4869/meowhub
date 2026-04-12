import 'dart:collection';

import 'package:flutter/foundation.dart';

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
  AppProvider()
    : _selectedServer = _defaultServers.first,
      _recentMediaIds = [1002, 1007],
      _playbackProgress = {
        1002: const MediaPlaybackProgress(
          position: Duration(minutes: 34, seconds: 12),
          duration: Duration(hours: 1, minutes: 52, seconds: 18),
        ),
        1007: const MediaPlaybackProgress(
          position: Duration(minutes: 12, seconds: 5),
          duration: Duration(hours: 2, minutes: 6, seconds: 40),
        ),
      };

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
  final Map<int, MediaPlaybackProgress> _playbackProgress;
  final List<int> _recentMediaIds;
  MediaServerInfo _selectedServer;

  UnmodifiableListView<MediaServerInfo> get availableServers {
    return UnmodifiableListView(_defaultServers);
  }

  MediaServerInfo get selectedServer => _selectedServer;

  UnmodifiableListView<MediaItem> get favoriteItems {
    return UnmodifiableListView(_favoriteItems.values);
  }

  int get favoriteCount => _favoriteItems.length;

  int get inProgressCount {
    return _playbackProgress.values
        .where((progress) => progress.position > Duration.zero)
        .length;
  }

  List<int> get recentPlaybackMediaIds {
    return List<int>.unmodifiable(_recentMediaIds);
  }

  int? get latestRecentMediaId {
    if (_recentMediaIds.isEmpty) {
      return null;
    }
    return _recentMediaIds.first;
  }

  bool isFavorite(int mediaId) => _favoriteItems.containsKey(mediaId);

  MediaPlaybackProgress? playbackProgressFor(int mediaId) {
    return _playbackProgress[mediaId];
  }

  double progressFractionFor(int mediaId) {
    return _playbackProgress[mediaId]?.fraction ?? 0;
  }

  void selectServer(MediaServerInfo server) {
    if (_selectedServer.id == server.id) {
      return;
    }

    _selectedServer = server;
    notifyListeners();
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

  void updatePlaybackProgress({
    required int mediaId,
    required Duration position,
    Duration duration = Duration.zero,
  }) {
    final previous = _playbackProgress[mediaId];
    final normalizedPosition = position < Duration.zero
        ? Duration.zero
        : position;
    final normalizedDuration = duration > Duration.zero
        ? duration
        : previous?.duration ?? Duration.zero;

    _playbackProgress[mediaId] = MediaPlaybackProgress(
      position: normalizedPosition,
      duration: normalizedDuration,
    );
    _markRecent(mediaId);
    notifyListeners();
  }

  void markRecentlyWatched(int mediaId) {
    _markRecent(mediaId);
    notifyListeners();
  }

  void clearPlaybackProgress(int mediaId) {
    if (_playbackProgress.remove(mediaId) != null) {
      notifyListeners();
    }
  }

  void _markRecent(int mediaId) {
    _recentMediaIds.remove(mediaId);
    _recentMediaIds.insert(0, mediaId);
  }
}
