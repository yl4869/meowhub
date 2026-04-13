# 媒体服务快速参考

## 核心文件

| 文件 | 用途 |
|------|------|
| `lib/domain/entities/media_service_config.dart` | 服务配置类 |
| `lib/domain/repositories/media_service.dart` | 服务接口和工厂 |
| `lib/domain/repositories/media_service_manager.dart` | 服务管理器 |
| `lib/data/datasources/emby_api_client.dart` | Emby API 客户端 |
| `lib/data/datasources/emby_watch_history_remote_data_source.dart` | 适配器 |
| `lib/ui/screens/media_service_config_screen.dart` | 配置 UI |

## 快速开始

### 1. 初始化应用
```dart
final manager = MediaServiceManager(preferences: preferences);
await manager.initialize();
```

### 2. 配置服务
```dart
final config = MediaServiceConfig(
  type: MediaServiceType.emby,
  serverUrl: 'http://192.168.1.100:8096',
  apiKey: 'your-api-key',
);
await manager.setConfig(config);
```

### 3. 获取数据
```dart
final service = manager.currentService;
final history = await service?.getWatchHistory();
```

## 添加新的服务提供商

### 步骤
1. 在 `MediaServiceType` 枚举中添加新类型
2. 创建实现 `MediaService` 的类
3. 在 `MediaServiceFactory.create()` 中添加 case
4. 在配置 UI 中添加选项

### 示例：添加 Plex
```dart
// 1. 创建 lib/data/datasources/plex_api_client.dart
class PlexMediaService implements MediaService {
  // 实现接口方法
}

// 2. 更新工厂
MediaServiceType.plex => PlexMediaService(config),

// 3. 更新 UI
ButtonSegment(value: MediaServiceType.plex, label: Text('Plex')),
```

## 常见任务

### 验证连接
```dart
final isValid = await manager.verifyConfig(config);
```

### 清除配置
```dart
await manager.clearConfig();
```

### 获取保存的配置
```dart
final config = manager.getSavedConfig();
```

### 在 Provider 中使用
```dart
class AppProvider extends ChangeNotifier {
  final MediaServiceManager _manager;
  
  Future<void> loadHistory() async {
    final service = _manager.currentService;
    if (service != null) {
      _history = await service.getWatchHistory();
      notifyListeners();
    }
  }
}
```

## API 实现清单

### Emby 端点
- [ ] `GET /emby/System/Info` — 验证连接
- [ ] `GET /emby/Users` — 获取用户
- [ ] `GET /emby/Users/{userId}/Items/ResumeItems` — 观看历史
- [ ] `POST /emby/Users/{userId}/PlayingItems/{itemId}` — 更新进度
- [ ] `GET /emby/Items/{itemId}/Images/Primary` — 获取图片

## 测试

```bash
# 运行所有测试
flutter test

# 运行特定测试
flutter test test/widget_test.dart

# 分析代码
flutter analyze
```

## 故障排除

| 问题 | 解决方案 |
|------|---------|
| 连接失败 | 检查服务器地址和 API 密钥 |
| 获取历史记录为空 | 确保用户在服务器上有观看记录 |
| 图片加载失败 | 检查图片 URL 和网络连接 |

## 相关文档

- `MEDIA_SERVICE_ARCHITECTURE.md` — 详细架构文档
- `lib/examples/media_service_examples.dart` — 代码示例
- `CLAUDE.md` — 项目指南
