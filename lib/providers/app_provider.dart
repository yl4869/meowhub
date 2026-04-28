import 'dart:async';

import 'package:flutter/foundation.dart';
import '../domain/repositories/i_media_service_manager.dart';
import '../core/persistence/file_source_store.dart';
import '../domain/entities/media_service_config.dart';

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
    return PersistedFileSource(id: id, name: name, config: config!);
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
  static const MediaServerInfo _unselectedServer = MediaServerInfo(
    id: 'no-source-selected',
    name: '未选择文件源',
    baseUrl: '',
    type: MediaServiceType.emby,
    region: '可随时从文件源页选择服务器',
  );
  static const MediaServerInfo _emptySourceServer = MediaServerInfo(
    id: 'empty-source',
    name: '未添加文件源',
    baseUrl: '',
    type: MediaServiceType.emby,
    region: '请先添加服务器',
  );

  // 1. 定义订阅变量，用于后续销毁
  StreamSubscription<MediaServiceConfig?>? _configSubscription;

  AppProvider({
    required IMediaServiceManager mediaServiceManager, // ✅ 改为接口
    required FileSourceStore fileSourceStore,
    required List<MediaServerInfo> initialServers,
    required String? initialSelectedServerId,
  }) : _mediaServiceManager = mediaServiceManager,

       _fileSourceStore = fileSourceStore {
    // --- 🚀 新增：放置监听逻辑的位置 ---
    _configSubscription = _mediaServiceManager.configStream.listen((config) {
      // 只要底层 Manager 的配置变了（无论是因为重连、过期更新还是切换）
      // 都会触发此处的 UI 通知
      notifyListeners();
    });

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
    if (hasSelectedServer && selectedServer.config != null) {
      unawaited(_mediaServiceManager.setConfig(selectedServer.config!));
    }
  }

  final IMediaServiceManager _mediaServiceManager; // ✅ 改为接口
  final FileSourceStore _fileSourceStore;

  // 核心存储：Map 是唯一的真理 (Single Source of Truth)
  final Map<String, MediaServerInfo> _serverMap = {};

  // 状态追踪：只记 ID，不记对象
  String _selectedServerId = '';

  static List<MediaServerInfo> _buildInitialServers(
    IMediaServiceManager manager,
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

    return const [];
  }

  /// 内部辅助：解析初始选中的 ID
  String _resolveInitialId(String? initialId) {
    if (initialId != null && _serverMap.containsKey(initialId)) {
      return initialId;
    }
    return '';
  }

  static String _defaultServerName(MediaServiceConfig config) {
    final host = Uri.tryParse(config.normalizedServerUrl)?.host.trim() ?? '';
    if (host.isNotEmpty) {
      return host;
    }

    return '${config.type.displayName} 默认源';
  }

  // Getters
  /// 实时获取选中对象：这样 Map 更新，UI 会立即看到新名字
  MediaServerInfo get selectedServer {
    final selected = _serverMap[_selectedServerId];
    if (selected != null) {
      return selected;
    }
    return _serverMap.isEmpty ? _emptySourceServer : _unselectedServer;
  }

  /// 提供给 UI 的列表：由 Map 动态生成
  List<MediaServerInfo> get availableServers => _serverMap.values.toList();

  bool get hasSelectedServer =>
      _selectedServerId.isNotEmpty && _serverMap[_selectedServerId] != null;

  IMediaServiceManager get mediaServiceManager => _mediaServiceManager;

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

  void clearSelectedServer() {
    if (_selectedServerId.isEmpty) {
      return;
    }

    _selectedServerId = '';
    notifyListeners();
    unawaited(_persistState());
  }

  Future<void> addConfiguredServer({
    required String? customName,
    required MediaServiceConfig config,
  }) async {
    await saveConfiguredServer(customName: customName, config: config);
  }

  Future<void> saveConfiguredServer({
    required String? customName,
    required MediaServiceConfig config,
    String? editingServerId,
  }) async {
    final updatedServer = MediaServerInfo.fromConfig(
      config: config,
      name: customName,
    );
    final isEditing = editingServerId != null && editingServerId.isNotEmpty;
    final wasSelectedServer = editingServerId == _selectedServerId;

    if (isEditing && editingServerId != updatedServer.id) {
      _serverMap.remove(editingServerId);
    }

    _serverMap[updatedServer.id] = updatedServer;

    if (!isEditing || wasSelectedServer) {
      _selectedServerId = updatedServer.id;
    }

    await _persistState();
    notifyListeners();
  }

  Future<void> _persistState() async {
    final current = hasSelectedServer ? _serverMap[_selectedServerId] : null;
    final currentConfig = current?.config;

    // 1. 激活配置到 Manager
    if (currentConfig != null) {
      await _mediaServiceManager.setConfig(currentConfig);
    } else {
      await _mediaServiceManager.clearConfig();
    }

    // 2. 提取所有有效的服务器进行持久化
    final persistedSources = _serverMap.values
        .map((s) => s.toPersistedSource)
        .whereType<PersistedFileSource>() // 自动过滤掉 null (占位符)
        .toList();

    await _fileSourceStore.save(
      PersistedFileSourceState(
        sources: persistedSources,
        selectedSourceId: hasSelectedServer ? _selectedServerId : null,
      ),
    );
  }

  @override
  void dispose() {
    // 当 AppProvider 被销毁时（例如应用彻底关闭或切换用户）
    // 必须取消流订阅，防止内存泄漏
    _configSubscription?.cancel();
    super.dispose();
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
