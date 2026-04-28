# 11 - 扩展指南

## 概述

MeowHub 设计为可扩展的多后端架构。本文档说明如何添加新媒体服务、新功能和新 Provider。

## 添加新媒体服务（如 Plex）

### 步骤 1: 确认服务类型

`MediaServiceType` 枚举已定义在 `lib/domain/entities/media_service_config.dart`：

```dart
enum MediaServiceType {
  emby,
  plex,      // 已预留
  jellyfin,  // 已预留（当前通过 Emby API 兼容）
}
```

### 步骤 2: 实现 API Client

参照 `lib/data/datasources/emby_api_client.dart`，新建例如 `plex_api_client.dart`：

```dart
class PlexApiClient {
  PlexApiClient({
    required MediaServiceConfig config,
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  });

  // 实现 Plex 协议的认证、媒体查询、播放等
  Future<void> authenticate() async { ... }
  Future<List<MediaItem>> getMovies() async { ... }
  // ...
}
```

### 步骤 3: 实现 Repository

在 `lib/data/repositories/` 创建 `plex_media_repository_impl.dart`，实现 `IMediaRepository` 接口。

参照 `EmbyMediaRepositoryImpl`，适配 Plex 的 DTO 和 API 语义。

### 步骤 4: 实现 PlaybackRepository（如有）

创建 `plex_playback_repository_impl.dart`，实现 `PlaybackRepository` 接口。

### 步骤 5: 更新 MediaRepositoryFactory

在 `lib/data/repositories/media_repository_factory.dart`：

```dart
static IMediaRepository createMediaRepository({...}) {
  return switch (config.type) {
    MediaServiceType.emby || MediaServiceType.jellyfin =>
      EmbyMediaRepositoryImpl(...),
    MediaServiceType.plex =>
      PlexMediaRepositoryImpl(...),  // 新增
  };
}
```

### 步骤 6: 更新验证器

在 `main.dart` 的 `_buildMediaConfigValidator()` 中添加 Plex 的连接验证逻辑。

### 步骤 7: 更新 UI

- `MediaServiceConfigScreen` — 服务类型选择器已包含 Plex 选项

## 添加新的 Provider

遵循现有模式：

1. 继承 `ChangeNotifier`
2. 在 `main.dart` 的 `MultiProvider` 中注册
3. 如果需要响应其他 Provider 的变化，使用 `ChangeNotifierProxyProvider`

示例模板：
```dart
class MyFeatureProvider extends ChangeNotifier {
  MyFeatureProvider({required IMediaRepository repository})
    : _repository = repository;

  IMediaRepository _repository;

  // 状态
  bool _isLoading = false;
  List<MyData> _items = [];

  // Getters
  bool get isLoading => _isLoading;
  List<MyData> get items => List.unmodifiable(_items);

  // Actions
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _items = await _repository.getSomeData();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Dependency update
  void updateDependencies({required IMediaRepository repository}) {
    if (identical(_repository, repository)) return;
    _repository = repository;
    _items = [];
    unawaited(load());
  }
}
```

## 添加新路由

在 `_MeowHubAppState._router` 中添加 `GoRoute`：

```dart
GoRoute(
  path: '/my-feature',
  builder: (context, state) => const MyFeatureScreen(),
),
```

使用 `extra` 传递参数时，添加类型检查：

```dart
GoRoute(
  path: '/my-feature/:id',
  builder: (context, state) {
    final data = state.extra;
    if (data is! MyDataType) {
      return _RouteErrorView(message: '数据丢失');
    }
    return MyFeatureScreen(data: data);
  },
),
```

## 添加新的 Atom 组件

在 `lib/ui/atoms/` 下创建。原子组件应：
- 高度可复用，不依赖特定业务状态
- 通过参数接收所有数据
- 使用 `context.watch` / `context.read` 谨慎（参数优于隐式依赖）

## 添加移动端和平板端页面

为了支持响应式，新页面需要：

1. 创建响应式入口（`lib/ui/responsive/my_feature_view.dart`）
2. 创建移动端实现（`lib/ui/mobile/my_feature/mobile_my_feature_screen.dart`）
3. 创建平板端实现（`lib/ui/tablet/my_feature/tablet_my_feature_screen.dart`）

入口视图使用 `ResponsiveLayoutBuilder`：

```dart
class MyFeatureView extends StatelessWidget {
  const MyFeatureView({super.key});

  static const String routePath = '/my-feature';

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) => const MobileMyFeatureScreen(),
      tabletBuilder: (context, maxWidth) => TabletMyFeatureScreen(),
    );
  }
}
```

## 代码规范

- Domain 层: 纯 Dart，不依赖 Flutter
- Data 层: 可以依赖 Flutter 的 `SharedPreferences` 等，但应隔离在 DataSource 中
- UI 层: 通过 Provider 消费状态，不直接访问 Repository
- 命名: 抽象接口以 `I` 前缀（如 `IMediaRepository`）
- 使用 `unawaited()` 处理 fire-and-forget 异步调用
