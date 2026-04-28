# 02 - 架构总览

## 总体架构

MeowHub 采用 **Clean Architecture** 分层设计，核心原则：

- 依赖方向从外向内：UI → Provider → Domain ← Data
- Domain 层不依赖任何具体框架或外部库
- Data 层实现 Domain 层定义的接口
- Provider 层作为 UI 和 Domain 之间的编排层

```
┌─────────────────────────────────────────┐
│  UI Layer (ui/)                          │
│  页面、组件、响应式布局                    │
├─────────────────────────────────────────┤
│  State Layer (providers/)                │
│  ChangeNotifier 状态管理、数据组装         │
├─────────────────────────────────────────┤
│  Domain Layer (domain/)                  │
│  实体、仓库抽象、用例                      │
├─────────────────────────────────────────┤
│  Data Layer (data/)                      │
│  仓库实现、数据源、DTO、HTTP 客户端        │
├─────────────────────────────────────────┤
│  Core (core/)                            │
│  安全存储、配置持久化、能力探测            │
└─────────────────────────────────────────┘
```

## 目录结构

```
lib/
├── main.dart                    # 应用入口 + MultiProvider 依赖装配
├── core/                        # 基础设施
│   ├── persistence/             # FileSourceStore - 服务器配置本地持久化
│   ├── services/                # SecurityService - 安全存储
│   │                            # CapabilityProber - 设备能力探测
│   ├── session/                 # SessionExpiredNotifier - 登录过期通知
│   └── utils/                   # Emby ticks 转换工具
├── domain/                      # 领域层（纯 Dart，无 Flutter 依赖）
│   ├── entities/                # 核心实体对象
│   │   ├── media_item.dart      # MediaItem, MediaType, Cast, SubtitleInfo
│   │   ├── playback_plan.dart   # PlaybackPlan, PlaybackStream, VideoChapter
│   │   ├── watch_history_item.dart  # WatchHistoryItem, WatchSourceType
│   │   ├── media_service_config.dart # MediaServiceConfig, MediaServiceType
│   │   ├── media_library_info.dart   # MediaLibraryInfo
│   │   ├── season_info.dart     # SeasonInfo
│   │   └── track_selection.dart # TrackSelectionRequest
│   ├── repositories/            # 仓库接口（抽象）
│   │   ├── i_media_repository.dart         # 媒体内容访问
│   │   ├── playback_repository.dart        # 播放方案获取
│   │   ├── watch_history_repository.dart   # 观看历史同步
│   │   └── i_media_service_manager.dart    # 服务配置管理
│   └── usecases/                # 用例
│       ├── get_playback_plan.dart      # 获取播放方案
│       ├── get_unified_history.dart    # 获取统一历史
│       └── update_watch_progress.dart  # 更新观看进度
├── data/                        # 数据层（Domain 接口的实现）
│   ├── datasources/             # 数据源
│   │   ├── emby_api_client.dart           # Emby HTTP API 客户端
│   │   ├── emby_watch_history_remote_data_source.dart  # 远端历史适配
│   │   └── local_watch_history_data_source.dart        # 本地历史缓存
│   ├── models/                  # 数据传输对象
│   │   ├── playback_record.dart           # 本地存储模型
│   │   ├── emby_auth_response.dart        # 认证响应 DTO
│   │   └── emby/                          # Emby 专用 DTO
│   │       ├── emby_media_item_dto.dart
│   │       ├── emby_media_mapper.dart     # DTO → Entity 映射
│   │       ├── emby_playback_info_dto.dart
│   │       ├── emby_device_profile.dart   # 设备能力描述
│   │       └── ...
│   ├── network/                 # 网络拦截器
│   │   └── emby_auth_interceptor.dart     # Dio 认证拦截器
│   ├── repositories/            # 仓库实现
│   │   ├── emby_media_repository_impl.dart       # Emby 媒体仓库
│   │   ├── emby_playback_repository_impl.dart    # Emby 播放仓库（复杂）
│   │   ├── watch_history_repository_impl.dart    # 历史仓库（合并本地+远端）
│   │   ├── mock_media_repository_impl.dart       # Mock 数据
│   │   ├── empty_media_repository_impl.dart      # 空实现
│   │   ├── media_repository_factory.dart         # 仓库工厂
│   │   └── media_service_manager_impl.dart       # 服务配置管理实现
│   └── utils/
│       └── emby_ticks.dart
├── providers/                   # 状态管理
│   ├── app_provider.dart                # 全局应用状态（服务器选择）
│   ├── media_library_provider.dart      # 媒体库列表状态
│   ├── media_with_user_data_provider.dart # 媒体+用户数据的组合视图
│   ├── media_detail_provider.dart       # 详情页状态
│   └── user_data_provider.dart          # 用户个人数据（历史、收藏、进度）
├── ui/                          # 界面
│   ├── atoms/                   # 原子组件（可复用）
│   ├── responsive/              # 路由入口视图（mobile/tablet 分支）
│   ├── mobile/                  # 移动端屏幕实现
│   ├── tablet/                  # 平板端屏幕实现
│   ├── screens/                 # 独立页面
│   └── file_source/             # 文件源管理 UI
└── theme/
    └── app_theme.dart           # Material 3 暗色主题
```

## 关键设计模式

### Repository 模式
所有数据访问通过抽象接口进行。上层只依赖接口，不关心具体实现（Emby / Jellyfin / Plex / Mock）。

### Factory 模式
`MediaRepositoryFactory` 根据 `MediaServiceType` 创建对应的 Repository 实现，支持在 Emby/Jellyfin/Mock/Empty 之间切换。

### Provider + ChangeNotifier
状态管理基于 Provider 库的 `ChangeNotifier`。全局状态通过 `MultiProvider` 装配，页面级状态通过 `ChangeNotifierProxyProvider` 注入。

### Responsive Layout Builder
`ResponsiveLayoutBuilder` 以 720px 为断点，在移动端和平板端布局间切换。每个页面有 mobile 和 tablet 两个独立实现。

### Adapter 模式
`EmbyMediaItemDtoMapper` 将 Emby API 返回的 JSON 结构映射为领域实体 `MediaItem`，隔离了外部协议变化对内部代码的影响。

## 核心实体关系

```
MediaServiceConfig ──配置──▶ EmbyApiClient
                                  │
                                  ▼
IMediaRepository ◀────实现──── EmbyMediaRepositoryImpl
                                  │
                                  ▼
                             MediaItem
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
            MediaLibraryProvider  MediaDetailProvider  UserDataProvider
                    │             │                   │
                    └─────┬───────┘                   │
                          ▼                           │
              MediaWithUserDataProvider ◀──────────────┘
                          │
                          ▼
                     UI Widgets
```

## 应用入口初始化流程

`main.dart` 中的 `main()` 函数按以下顺序初始化：

1. `SharedPreferences` 实例化
2. `SecurityService` — 安全存储（密码、Token）
3. `SessionExpiredNotifier` — 会话过期通知
4. `CapabilityProber` — 设备能力探测
5. `FileSourceStore` — 服务器配置持久化
6. `MediaServiceManagerImpl` — 服务配置管理
7. Bootstrap：从 `FileSourceStore` 和 `MediaServiceManager` 加载/迁移配置
8. 进入 `MeowHubApp` → `MultiProvider` 装配 → `MaterialApp.router`
