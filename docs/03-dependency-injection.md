# 03 - 依赖注入

## 概述

MeowHub 使用 `provider` 库实现依赖注入。所有依赖在 `main.dart` 的 `MeowHubApp.build()` 中通过 `MultiProvider` 统一装配。依赖图是单向的：上层 Provider 依赖下层，不存在循环依赖。

## Provider 注入树

```
MultiProvider
│
├── ChangeNotifierProvider<AppProvider>
│     依赖: IMediaServiceManager, FileSourceStore
│     职责: 服务器选择、服务器列表管理
│
├── Provider<IMediaServiceManager>.value
│     依赖: SharedPreferences
│     职责: 服务配置存取（全局单例）
│
├── Provider<MediaConfigValidator>.value
│     依赖: SecurityService, SessionExpiredNotifier
│     职责: 连接验证回调
│
├── Provider<SecurityService>.value
│     职责: Token/密码安全存储
│
├── ChangeNotifierProvider<CapabilityProber>.value
│     职责: 设备屏幕/平台能力快照
│
├── ChangeNotifierProvider<SessionExpiredNotifier>.value
│     职责: 登录过期状态通知
│
├── ProxyProvider4<AppProvider, SecurityService, SessionExpiredNotifier, CapabilityProber, EmbyApiClient?>
│     条件创建: config.type ∈ {emby, jellyfin} 且 config 变更
│     职责: Emby HTTP 客户端单例
│
├── ProxyProvider3<AppProvider, EmbyApiClient?, SecurityService, IMediaRepository>
│     通过 MediaRepositoryFactory 创建:
│       - 无 config → EmptyMediaRepositoryImpl
│       - USE_MOCK_REPOSITORY=true → MockMediaRepositoryImpl
│       - 正常 → EmbyMediaRepositoryImpl
│
├── ProxyProvider3<AppProvider, EmbyApiClient?, SecurityService, PlaybackRepository>
│     通过 MediaRepositoryFactory 创建:
│       - 无 config → UnavailablePlaybackRepository
│       - 正常 → EmbyPlaybackRepositoryImpl
│
├── ProxyProvider2<AppProvider, EmbyApiClient?, WatchHistoryRepository>
│     通过 MediaRepositoryFactory 创建 WatchHistoryRepositoryImpl
│
├── ChangeNotifierProxyProvider2<IMediaServiceManager, WatchHistoryRepository, UserDataProvider>
│     依赖: IMediaServiceManager, WatchHistoryRepository
│     构造时: 启动后台历史同步, 加载首次历史
│
├── ChangeNotifierProxyProvider<IMediaRepository, MediaLibraryProvider>
│     构造时: 调用 loadInitialMedia()
│
└── ChangeNotifierProxyProvider2<MediaLibraryProvider, UserDataProvider, MediaWithUserDataProvider>
      依赖: MediaLibraryProvider, UserDataProvider
      职责: 合并媒体库 + 用户数据 → 展示态
```

## 依赖拓扑图

```
SharedPreferences ─────────┐
                            ▼
                    IMediaServiceManager ──┬──▶ AppProvider
                                           │        │
                    FileSourceStore ───────┘        │
                                                    ▼
                    SecurityService ◀──────── EmbyApiClient?
                         │                          │
                    SessionExpiredNotifier ─────────┘
                         │                          │
                    CapabilityProber ───────────────┘
                                                    │
                    ┌───────────────────────────────┤
                    ▼                               ▼
            IMediaRepository               WatchHistoryRepository
                    │                               │
                    ▼                               ▼
            MediaLibraryProvider             UserDataProvider
                    │                               │
                    └──────────┬────────────────────┘
                               ▼
                  MediaWithUserDataProvider
```

## Provider 更新机制

### ProxyProvider 链式更新

当 `AppProvider` 调用 `notifyListeners()` 时（例如选中了新的服务器），触发以下级联更新：

1. `EmbyApiClient?` ProxyProvider 检测 config 变化，重建 ApiClient
2. `IMediaRepository` ProxyProvider 检测变化，重建 MediaRepository
3. `PlaybackRepository` ProxyProvider 检测变化，重建 PlaybackRepository
4. `WatchHistoryRepository` ProxyProvider 检测变化，重建 WatchHistoryRepository
5. `UserDataProvider` 检测 WatchHistoryRepository 变化，调用 `updateDependencies()`
6. `MediaLibraryProvider` 检测 IMediaRepository 变化，调用 `updateRepository()`
7. `MediaWithUserDataProvider` 检测子 Provider 变化，调用 `updateDependencies()`

### updateDependencies 模式

大多数 Provider 实现了 `updateDependencies()` 方法而非直接重建实例：

```dart
update: (context, repo, previous) {
  final provider = previous ?? MediaLibraryProvider(mediaRepository: repo);
  provider.updateRepository(repo);
  return provider;
}
```

这样做的好处：
- 保持 Provider 实例引用稳定（UI 中的 `context.watch` 不会因为实例替换而重建）
- 内部只更新可变依赖，不清空无关状态
- namespace 变更时触发完整重置

### configStream 驱动的更新

`IMediaServiceManager.configStream` 是一个 Dart `Stream`。`AppProvider` 在构造时订阅此流，当外部（如登录页）调用 `setConfig()` 时，通过流触发 `AppProvider.notifyListeners()`，进而触发整个 ProxyProvider 链。

## 路由级依赖注入

部分依赖仅在特定路由生效：

### MediaDetailProvider（路由级）
在 GoRouter 的 `/media/:id` 路由中，通过 `ChangeNotifierProxyProvider3` 创建：

```dart
ChangeNotifierProxyProvider3<UserDataProvider, PlaybackRepository, IMediaRepository, MediaDetailProvider>(
  create: (context) => MediaDetailProvider(
    playbackRepository: context.read<PlaybackRepository>(),
    userDataProvider: context.read<UserDataProvider>(),
    mediaRepository: context.read<IMediaRepository>(),
  ),
  ...
)
```

此 Provider 仅在该路由的 Widget 子树中可用，离开页面即销毁。

### MediaConfigValidator（回调注入）
`_buildMediaConfigValidator()` 创建一个闭包，封装 EmbyApiClient 的临时创建和认证逻辑，以 `Provider<MediaConfigValidator>.value` 注入，供登录页验证连接。

## 测试中的替换

通过编译常量和工厂模式，测试时可以替换整个 Repository 层：

```bash
# Mock 数据（无服务器）
flutter run --dart-define=USE_MOCK_REPOSITORY=true
```

`MediaRepositoryFactory` 的 `createMediaRepository()` 检查此常量并返回 `MockMediaRepositoryImpl`，无需修改任何 UI 或 Provider 代码。
