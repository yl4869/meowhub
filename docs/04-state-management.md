# 04 - 状态管理

## 概述

项目使用 `provider` + `ChangeNotifier` 进行状态管理。共有 5 个主要 Provider 加上若干基础设施 Provider。

## Provider 详解

### 1. AppProvider

**文件**: `lib/providers/app_provider.dart`

**职责**: 全局应用配置状态

**核心状态**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `_serverMap` | `Map<String, MediaServerInfo>` | 所有可用服务器（ID 为键） |
| `_selectedServerId` | `String` | 当前选中服务器的 ID |

**公开 getter**:
| Getter | 返回值 | 说明 |
|--------|--------|------|
| `selectedServer` | `MediaServerInfo` | 当前选中服务器（含占位符处理） |
| `availableServers` | `List<MediaServerInfo>` | 所有可用服务器列表 |
| `hasSelectedServer` | `bool` | 是否有有效选中服务器 |

**公开方法**:
- `selectServer(server)` — 切换服务器，持久化选择
- `addConfiguredServer({customName, config})` — 添加新服务器
- `saveConfiguredServer({...})` — 保存/编辑服务器配置
- `clearSelectedServer()` — 清除选择

**更新触发**: `configStream` 监听 + `notifyListeners()` 显式调用

**关联模型**: `MediaServerInfo` — 包含 id, name, baseUrl, type, config 等字段

### 2. MediaLibraryProvider

**文件**: `lib/providers/media_library_provider.dart`

**职责**: 媒体库内容列表状态

**核心状态**: `MediaLibraryState`
| 字段 | 说明 |
|------|------|
| `libraries` | `List<MediaLibraryInfo>` 媒体库列表 |
| `continueWatching` | `List<MediaItem>` 继续观看（仅媒体库数据） |
| `recentlyAdded` | `List<MediaItem>` 最近添加 |
| `libraryItems` | 按 libraryId 索引的媒体项分组 |
| `isLoading` | 加载中 |
| `errorMessage` | 错误信息 |

**公开方法**:
- `fetchAll()` — 并发加载媒体库、继续观看、各库内容
- `loadInitialMedia()` — 首次加载
- `refreshMovies()` / `refreshSeries()` — 刷新特定类型
- `updateRepository(repo)` — 切换 Repository

### 3. UserDataProvider

**文件**: `lib/providers/user_data_provider.dart`

**职责**: 用户个人数据管理（最复杂的 Provider）

**核心状态**:
| 字段 | 类型 | 说明 |
|------|------|------|
| `_historyMap` | `Map<String, WatchHistoryItem>` | 观看历史（uniqueKey 为键） |
| `_favoriteItems` | `Map<int, MediaItem>` | 收藏列表 |
| `_trackSelections` | `Map<String, TrackSelection>` | 音轨/字幕选择偏好（持久化） |
| `_activePlaybackKeys` | `Set<String>` | 当前活跃播放的媒体键 |
| `_lastServerSyncTimes` | `Map<String, DateTime>` | 上次服务器同步时间 |
| `_optimisticSeekStates` | `Map<String, _OptimisticSeekState>` | 乐观 Seek 保护 |
| `_pendingSyncItems` | `List<_PendingSyncItem>` | 离线同步积压队列 |

**派生状态**: `_recentEpisodeIndices`, `_recentPlayableItemIds`（根据 `_historyMap` 自动重建）

**查询接口**:
- `isFavorite(mediaId)` / `playbackProgressFor(mediaId)` / `playbackProgressForItem(mediaItem)`
- `episodeIndexForItem(mediaItem)` / `resumePlayableItemIdForItem(mediaItem)`
- `trackSelectionForItem(mediaItem)` / `progressFractionForItem(mediaItem)`
- `watchHistory` — 按 `updatedAt` 降序排列的历史列表

