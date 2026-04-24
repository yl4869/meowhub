# MeowHub 关键接口说明

本文聚焦 MeowHub 项目中“对外提供能力”的关键接口。这里的“接口”不仅指 Dart `abstract class`，也包括项目中实际承担边界职责的公开 Provider API、播放器回调契约以及基础设施服务入口。

建议结合 [docs/architecture.md](/Users/yunlang/meowhub/meowhub/docs/architecture.md) 一起阅读：

- `architecture.md` 关注整体分层和数据流
- 本文关注每个子系统对外暴露的关键入口

## 1. 阅读约定

本文把关键接口分成四类：

- Domain 抽象接口：定义业务边界
- Presentation 状态接口：Provider 对 UI 暴露的公开能力
- Player 契约接口：播放器组件向上层暴露的回调与状态模型
- Infrastructure 接口：面向 Emby 或底层能力的统一访问入口

## 2. 启动与服务配置接口

### 2.1 IMediaServiceManager

文件：

- `lib/domain/repositories/i_media_service_manager.dart`

职责：

- 加载和保存当前媒体服务配置
- 校验配置有效性

关键方法：

- `Future<void> initialize()`
  - 启动时加载本地保存的媒体服务配置
- `MediaServiceConfig? getSavedConfig()`
  - 获取当前激活的媒体服务配置
- `Future<void> setConfig(MediaServiceConfig config)`
  - 设置并持久化当前服务配置
- `Future<void> clearConfig()`
  - 清理当前配置与敏感信息
- `Future<bool> verifyConfig(MediaServiceConfig config, {required MediaConfigValidator validator})`
  - 通过外部注入的验证器校验配置是否可连接

说明：

- 它不直接承载媒体业务数据，而是承载“当前服务环境”。
- 具体持久化与校验实现由 Composition Root 注入。

### 2.2 AppProvider

文件：

- `lib/providers/app_provider.dart`

职责：

- 管理当前选中的媒体服务器
- 管理服务端列表和持久化状态

关键公开成员：

- `MediaServerInfo get selectedServer`
- `List<MediaServerInfo> get availableServers`
- `void selectServer(MediaServerInfo server)`
- `void addConfiguredServer({required String? customName, required MediaServiceConfig config})`

说明：

- `AppProvider` 是 UI 访问“当前选中服务器”和“可用服务器列表”的主要入口。

## 3. Domain 层抽象接口

### 3.1 IMediaRepository

文件：

- `lib/domain/repositories/i_media_repository.dart`

职责：

- 抽象媒体内容访问能力

方法：

- `Future<List<MediaItem>> getMovies()`
- `Future<List<MediaItem>> getSeries()`
- `Future<MediaItem> getMediaDetail(MediaItem item)`
- `Future<List<MediaItem>> getPlayableItems(MediaItem item)`

返回模型：

- `MediaItem`

说明：

- 这是媒体列表、详情页和剧集列表的统一业务入口。
- UI 与 Provider 不应该直接依赖 Emby DTO，而应依赖这个抽象。

### 3.2 PlaybackRepository

文件：

- `lib/domain/repositories/playback_repository.dart`

职责：

- 抽象播放方案构建能力

方法：

- `Future<PlaybackPlan> getPlaybackPlan(MediaItem item, { ... })`

关键参数：

- `maxStreamingBitrate`
- `requireAvc`
- `audioStreamIndex`
- `subtitleStreamIndex`
- `playSessionId`
- `startPosition`

返回模型：

- `PlaybackPlan`

说明：

- 这是“建立播放会话、获得播放地址和媒体源信息”的 Domain 边界。
- 具体实现由 Data 层的 `EmbyPlaybackRepositoryImpl` 提供。

### 3.3 WatchHistoryRepository

文件：

- `lib/domain/repositories/watch_history_repository.dart`

职责：

- 抽象播放开始、播放进度和播放停止的统一汇报能力
- 抽象播放历史读取能力

方法：

- `Future<void> startPlayback(WatchHistoryItem item, { ... })`
- `Future<void> updateProgress(WatchHistoryItem item, { ... })`
- `Future<void> stopPlayback(WatchHistoryItem item, { ... })`
- `Future<List<WatchHistoryItem>> getUnifiedHistory()`
- `Future<List<WatchHistoryItem>> getHistoryBySource(WatchSourceType sourceType)`

关键参数：

- `playSessionId`
- `mediaSourceId`
- `audioStreamIndex`
- `subtitleStreamIndex`

说明：

- 这是播放汇报和续播记录的统一业务边界。

## 4. Domain 层关键数据契约

### 4.1 MediaItem

文件：

- `lib/domain/entities/media_item.dart`

作用：

- 项目中最核心的媒体实体

关键字段：

- `id`
- `sourceId`
- `title`
- `type`
- `posterUrl`
- `backdropUrl`
- `playUrl`
- `playbackProgress`
- `playableItems`
- `seriesId`
- `indexNumber`
- `parentIndexNumber`

