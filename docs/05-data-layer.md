# 05 - 数据层

## 概述

Data 层实现 Domain 层定义的抽象接口，负责所有外部数据访问。结构分三层：

```
Domain Repository 接口
        ▲
        │ 实现
Data Repository 实现 ──编排──▶ DataSource ──HTTP──▶ Emby Server
        │                         │
        ▼                         ▼
      DTO ←──映射──→ Entity   本地缓存 (SharedPreferences)
```

## Repository 实现

### EmbyMediaRepositoryImpl

**文件**: `lib/data/repositories/emby_media_repository_impl.dart`

**实现接口**: `IMediaRepository`

核心方法及调用链:

| 方法 | EmbyClient 调用 | 说明 |
|------|----------------|------|
| `getMovies()` | `getMovieItems()` | 获取所有电影 |
| `getSeries()` | `getMediaItems(includeItemTypes: "Series")` | 获取所有剧集 |
| `getMediaDetail(item)` | `getMediaItemDetail()` | 获取详情，对剧集补充 `playableItems`，对电影补充字幕 |
| `getPlayableItems(item)` | `getEpisodes()` | 获取剧集的各集列表 |
| `getRecentWatching(limit)` | `getContinueWatching()` | 继续观看列表 |
| `getMediaLibraries()` | `getMediaLibraries()` | 媒体库列表 |
| `getSeasons(id)` | `getSeasons()` | 季列表 |
| `getEpisodesForSeason()` | `getEpisodes()` | 按季获取剧集 |
| `search(query)` | `getSearchHints()` | 搜索 |
| `getItems(...)` | `getMediaItems(...)` | 通用查询 |

所有 DTO → Entity 转换通过 `EmbyMediaItemDtoMapper` 扩展完成。

### EmbyPlaybackRepositoryImpl

**文件**: `lib/data/repositories/emby_playback_repository_impl.dart`

**实现接口**: `PlaybackRepository`

最复杂的 Repository 实现（约 940 行）。详见 [07-播放系统](07-playback-system.md)。

核心流程:
1. 调用 `getPlaybackInfo()` 获取媒体源列表
2. 选择最佳媒体源（优先 DirectPlay → DirectStream → Transcode）
3. 解析音轨、字幕、章节、片头尾标记
4. 生成带认证参数的播放 URL
5. 结果缓存 12 秒（防止重复请求）

**内嵌图像字幕处理**: PGS/DVDSub 等图形字幕无法在客户端独立渲染时，自动请求服务端转码（将字幕烧录进视频流）。

### WatchHistoryRepositoryImpl

**文件**: `lib/data/repositories/watch_history_repository_impl.dart`

**实现接口**: `WatchHistoryRepository`

协调本地和远端两个数据源：
- **本地**: `LocalWatchHistoryDataSource` — 即时响应，离线可用
- **远端**: `EmbyWatchHistoryRemoteDataSource` — 通过 Emby Sessions API 同步

三个生命周期方法对应 Emby API:
| 方法 | Emby API |
|------|----------|
| `startPlayback()` | `POST /Sessions/Playing` |
| `updateProgress()` | `POST /Sessions/Playing/Progress` |
| `stopPlayback()` | `POST /Sessions/Playing/Stopped` |

### MockMediaRepositoryImpl

**文件**: `lib/data/repositories/mock_media_repository_impl.dart`

提供硬编码 Mock 数据，方便无服务器开发。包含 2 部电影、2 部系列（各 3 季 8 集），模拟 250ms 网络延迟。

通过 `--dart-define=USE_MOCK_REPOSITORY=true` 启用。

### EmptyMediaRepositoryImpl

返回空列表，用于无有效服务配置的场景。

### MediaRepositoryFactory

**文件**: `lib/data/repositories/media_repository_factory.dart`

静态工厂，根据 `MediaServiceType` 创建对应的 Repository：
- `emby` / `jellyfin` → Emby 实现（API 兼容）
- `plex` → Empty/Unavailable（未实现）
- `USE_MOCK_REPOSITORY` → Mock

## DataSource

### EmbyApiClient

**文件**: `lib/data/datasources/emby_api_client.dart`

封装 Emby REST API 的 HTTP 客户端，基于 `Dio`。

**认证**:
- `authenticate()` → `POST /emby/Users/AuthenticateByName`
- 返回的 AccessToken 和 UserId 存入 SecurityService
- 后续请求通过 `EmbyAuthInterceptor` 自动附加 Header

**关键 API 方法**:

