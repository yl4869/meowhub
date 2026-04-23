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

  /// 语义化：是否为“占位”状态
  bool get isPlaceholder => id == 'empty-source' || baseUrl.isEmpty;

  /// 语义化：转换为持久化模型
  PersistedFileSource? get toPersistedSource {
    if (isPlaceholder || config == null) return null;
    return PersistedFileSource(
      id: id,
      name: name,
      config: config!,
    );
  }

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

       _fileSourceStore = fileSourceStore{
    
    // 1. 确定初始列表（只计算一次）
    final servers = initialServers.isEmpty
        ? _buildInitialServers(mediaServiceManager)
        : initialServers;

    // 2. 填充 Map
    for (final s in servers) {
      _serverMap[s.id] = s;
    }

    // 3. 确定选中的 ID
    _selectedServerId = _resolveInitialId(initialSelectedServerId);
    
    // 4. (可选) 如果有配置，立即同步给底层 manager
    if (selectedServer.config != null) {
      unawaited(_mediaServiceManager.setConfig(selectedServer.config!));
    }
  }

  final MediaServiceManager _mediaServiceManager;
  final FileSourceStore _fileSourceStore;

  // 核心存储：Map 是唯一的真理 (Single Source of Truth)
  final Map<String, MediaServerInfo> _serverMap = {};
  
  // 状态追踪：只记 ID，不记对象
  String _selectedServerId = '';

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

  /// 内部辅助：解析初始选中的 ID
  String _resolveInitialId(String? initialId) {
    if (initialId != null && _serverMap.containsKey(initialId)) {
      return initialId;
    }
  // 默认选中第一个服务器（即便它是“未添加源”的占位符）
    return _serverMap.keys.isNotEmpty ? _serverMap.keys.first : '';
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
  /// 实时获取选中对象：这样 Map 更新，UI 会立即看到新名字
  MediaServerInfo get selectedServer => 
      _serverMap[_selectedServerId] ?? _serverMap.values.first;

  /// 提供给 UI 的列表：由 Map 动态生成
  List<MediaServerInfo> get availableServers => _serverMap.values.toList();

  MediaServiceManager get mediaServiceManager => _mediaServiceManager;

  // Actions
  void selectServer(MediaServerInfo server) {
    if (_selectedServerId == server.id) {
      return;
    }

    // 更新 ID 即可，Getter 会自动处理对象获取
    _selectedServerId = server.id;
    notifyListeners();
    
    // 这里的持久化方法我们也建议同步简化（见下文）
    unawaited(_persistState());
  }

  void addConfiguredServer({
    required String? customName,
    required MediaServiceConfig config,
  }) {
    final newServer = MediaServerInfo.fromConfig(
      config: config,
      name: customName,
    );

    // 1. 如果当前是占位符，添加真实服务器前先清空
    if (_serverMap.containsKey('empty-source')) {
      _serverMap.clear();
    }

    // 2. 利用 Map 自动去重的特性，直接赋值
    // 如果 ID 存在则覆盖（更新），不存在则新增
    _serverMap[newServer.id] = newServer;
    _selectedServerId = newServer.id;

    notifyListeners();
    unawaited(_persistState());
  }

  Future<void> _persistState() async {
    final current = selectedServer;

    // 1. 激活配置到 Manager
    if (current.config != null) {
      await _mediaServiceManager.setConfig(current.config!);
    }

    // 2. 提取所有有效的服务器进行持久化
    final persistedSources = _serverMap.values
        .map((s) => s.toPersistedSource)
        .whereType<PersistedFileSource>() // 自动过滤掉 null (占位符)
        .toList();

    await _fileSourceStore.save(
      PersistedFileSourceState(
        sources: persistedSources,
        selectedSourceId: current.isPlaceholder ? null : _selectedServerId,
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
