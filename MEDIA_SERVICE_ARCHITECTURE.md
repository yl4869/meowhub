# 媒体服务架构文档

## 概述

MeowHub 采用可扩展的媒体服务架构，支持多个不同的媒体服务提供商（Emby、Plex、Jellyfin等）。该架构遵循 Clean Architecture 原则，确保易于维护和扩展。

## 架构设计

### 核心组件

#### 1. **MediaService 接口** (`lib/domain/repositories/media_service.dart`)
所有媒体服务提供商都必须实现的通用接口：

```dart
abstract class MediaService {
  MediaServiceConfig get config;
  Future<bool> verifyConnection();
  Future<List<WatchHistoryItem>> getWatchHistory();
  Future<void> updatePlaybackProgress(WatchHistoryItem item);
}
```

#### 2. **MediaServiceConfig** (`lib/domain/entities/media_service_config.dart`)
媒体服务配置类，包含：
- 服务类型（Emby、Plex、Jellyfin）
- 服务器地址
- API密钥
- 可选的用户名、密码、设备ID

#### 3. **MediaServiceFactory** (`lib/domain/repositories/media_service.dart`)
工厂类，根据配置创建相应的服务实现：

```dart
final service = MediaServiceFactory.create(config);
```

#### 4. **IMediaServiceManager / MediaServiceManagerImpl**
接口与实现分别位于：
- `lib/domain/repositories/i_media_service_manager.dart`
- `lib/data/repositories/media_service_manager_impl.dart`

管理器负责：
- 保存和加载配置（使用 SharedPreferences）
- 初始化当前活跃的服务
- 验证服务连接

#### 5. **EmbyMediaService** (`lib/data/datasources/emby_api_client.dart`)
Emby 服务的具体实现，包含真实的 API 调用。

#### 6. **RemoteWatchHistoryDataSourceAdapter** (`lib/data/datasources/emby_watch_history_remote_data_source.dart`)
适配器类，将任何 `MediaService` 实现适配为 `EmbyWatchHistoryRemoteDataSource`，确保与现有代码兼容。

## 数据流

```
UI Layer
   ↓
AppProvider (使用 WatchHistoryRepository)
   ↓
WatchHistoryRepository
   ↓
RemoteWatchHistoryDataSourceAdapter
   ↓
MediaService (EmbyMediaService / PexMediaService / etc.)
   ↓
API Client (EmbyApiClient / PexApiClient / etc.)
   ↓
Remote Server
```

## 使用指南

### 初始化

在 `main.dart` 中：

```dart
final mediaServiceManager = MediaServiceManagerImpl(preferences: preferences);
await mediaServiceManager.initialize();
```

### 配置服务

```dart
final config = MediaServiceConfig(
  type: MediaServiceType.emby,
  serverUrl: 'http://192.168.1.100:8096',
  apiKey: 'your-api-key',
);

await mediaServiceManager.setConfig(config);
```

### 验证连接

```dart
final isValid = await mediaServiceManager.verifyConfig(config);
```

### 获取观看历史

```dart
final service = mediaServiceManager.currentService;
if (service != null) {
  final history = await service.getWatchHistory();
}
```

## 扩展新的服务提供商

### 步骤 1：添加服务类型

在 `lib/domain/entities/media_service_config.dart` 中：

```dart
enum MediaServiceType {
  emby,
  plex,
  jellyfin,
  newService,  // 新增
}
```

### 步骤 2：实现 MediaService

创建 `lib/data/datasources/new_service_api_client.dart`：

```dart
class NewServiceMediaService implements MediaService {
  NewServiceMediaService(this._config);

  final MediaServiceConfig _config;

  @override
  MediaServiceConfig get config => _config;

  @override
  Future<bool> verifyConnection() async {
    // 实现连接验证
  }

  @override
  Future<List<WatchHistoryItem>> getWatchHistory() async {
    // 实现获取观看历史
  }

  @override
  Future<void> updatePlaybackProgress(WatchHistoryItem item) async {
    // 实现更新播放进度
  }
}
```

### 步骤 3：更新工厂类

在 `lib/domain/repositories/media_service.dart` 中：

```dart
class MediaServiceFactory {
  static MediaService create(MediaServiceConfig config) {
    return switch (config.type) {
      MediaServiceType.emby => EmbyMediaService(config),
      MediaServiceType.plex => PlexMediaService(config),
      MediaServiceType.jellyfin => JellyfinMediaService(config),
      MediaServiceType.newService => NewServiceMediaService(config),
    };
  }
}
```

### 步骤 4：更新配置 UI

在 `lib/ui/screens/media_service_config_screen.dart` 中添加新的服务类型选项。

## 当前状态

- ✅ Emby 架构已实现（API 调用需要完成）
- ⏳ Plex 支持（预留扩展点）
- ⏳ Jellyfin 支持（预留扩展点）

## API 实现清单

### Emby API 端点

- [ ] `GET /emby/System/Info` - 验证连接
- [ ] `GET /emby/Users` - 获取用户列表
- [ ] `GET /emby/Users/{userId}/Items/Resume` - 获取继续播放列表
- [ ] `POST /emby/Users/{userId}/PlayingItems/{itemId}` - 更新播放进度
- [ ] `GET /emby/Items/{itemId}/Images/Primary` - 获取海报图片

## 测试

### 单元测试

```dart
test('EmbyMediaService verifies connection', () async {
  final config = MediaServiceConfig(
    type: MediaServiceType.emby,
    serverUrl: 'http://localhost:8096',
    apiKey: 'test-key',
  );
  
  final service = EmbyMediaService(config);
  final isValid = await service.verifyConnection();
  
  expect(isValid, true);
});
```

### 集成测试

使用 `MediaServiceConfigScreen` 进行手动测试。

## 最佳实践

1. **错误处理** - 所有 API 调用都应该有适当的错误处理
2. **缓存** - 考虑缓存用户 ID 和其他频繁访问的数据
3. **超时** - 为 HTTP 请求设置合理的超时时间
4. **日志** - 添加适当的日志用于调试
5. **测试** - 为每个新的服务实现编写单元测试

## 相关文件

- `lib/domain/entities/media_service_config.dart` - 配置类
- `lib/domain/repositories/media_service.dart` - 服务接口和工厂
- `lib/domain/repositories/i_media_service_manager.dart` - 服务管理接口
- `lib/data/repositories/media_service_manager_impl.dart` - 服务管理实现
- `lib/data/datasources/emby_api_client.dart` - Emby API 客户端
- `lib/data/datasources/emby_watch_history_remote_data_source.dart` - 适配器
- `lib/ui/screens/media_service_config_screen.dart` - 配置 UI