| 方法 | HTTP 端点 | 说明 |
|------|-----------|------|
| `getSystemInfo()` | `GET /System/Info` | 服务器信息 |
| `getMediaLibraries()` | `GET /Library/VirtualFolders` | 媒体库列表 |
| `getMediaItems()` | `GET /Items` | 通用媒体查询 |
| `getMediaItemDetail(id)` | `GET /Users/{userId}/Items/{id}` | 媒体详情 |
| `getContinueWatching()` | `GET /Items/Resume` | 继续观看 |
| `getEpisodes(seriesId)` | `GET /Shows/{id}/Episodes` | 剧集列表 |
| `getSeasons(seriesId)` | `GET /Shows/{id}/Seasons` | 季列表 |
| `getPlaybackInfo(...)` | `POST /Items/{id}/PlaybackInfo` | 播放信息（含设备配置） |
| `reportPlaybackAction(...)` | `POST /Sessions/Playing[/Progress\|/Stopped]` | 播放状态上报 |
| `getSearchHints(query)` | `GET /Search/Hints` | 搜索提示 |
| `buildSubtitleVttUrl(...)` | | 构造字幕 VTT URL |

**配置来源**: `MediaServiceConfig`（由 `AppProvider.selectedServer.config` 提供）

### 远端历史数据源

**EmbyWatchHistoryRemoteDataSource（抽象）**
**EmbyWatchHistoryRemoteDataSourceImpl（实现）**

封装了通过 EmbyAPI 的播放历史远端存取，将 `start/updateProgress/stop` 统一映射为 `_report()` 调用。

### 本地历史数据源

**LocalWatchHistoryDataSource（抽象）**
**InMemoryLocalWatchHistoryDataSource（实现）**

基于 `SharedPreferences` 的本地播放进度缓存。存储 JSON 序列化的 `PlaybackRecord` 列表。

## 网络拦截器

### EmbyAuthInterceptor

**文件**: `lib/data/network/emby_auth_interceptor.dart`

`Dio` 的 `QueuedInterceptor`，在每次请求时自动附加：

```
X-Emby-Authorization: MediaBrowser Client="MeowHub", Device="...", DeviceId="...", Version="1.0.0"
X-Emby-Device-Id: <deviceId>
X-Emby-Token: <accessToken>
```

收到 401 响应时：
1. 清除 SecurityService 中的 Token/UserId
2. 触发 `SessionExpiredNotifier.notifySessionExpired()`
3. GoRouter 自动重定向到登录页

## DTO 与映射

### Emby DTO 结构

所有 Emby 专用 DTO 位于 `lib/data/models/emby/`：

| 文件 | 对应 Emby JSON |
|------|---------------|
| `emby_media_item_dto.dart` | Items 查询返回的单个媒体项 |
| `emby_playback_info_dto.dart` | PlaybackInfo 响应 |
| `emby_media_library_dto.dart` | VirtualFolders 响应 |
| `emby_image_tags_dto.dart` | 图片标签引用 |
| `emby_device_profile.dart` | 发送给 Emby 的设备能力描述 |
| `emby_resume_item_dto.dart` | Resume 端点返回的轻量项 |

### EmbyMediaItemDtoMapper

**文件**: `lib/data/models/emby/emby_media_mapper.dart`

`EmbyMediaItemDto` 的扩展方法，负责 DTO → Domain Entity 转换：

- 构建图片 URL（primary/thumb/backdrop/logo）
- 构建播放 URL
- 映射演员信息
- 提取播放进度
- 提取字幕信息

### PlaybackRecord

**文件**: `lib/data/models/playback_record.dart`

本地存储的中间模型，不直接暴露给 UI。提供 `toWatchHistoryItem()` / `fromWatchHistoryItem()` 方法在持久化和领域实体之间转换。

## Utils

### Emby Ticks

**文件**: `lib/core/utils/emby_ticks.dart` 和 `lib/data/utils/emby_ticks.dart`

Emby 的时间单位是 100 纳秒的 tick，提供转换函数：

```dart
int durationToEmbyTicks(Duration d);   // Duration → ticks
Duration embyTicksToDuration(int t);    // ticks → Duration
Duration? durationFromEmbyTicks(dynamic t);
```

## 回退策略

当 EmbyApiClient 不可用时（无配置或不支持的类型）：

| Repository | 回退实现 | 行为 |
|------------|----------|------|
| IMediaRepository | EmptyMediaRepositoryImpl | 返回空列表 |
| PlaybackRepository | UnavailablePlaybackRepository | 抛出 StateError |
| WatchHistoryRepository | WatchHistoryRepositoryImpl | 仅本地数据源 |
