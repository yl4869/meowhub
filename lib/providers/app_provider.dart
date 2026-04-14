import 'dart:collection';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/persistence/file_source_store.dart';
import '../domain/entities/media_service_config.dart';
import '../domain/repositories/media_service_manager.dart';

class MediaServerInfo {
  const MediaServerInfo({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    this.region = '',
    this.config,
  });

  final String id;
  final String name;
  final String baseUrl;
  final MediaServiceType type;
  final String region;
  final MediaServiceConfig? config;

  factory MediaServerInfo.fromConfig({
    required MediaServiceConfig config,
    String? name,
  }) {
    final normalizedUrl = config.normalizedServerUrl;
    final normalizedUsername = config.username?.trim().toLowerCase() ?? '';
    return MediaServerInfo(
      id: '${config.type.name}:${normalizedUrl.toLowerCase()}:$normalizedUsername',
      name: _resolveDisplayName(name, normalizedUrl, config.type),
      baseUrl: normalizedUrl,
      type: config.type,
      region: config.type.displayName,
      config: config.copyWith(serverUrl: normalizedUrl),
    );
  }

  static String _resolveDisplayName(
    String? name,
    String normalizedUrl,
    MediaServiceType type,
  ) {
    final trimmedName = name?.trim() ?? '';
    if (trimmedName.isNotEmpty) {
      return trimmedName;
    }

    final host = Uri.tryParse(normalizedUrl)?.host.trim() ?? '';
    if (host.isNotEmpty) {
      return host;
    }

    return '${type.displayName} 服务器';
  }
}

/// 全局应用状态 Provider
/// 管理应用级别的配置：服务器选择、观看源选择等
class AppProvider extends ChangeNotifier {
  AppProvider({
    required MediaServiceManager mediaServiceManager,
    required FileSourceStore fileSourceStore,
    required List<MediaServerInfo> initialServers,
    required String? initialSelectedServerId,
  }) : _mediaServiceManager = mediaServiceManager,
       _fileSourceStore = fileSourceStore,
       _availableServers = List<MediaServerInfo>.from(
         initialServers.isEmpty
             ? _buildInitialServers(mediaServiceManager)
             : initialServers,
       ),
       _selectedServer = _resolveInitialSelectedServer(
         initialServers.isEmpty
             ? _buildInitialServers(mediaServiceManager)
             : initialServers,
         initialSelectedServerId,
       );

  final MediaServiceManager _mediaServiceManager;
  final FileSourceStore _fileSourceStore;
  final List<MediaServerInfo> _availableServers;
  MediaServerInfo _selectedServer;

  static List<MediaServerInfo> _buildInitialServers(
    MediaServiceManager manager,
  ) {
    final savedConfig = manager.getSavedConfig();
    if (savedConfig != null) {
      return [
        MediaServerInfo.fromConfig(
          config: savedConfig,
          name: _defaultServerName(savedConfig),
        ),
      ];
    }

    return const [
      MediaServerInfo(
        id: 'empty-source',
        name: '未添加文件源',
        baseUrl: '',
        type: MediaServiceType.emby,
        region: '请先添加服务器',
      ),
    ];
  }

  static String _defaultServerName(MediaServiceConfig config) {
    final host = Uri.tryParse(config.normalizedServerUrl)?.host.trim() ?? '';
    if (host.isNotEmpty) {
      return host;
    }

    return '${config.type.displayName} 默认源';
  }

  static MediaServerInfo _resolveInitialSelectedServer(
    List<MediaServerInfo> servers,
    String? selectedServerId,
  ) {
    if (selectedServerId != null) {
      for (final server in servers) {
        if (server.id == selectedServerId) {
          return server;
        }
      }
    }

    return servers.first;
  }

  // Getters
  UnmodifiableListView<MediaServerInfo> get availableServers {
    return UnmodifiableListView(_availableServers);
  }

  MediaServerInfo get selectedServer => _selectedServer;
  MediaServiceManager get mediaServiceManager => _mediaServiceManager;

  // Actions
  void selectServer(MediaServerInfo server) {
    if (_selectedServer.id == server.id) {
      return;
    }

    _selectedServer = server;
    notifyListeners();
    unawaited(_persistAndActivateSelectedServer(server));
  }

  void addConfiguredServer({
    required String? customName,
    required MediaServiceConfig config,
  }) {
    final newServer = MediaServerInfo.fromConfig(
      config: config,
      name: customName,
    );
    final existingIndex = _availableServers.indexWhere(
      (server) => server.id == newServer.id,
    );

    if (existingIndex >= 0) {
      _availableServers[existingIndex] = newServer;
    } else {
      _availableServers.removeWhere((server) => server.baseUrl.isEmpty);
      _availableServers.add(newServer);
    }

    _selectedServer = newServer;
    notifyListeners();
    unawaited(_persistAndActivateSelectedServer(newServer));
  }

  Future<void> _persistAndActivateSelectedServer(MediaServerInfo server) async {
    final config = server.config;
    if (config != null) {
      await _mediaServiceManager.setConfig(config);
    }

    final persistedSources = _availableServers
        .where((item) => item.config != null && item.baseUrl.isNotEmpty)
        .map(
          (item) => PersistedFileSource(
            id: item.id,
            name: item.name,
            config: item.config!,
          ),
        )
        .toList(growable: false);

    await _fileSourceStore.save(
      PersistedFileSourceState(
        sources: persistedSources,
        selectedSourceId: server.baseUrl.isEmpty ? null : server.id,
      ),
    );
  }
}

extension MediaServiceTypeDisplayName on MediaServiceType {
  String get displayName {
    return switch (this) {
      MediaServiceType.emby => 'Emby',
      MediaServiceType.plex => 'Plex',
      MediaServiceType.jellyfin => 'Jellyfin',
    };
  }
}
