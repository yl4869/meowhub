# 06 - 路由系统

## 概述

项目使用 `go_router` 管理路由。路由配置在 `_MeowHubAppState` 中集中定义，与 `MaterialApp.router` 集成。

## 路由表

| 路径 | 页面 | Extra 参数 | 说明 |
|------|------|-----------|------|
| `/login` | `MediaServiceConfigScreen` | — | 服务器配置/登录 |
| `/` | `HomeView` | — | 首页（3 标签：媒体库/文件源/我的） |
| `/media/:id` | `MediaDetailView` | `MediaItem` | 媒体详情页 |
| `/library/:libraryId` | `MediaLibraryCollectionView` | `MediaLibraryInfo` | 媒体库合集页 |
| `/player/:id` | `PlayerView` | `MediaItem` 或 `PlayerViewRoutePayload` | 播放器页 |
| `/sample` | `MobileUiSampleView` | — | UI 组件展示（开发） |

## GoRouter 配置

```dart
GoRouter(
  initialLocation: HomeView.routePath,           // 默认首页
  refreshListenable: sessionExpiredNotifier,     // 监听登录过期
  redirect: (context, state) {
    // 未登录且不是登录页 → 跳转登录页
    if (sessionExpiredNotifier.requiresLogin && !isLoginRoute) {
      return MediaServiceConfigScreen.routePath;
    }
    return null;
  },
  routes: [...]
)
```

## 路由守卫

`SessionExpiredNotifier` 同时作为 `refreshListenable` 和 `redirect` 的判断依据：

1. Emby API 返回 401 → `EmbyAuthInterceptor` 调用 `notifySessionExpired()`
2. GoRouter 检测 `refreshListenable` 变化 → 执行 `redirect`
3. 非登录页 → 重定向到 `/login`
4. 登录成功后 → `markAuthenticated()` → GoRouter 移除重定向

## Extra 参数传递

GoRouter 的 `extra` 机制用于页面间传递对象（非字符串参数）：

```dart
// 跳转详情页
context.push(MediaDetailView.routePath, extra: mediaItem);

// 详情页路由解析
GoRoute(
  path: MediaDetailView.routePath,
  builder: (context, state) {
    final mediaItem = state.extra;
    if (mediaItem is! MediaItem) {
      return _RouteErrorView(message: '作品数据丢失');
    }
    return ChangeNotifierProxyProvider3(...);
  },
);
```

播放器支持两种 extra 类型：
- `MediaItem` — 首次进入，需要从头建立播放会话
- `PlayerViewRoutePayload` — 已预取 `PlaybackPlan`，直接使用

## 路由级 Provider 注入

`/media/:id` 路由注入 `MediaDetailProvider`：

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

此 Provider 仅在详情页的 Widget 子树中可用，离开即销毁。

## 静态路径定义

每个页面 Widget 暴露静态路径常量：

```dart
class HomeView {
  static const String routePath = '/';
}

class PlayerView {
  static const String routePath = '/player/:id';
  static String locationFor(int id) => '/player/$id';
}
```

## 导航使用示例

```dart
// 使用 context.push
context.push('/media/$id', extra: mediaItem);

// 使用 context.go（替换整个栈）
context.go(HomeView.routePath);

// 使用命名路由常量
context.push(PlayerView.locationFor(item.id), extra: item);
```

## 错误处理

路由收到不匹配的 extra 类型时，显示 `_RouteErrorView`：

```dart
if (mediaItem is! MediaItem) {
  return const _RouteErrorView(message: '作品数据丢失，请重新进入。');
}
```

错误视图包含 AppBar 和居中的错误提示文本。