关键语义：

- `dataSourceId`
  - 优先使用外部来源 ID
- `mediaKey`
  - 以 `sourceType + dataSourceId` 组成唯一键

### 4.2 PlaybackPlan

文件：

- `lib/domain/entities/playback_plan.dart`

作用：

- 表示一次“可执行的播放方案”

关键字段：

- `url`
- `isTranscoding`
- `playSessionId`
- `mediaSourceId`
- `audioStreams`
- `subtitleStreams`
- `chapters`
- `markers`

说明：

- 播放器页最终依赖它来决定“播什么”和“如何向 Emby 汇报”。

### 4.3 WatchHistoryItem

文件：

- `lib/domain/entities/watch_history_item.dart`

作用：

- 表示一条续播/观看历史记录

关键字段：

- `id`
- `title`
- `poster`
- `position`
- `duration`
- `updatedAt`
- `sourceType`
- `seriesId`
- `parentIndexNumber`
- `indexNumber`

说明：

- 是播放汇报链路与最近观看列表的核心实体。

## 5. Presentation 层状态接口

### 5.1 MediaLibraryProvider

文件：

- `lib/providers/media_library_provider.dart`

职责：

- 管理媒体库基础列表状态

关键公开接口：

- `MediaLibraryState get state`
- `void updateRepository(IMediaRepository mediaRepository)`
- `Future<void> loadInitialMovies()`
- `Future<void> refreshMovies()`
- `Future<void> fetchMovies({bool showLoading = false})`

说明：

- 它只负责“基础媒体数据”，不负责收藏和续播合并。

### 5.2 MediaWithUserDataProvider

文件：

- `lib/providers/media_with_user_data_provider.dart`

职责：

- 把媒体库列表与用户数据合并成最终展示态

关键公开接口：

- `List<MediaItem> get enrichedMovies`
- `List<MediaItem> get enrichedSeries`
- `List<MediaItem> get recentWatching`
- `List<MediaItem> get allItems`
- `bool get isLoading`
- `String? get errorMessage`

说明：

- 首页和列表页通常直接消费这个 Provider 的输出，而不是自己拼装进度和收藏状态。

### 5.3 MediaDetailProvider

文件：

- `lib/providers/media_detail_provider.dart`

职责：

- 管理详情页的可播放集列表和当前选中集

关键公开接口：

- `List<MediaItem> get episodes`
- `int get selectedIndex`
- `bool get isLoading`
- `String? get loadedSeriesKey`
- `Future<void> loadEpisodes(MediaItem series)`
- `void selectEpisode(int index)`
- `void updateUserDataProvider(UserDataProvider userDataProvider)`

说明：

- 它本身不直接请求远端详情，而是消费已经准备好的 `MediaItem.playableItems`。

### 5.4 UserDataProvider

文件：

- `lib/providers/user_data_provider.dart`

职责：

- 管理收藏、观看历史、播放进度、track selection 和播放同步状态

关键查询接口：

- `bool isFavorite(int mediaId)`
- `MediaPlaybackProgress? playbackProgressFor(int mediaId)`
- `MediaPlaybackProgress? playbackProgressForItem(MediaItem mediaItem)`
- `int episodeIndexForItem(MediaItem mediaItem)`
- `String? resumePlayableItemIdForItem(MediaItem mediaItem)`
- `TrackSelection? trackSelectionForItem(MediaItem mediaItem)`
- `List<WatchHistoryItem> get watchHistory`

关键写入接口：

- `bool toggleFavorite(MediaItem mediaItem)`
- `void initializeProgress(List<MediaItem> items)`
- `void setTrackSelectionForItem(MediaItem mediaItem, { ... })`
- `Future<void> updateProgress(WatchHistoryItem item, {int? episodeIndex})`
- `void updatePlaybackProgressForItem(MediaItem mediaItem, { ... })`
- `Future<void> startPlaybackForItem(MediaItem mediaItem, { ... })`
- `Future<void> syncProgressToServerForItem(MediaItem mediaItem, { ... })`
- `Future<void> stopPlaybackForItem(MediaItem mediaItem, { ... })`
- `void markRecentlyWatchedItemMemoryOnly(MediaItem mediaItem, { ... })`

说明：

- 这是当前项目里最重的一个状态接口。
- 从播放器角度看，它几乎就是播放进度同步的应用层入口。

## 6. Player 子系统契约接口

### 6.1 MeowVideoPlaybackStatus

文件：

- `lib/ui/atoms/meow_video_player.dart`

作用：

- 统一播放器状态模型，供上层页面订阅

字段：

- `position`
- `duration`
- `isInitialized`
- `isPlaying`
- `isBuffering`
- `isCompleted`

说明：

- 这是底层播放器状态向页面层传播的标准结构。