**写入接口**（详细见 [08-观看历史](08-watch-history.md)）:
- `startPlaybackForItem()` — 开始播放，上报 start 事件
- `syncProgressToServerForItem()` — 心跳同步（15秒节流）
- `stopPlaybackForItem()` — 停止播放，上报 stop 事件
- `updatePlaybackProgressForItem()` — 仅内存更新
- `markContinueWatchingItemMemoryOnly()` — 内存预热（播放前）
- `toggleFavorite()` / `setTrackSelectionForItem()`

**定时任务**:
- 每 15 秒后台同步 `_syncWatchHistoryFromServerInBackground()`
- 播放中允许后台同步（让用户看到其他设备的进度更新）

### 4. MediaWithUserDataProvider

**文件**: `lib/providers/media_with_user_data_provider.dart`

**职责**: 组合 `MediaLibraryProvider` + `UserDataProvider` 产生最终展示数据

**核心状态** (缓存):
| 字段 | 说明 |
|------|------|
| `_cachedContinueWatching` | 继续观看列表（合并了历史进度） |
| `_cachedEnrichedMovies` | 带收藏/进度状态的电竞列表 |
| `_cachedEnrichedSeries` | 带收藏/进度状态的剧集列表 |

**组装逻辑**: `_updateCache()` 从前两个 Provider 读取数据，对每条 `WatchHistoryItem` 反查媒体库，生成带进度信息的 `MediaItem` 列表。

**公开 getter**:
- `enrichedMovies` / `enrichedSeries` — 用于列表展示
- `continueWatching` — 首页"继续观看"横幅
- `allItems` — 用于搜索等全局场景
- `isLoading` / `errorMessage` — 加载状态

### 5. MediaDetailProvider

**文件**: `lib/providers/media_detail_provider.dart`

**职责**: 详情页状态（仅在 `/media/:id` 路由可用）

**核心职责**:
- 管理剧集列表和当前选中剧集索引
- 预取选中剧集的 PlaybackPlan
- 使用 `_requestToken` 取消过期异步请求

**公开成员**:
- `episodes`, `seasons` — 剧集/季列表
- `selectedIndex` / `selectedSeasonIndex` — 当前选中索引
- `selectedEpisodePlaybackPlan` / `isFetchingPlaybackInfo` — 播放预取状态
- `selectSeason(index)` / `selectEpisode(index)` — 切换选择
- `updateDependencies(...)` — 依赖更新

## 基础设施 Provider

### CapabilityProber
`ChangeNotifier` — 持有 `CapabilitySnapshot`（屏幕尺寸、平台、预估视频带宽）。通过 `WidgetsBindingObserver` 监听尺寸变化。

### SessionExpiredNotifier
`ChangeNotifier` — `requiresLogin` 布尔值。Emby 返回 401 时设为 true，GoRouter 据此重定向到登录页。

### SecurityService
无状态 Provider（纯函数式）— 封装 `FlutterSecureStorage`，Web 端降级为 `SharedPreferences`。按 `credentialNamespace` 隔离子域。

## 数据流总览

```
Emby Server
    │
    ▼
EmbyApiClient ──▶ EmbyMediaRepositoryImpl ──▶ IMediaRepository
    │                                                │
    └──▶ EmbyPlaybackRepositoryImpl ──▶ PlaybackRepository
    │                                                │
    └──▶ WatchHistoryRepositoryImpl ──▶ WatchHistoryRepository
                                                     │
                              ┌──────────────────────┤
                              ▼                      ▼
                      MediaLibraryProvider    UserDataProvider
                              │                      │
                              └──────────┬───────────┘
                                         ▼
                              MediaWithUserDataProvider
                                         │
                                         ▼
                                   UI Widgets
```

## Provider 依赖关系

| Provider | 依赖 |
|----------|------|
| AppProvider | IMediaServiceManager, FileSourceStore |
| UserDataProvider | IMediaServiceManager, WatchHistoryRepository |
| MediaLibraryProvider | IMediaRepository |
| MediaWithUserDataProvider | MediaLibraryProvider, UserDataProvider |
| MediaDetailProvider (路由级) | UserDataProvider, PlaybackRepository, IMediaRepository |
