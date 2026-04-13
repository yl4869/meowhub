/// 媒体服务集成使用示例
library;

// ignore_for_file: avoid_print, non_constant_identifier_names

import 'package:meowhub/core/services/security_service.dart';
import 'package:meowhub/core/session/session_expired_notifier.dart';
import 'package:meowhub/domain/entities/media_service_config.dart';
import 'package:meowhub/domain/repositories/media_service.dart';
import 'package:meowhub/domain/repositories/media_service_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 示例 1: 初始化和配置服务
Future<void> example1_InitializeService() async {
  final preferences = await SharedPreferences.getInstance();
  final manager = MediaServiceManager(
    preferences: preferences,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );

  // 初始化（从保存的配置加载）
  await manager.initialize();

  // 检查是否有配置的服务
  if (manager.currentService != null) {
    print('已配置的服务: ${manager.currentService}');
  }
}

/// 示例 2: 配置新的 Emby 服务
Future<void> example2_ConfigureEmbyService() async {
  final preferences = await SharedPreferences.getInstance();
  final manager = MediaServiceManager(
    preferences: preferences,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );

  final config = MediaServiceConfig(
    type: MediaServiceType.emby,
    serverUrl: 'http://192.168.1.100:8096',
    username: 'your-username',
    password: 'your-password',
    deviceId: 'flutter-app',
  );

  // 验证配置
  final isValid = await manager.verifyConfig(config);
  if (isValid) {
    // 保存配置
    await manager.setConfig(config);
    print('配置已保存');
  } else {
    print('配置验证失败');
  }
}

/// 示例 3: 获取观看历史
Future<void> example3_GetWatchHistory() async {
  final preferences = await SharedPreferences.getInstance();
  final manager = MediaServiceManager(
    preferences: preferences,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );
  await manager.initialize();

  final service = manager.currentService;
  if (service != null) {
    try {
      final history = await service.getWatchHistory();
      for (final item in history) {
        print('${item.title} - ${item.position}/${item.duration}');
      }
    } catch (e) {
      print('获取历史记录失败: $e');
    }
  }
}

/// 示例 4: 更新播放进度
Future<void> example4_UpdatePlaybackProgress() async {
  final preferences = await SharedPreferences.getInstance();
  final manager = MediaServiceManager(
    preferences: preferences,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );
  await manager.initialize();

  final service = manager.currentService;
  if (service != null) {
    try {
      // 获取历史记录
      final history = await service.getWatchHistory();
      if (history.isNotEmpty) {
        // 更新第一个项目的播放进度
        final item = history.first;
        final updatedItem = item.copyWith(position: Duration(minutes: 45));
        await service.updatePlaybackProgress(updatedItem);
        print('播放进度已更新');
      }
    } catch (e) {
      print('更新播放进度失败: $e');
    }
  }
}

/// 示例 5: 使用工厂创建服务
Future<void> example5_UseFactory() async {
  final config = MediaServiceConfig(
    type: MediaServiceType.emby,
    serverUrl: 'http://localhost:8096',
    username: 'demo',
    password: 'demo-password',
  );

  // 使用工厂创建服务
  final service = MediaServiceFactory.create(
    config,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );

  // 验证连接
  final isConnected = await service.verifyConnection();
  print('连接状态: $isConnected');
}

/// 示例 6: 清除配置
Future<void> example6_ClearConfig() async {
  final preferences = await SharedPreferences.getInstance();
  final manager = MediaServiceManager(
    preferences: preferences,
    securityService: SecurityService(),
    sessionExpiredNotifier: SessionExpiredNotifier(),
  );

  await manager.clearConfig();
  print('配置已清除');
}

/// 示例 7: 在 Provider 中使用
///
/// 在 AppProvider 中：
/// ```dart
/// class AppProvider extends ChangeNotifier {
///   final MediaServiceManager _mediaServiceManager;
///
///   Future<void> loadWatchHistory() async {
///     final service = _mediaServiceManager.currentService;
///     if (service != null) {
///       _watchHistory = await service.getWatchHistory();
///       notifyListeners();
///     }
///   }
/// }
/// ```

/// 示例 8: 扩展新的服务提供商
///
/// 1. 创建新的服务实现：
/// ```dart
/// class PlexMediaService implements MediaService {
///   PlexMediaService(this._config);
///
///   final MediaServiceConfig _config;
///
///   @override
///   MediaServiceConfig get config => _config;
///
///   @override
///   Future<bool> verifyConnection() async {
///     // 实现 Plex 连接验证
///     return true;
///   }
///
///   @override
///   Future<List<WatchHistoryItem>> getWatchHistory() async {
///     // 实现获取 Plex 观看历史
///     return [];
///   }
///
///   @override
///   Future<void> updatePlaybackProgress(WatchHistoryItem item) async {
///     // 实现更新 Plex 播放进度
///   }
/// }
/// ```
///
/// 2. 更新工厂类：
/// ```dart
/// class MediaServiceFactory {
///   static MediaService create(MediaServiceConfig config) {
///     return switch (config.type) {
///       MediaServiceType.emby => EmbyMediaService(config),
///       MediaServiceType.plex => PlexMediaService(config),
///       MediaServiceType.jellyfin => JellyfinMediaService(config),
///     };
///   }
/// }
/// ```
///
/// 3. 在配置 UI 中添加新的服务类型选项

void main() {
  print('这是媒体服务集成的使用示例文件');
  print('请参考 MEDIA_SERVICE_ARCHITECTURE.md 了解详细信息');
}