### 6.2 MeowVideoPlaybackStatusChanged

文件：

- `lib/ui/atoms/meow_video_player.dart`

定义：

- `typedef MeowVideoPlaybackStatusChanged = void Function(MeowVideoPlaybackStatus status);`

作用：

- 用于把播放器状态回调给上层页面

### 6.3 MeowVideoPlayer

文件：

- `lib/ui/atoms/meow_video_player.dart`

职责：

- 封装 `media_kit`，向上提供统一播放器组件接口

关键构造参数：

- `url`
- `initialPosition`
- `onPlaybackStatusChanged`
- `onPlaybackStarted`
- `onPlayerCreated`
- `subtitleUri`
- `subtitleTitle`
- `subtitleLanguage`
- `disableSubtitleTrack`

关键回调约定：

- `onPlaybackStatusChanged`
  - 连续回传播放器状态
- `onPlaybackStarted`
  - 首次确认开始播放时触发
- `onPlayerCreated`
  - 暴露底层 `Player` 实例，便于上层执行 `stop()` 等操作

说明：

- 对播放器页来说，`MeowVideoPlayer` 是底层渲染和状态事件的唯一接口。

## 7. Infrastructure 接口

### 7.1 EmbyApiClient

文件：

- `lib/data/datasources/emby_api_client.dart`

职责：

- 封装 Emby HTTP 协议
- 统一认证、会话校验、基础 GET/POST

基础接口：

- `Future<void> authenticate()`
- `Future<Response<T>> get<T>(String path, { ... })`
- `Future<Response<T>> post<T>(String path, { ... })`
- `Future<Map<String, dynamic>> getSystemInfo()`

媒体内容接口：

- `Future<EmbyMediaLibraryListDto> getMediaLibraries()`
- `Future<List<EmbyMediaItemDto>> getMediaItems({ ... })`
- `Future<EmbyMediaItemDto> getMediaItemDetail(String itemId)`
- `Future<List<EmbyMediaItemDto>> getEpisodes(String seriesId)`
- `Future<List<Map<String, dynamic>>> getRecentlyWatchedItems()`

播放相关接口：

- `Future<EmbyPlaybackInfoDto> getPlaybackInfo({ ... })`
- `Future<void> reportPlaybackAction({ ... })`
- `Future<String?> buildSubtitleVttUrl({ ... })`

说明：

- `EmbyApiClient` 是 Data 层访问 Emby 的统一底层入口。
- 当前项目已经把它纳入 DI，由多个 Repository 共享。

### 7.2 EmbyWatchHistoryRemoteDataSource

文件：

- `lib/data/datasources/emby_watch_history_remote_data_source.dart`

职责：

- 面向播放历史业务，封装 Emby 的最近观看读取和播放状态汇报

关键方法：

- `Future<void> startPlayback({ ... })`
- `Future<void> updateProgress({ ... })`
- `Future<void> stopPlayback({ ... })`
- `Future<List<EmbyResumeItemDto>> getHistory()`

说明：

- 它是 `WatchHistoryRepositoryImpl` 对接 Emby 的远端适配层。

### 7.3 LocalWatchHistoryDataSource

文件：

- `lib/data/datasources/local_watch_history_data_source.dart`

职责：

- 管理本地播放历史和续播记录的缓存存取

关键方法：

- `Future<void> updateProgress(PlaybackRecord record)`
- `Future<List<PlaybackRecord>> getHistory()`
- `Future<void> replaceHistoryForSource(WatchSourceType sourceType, List<PlaybackRecord> records)`

说明：

- 它是 `WatchHistoryRepositoryImpl` 的本地状态支撑层。

## 8. Repository 实现类与抽象接口的映射关系

当前主要映射关系如下：

```text
IMediaRepository
  -> EmbyMediaRepositoryImpl
  -> MockMediaRepositoryImpl
  -> EmptyMediaRepositoryImpl

PlaybackRepository
  -> EmbyPlaybackRepositoryImpl
  -> _UnavailablePlaybackRepository

WatchHistoryRepository
  -> WatchHistoryRepositoryImpl
```

说明：

- Domain 层只定义抽象。
- Data 层负责具体实现和数据源编排。
- Composition Root 决定最终注入哪个实现。

## 9. 哪些接口最值得优先关注

如果是第一次进入这个项目，建议先看下面这组：

- `IMediaServiceManager`
  - 决定当前应用连接哪个媒体服务
- `IMediaRepository`
  - 决定媒体内容如何被读取
- `PlaybackRepository`
  - 决定播放方案如何生成
- `UserDataProvider`
  - 决定收藏、续播、播放同步如何运转
- `MeowVideoPlayer`
  - 决定播放器状态如何向上层传播
- `EmbyApiClient`
  - 决定 Emby HTTP 协议如何落地

这几组接口串起来，基本就构成了 MeowHub 的核心运行骨架。
