# Emby 接口集成指南

## 当前状态

✅ **Emby API 客户端已完整实现**
- `EmbyApiClient` — 完整的Emby API封装
- `EmbyMediaService` — 实现了 `MediaService` 接口
- `MediaServiceManager` — 管理媒体服务的生命周期和配置持久化

## 如何使用真实的Emby接口

### 1. 配置Emby服务器

用户首次打开应用时，会被引导到 `MediaServiceConfigScreen`，需要填写：
- **服务器地址** — Emby服务器的URL（如 `http://192.168.1.100:8096`）
- **用户名** — Emby账户用户名
- **密码** — Emby账户密码
- **设备ID**（可选）— 用于标识客户端设备

### 2. 数据流

配置完成后，数据流如下：

```
UI (AppProvider)
  ↓
WatchHistoryRepository
  ↓
RemoteWatchHistoryDataSourceAdapter
  ↓
MediaService (EmbyMediaService)
  ↓
EmbyApiClient
  ↓
Emby Server API
```

### 3. 关键改动

#### AppProvider (`lib/providers/app_provider.dart`)
- 现在接收 `MediaServiceManager` 参数
- `_buildDefaultWatchHistoryRepository()` 方法会：
  - 如果有配置的媒体服务，使用真实的Emby接口
  - 否则使用Mock数据（开发/测试用）

#### main.dart
- 将 `mediaServiceManager` 传给 `AppProvider`

### 4. 工作流程

1. **首次启动**
   - 应用检查是否有保存的Emby配置
   - 如果没有，跳转到配置屏幕
   - 用户输入服务器信息并验证连接

2. **配置保存**
   - 服务器地址、用户名、设备ID 保存到 `SharedPreferences`
   - 密码保存到安全存储（`SecurityService`）
   - 访问令牌和用户ID也保存到安全存储

3. **加载历史记录**
   - `AppProvider.loadWatchHistory()` 调用 `WatchHistoryRepository`
   - 仓库通过适配器调用 `EmbyMediaService.getWatchHistory()`
   - `EmbyMediaService` 调用 `EmbyApiClient.getResumeItems()`
   - 结果解析为 `WatchHistoryItem` 列表

4. **更新播放进度**
   - 用户播放视频时，`AppProvider.updatePlaybackProgress()` 被调用
   - 通过 `EmbyApiClient.updatePlaybackProgress()` 发送到Emby服务器

## Mock数据

如果没有配置Emby服务器，应用会使用Mock数据进行开发和测试：

```dart
MockEmbyWatchHistoryRemoteDataSource(
  initialHistory: [
    WatchHistoryItem(
      id: '1002',
      title: 'Moonlit Harbor',
      // ...
    ),
    // ...
  ],
)
```

## 安全性

- **密码存储** — 使用 `SecurityService` 的安全存储
- **访问令牌** — 自动管理，过期时自动重新认证
- **会话管理** — `SessionExpiredNotifier` 监听会话过期事件

## 扩展其他媒体服务

架构已为Plex和Jellyfin预留了扩展点：

1. 在 `MediaServiceType` 枚举中添加新类型
2. 实现 `MediaService` 接口
3. 在 `MediaServiceFactory.create()` 中添加工厂方法
4. 在配置UI中添加选项

## 测试

运行应用时，如果没有配置Emby服务器，会自动使用Mock数据。要测试真实接口：

```bash
# 运行应用
flutter run

# 在配置屏幕输入你的Emby服务器信息
```

## 常见问题

**Q: 如何切换Emby服务器？**
A: 在设置中重新配置，或调用 `MediaServiceManager.setConfig()`

**Q: 如何清除配置？**
A: 调用 `MediaServiceManager.clearConfig()`

**Q: 密码存储在哪里？**
A: 使用平台特定的安全存储（iOS Keychain, Android Keystore）
