import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/repositories/media_service_manager.dart';

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

/// 全局应用状态 Provider
/// 管理应用级别的配置：服务器选择、观看源选择等
class AppProvider extends ChangeNotifier {
  AppProvider({
    required MediaServiceManager mediaServiceManager,
  }) : _mediaServiceManager = mediaServiceManager,
       _selectedServer = _defaultServers.first,
       _selectedWatchSource = WatchSourceType.emby;

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

  final MediaServiceManager _mediaServiceManager;
  MediaServerInfo _selectedServer;
  WatchSourceType _selectedWatchSource;

  // Getters
  UnmodifiableListView<MediaServerInfo> get availableServers {
    return UnmodifiableListView(_defaultServers);
  }

  MediaServerInfo get selectedServer => _selectedServer;
  WatchSourceType get selectedWatchSource => _selectedWatchSource;
  MediaServiceManager get mediaServiceManager => _mediaServiceManager;

  // Actions
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
    notifyListeners();
  }
}

enum WatchSourceType {
  emby,
  plex,
  jellyfin;

  String toJson() => name;

  static WatchSourceType fromJson(String json) {
    return values.firstWhere(
      (e) => e.name == json,
      orElse: () => WatchSourceType.emby,
    );
  }
}
