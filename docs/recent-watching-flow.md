# 继续播放链路说明

本文聚焦当前项目里“继续播放”的完整获取、更新、组装与消费路径，目标是回答三个问题：

- 继续播放的数据最早从哪里来
- 播放过程中哪些时机会更新它
- UI 最终是怎么把它展示出来的

建议结合以下文件一起阅读：

- [lib/main.dart](/Users/yunlang/meowhub/meowhub/lib/main.dart)
- [lib/providers/app_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/app_provider.dart)
- [lib/providers/user_data_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart)
- [lib/providers/media_with_user_data_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/media_with_user_data_provider.dart)
- [lib/data/repositories/watch_history_repository_impl.dart](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart)
- [lib/data/datasources/emby_watch_history_remote_data_source.dart](/Users/yunlang/meowhub/meowhub/lib/data/datasources/emby_watch_history_remote_data_source.dart)
- [lib/data/datasources/local_watch_history_data_source.dart](/Users/yunlang/meowhub/meowhub/lib/data/datasources/local_watch_history_data_source.dart)
- [lib/ui/responsive/home_view.dart](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/home_view.dart)
- [lib/ui/responsive/media_detail_view.dart](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/media_detail_view.dart)
- [lib/ui/responsive/player_view.dart](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/player_view.dart)
- [lib/ui/mobile/player/mobile_player_screen.dart](/Users/yunlang/meowhub/meowhub/lib/ui/mobile/player/mobile_player_screen.dart)
- [lib/ui/tablet/player/tablet_player_screen.dart](/Users/yunlang/meowhub/meowhub/lib/ui/tablet/player/tablet_player_screen.dart)

## 1. 先说结论

当前“继续播放”并不由 `AppProvider` 维护。

`AppProvider` 的职责只是管理当前选中的媒体服务环境，比如当前选中的服务器、持久化配置、以及把配置同步给 `IMediaServiceManager`。它会间接影响“继续播放读取的是哪一个服务环境”，但不会直接保存或计算继续播放列表。

真正的主链路如下：

```text
AppProvider / IMediaServiceManager
  -> 决定当前服务配置
  -> WatchHistoryRepository
    -> 远端 Emby 历史 + 本地历史
      -> UserDataProvider.watchHistory
      -> MediaWithUserDataProvider.continueWatching
          -> 首页/详情页/播放器读取与展示
```

如果只记一个最核心的归属关系，可以记成：

- 服务环境归 `AppProvider`
- 继续播放原始状态归 `UserDataProvider`
- 继续播放展示态归 `MediaWithUserDataProvider`

## 2. 涉及到的核心对象

### 2.1 AppProvider

文件：

- [lib/providers/app_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/app_provider.dart)

职责：

- 管理当前选中的服务器
- 监听 `IMediaServiceManager.configStream`
- 把当前选中的配置同步给底层 manager

和继续播放的关系：

- 它不保存 `watchHistory`
- 它不生成 `continueWatching`
- 它只决定“当前正在连接哪个媒体服务”

### 2.2 WatchHistoryRepository

文件：

- [lib/domain/repositories/watch_history_repository.dart](/Users/yunlang/meowhub/meowhub/lib/domain/repositories/watch_history_repository.dart)
- [lib/data/repositories/watch_history_repository_impl.dart](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart)

职责：

- 拉取观看历史
- 开始播放时上报
- 播放中上报进度
- 停止播放时上报
- 协调远端和本地缓存

### 2.3 UserDataProvider

文件：

- [lib/providers/user_data_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart)

职责：

- 保存内存中的 `_historyMap`
- 对外暴露排序后的 `watchHistory`
- 提供播放前、播放中、播放退出时的更新入口
- 提供 `playbackProgressForItem`、`episodeIndexForItem`、`resumePlayableItemIdForItem`

它是“继续播放原始数据的单一入口”。

### 2.4 MediaWithUserDataProvider

文件：

- [lib/providers/media_with_user_data_provider.dart](/Users/yunlang/meowhub/meowhub/lib/providers/media_with_user_data_provider.dart)

职责：

- 把媒体库基础数据和 `UserDataProvider.watchHistory` 组合
- 生成 UI 直接消费的 `continueWatching`
- 给电影、剧集列表补上 `isFavorite` 和 `playbackProgress`

它是“继续播放展示态的组装层”。

## 3. 启动时的获取路径

### 3.1 Provider 注入顺序

入口在 [lib/main.dart](/Users/yunlang/meowhub/meowhub/lib/main.dart)。

和继续播放直接相关的部分是：

1. 注入 `IMediaServiceManager`
2. 注入 `WatchHistoryRepository`
3. 创建 `UserDataProvider`
4. 创建 `MediaLibraryProvider`
5. 创建 `MediaWithUserDataProvider`

其中 `UserDataProvider` 在构造时会立即做两件事：

- 启动后台定时同步 `_restartServerWatchHistorySync()`
- 首次加载历史 `_loadWatchHistory()`

### 3.2 首次加载历史

链路如下：

```text
UserDataProvider()
  -> _loadWatchHistory()
    -> WatchHistoryRepository.getHistoryBySource(emby)
      -> WatchHistoryRepositoryImpl._getMergedEmbyHistory()
        -> 本地 local history
        -> 远端 Emby history
        -> merge
    -> _replaceWatchHistoryItemsForSource()
    -> notifyListeners()
```

对应关键位置：

- `UserDataProvider` 初始化与加载：
  - [lib/providers/user_data_provider.dart:34](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:34)
  - [lib/providers/user_data_provider.dart:653](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:653)
- 仓库读取：
  - [lib/data/repositories/watch_history_repository_impl.dart:43](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart:43)
  - [lib/data/repositories/watch_history_repository_impl.dart:180](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart:180)

### 3.3 远端和本地的来源

远端来源：

- `EmbyWatchHistoryRemoteDataSource.getHistory()`
- 最终调用 `EmbyApiClient.getContinueWatching()`

本地来源：

- `LocalWatchHistoryDataSource.getHistory()`
- 当前默认实现是内存版 `InMemoryLocalWatchHistoryDataSource`

也就是说，启动时看到的“继续播放”并不是直接只看 Emby，而是“Emby 返回值 + 本地缓存”经过仓库合并后的结果。

## 4. 内存中的核心状态结构

### 4.1 WatchHistoryItem

文件：

- [lib/domain/entities/watch_history_item.dart](/Users/yunlang/meowhub/meowhub/lib/domain/entities/watch_history_item.dart)

关键字段：

- `id`
- `sourceType`
- `position`
- `duration`
- `updatedAt`
- `seriesId`
- `parentIndexNumber`
- `indexNumber`

关键语义：

- `uniqueKey = ${sourceType.name}:$id`
- `progressFraction` 用于计算进度条比例

### 4.2 UserDataProvider 内部状态

`UserDataProvider` 核心并不是存一个列表，而是几个 map：

- `_historyMap`
  - 真正的观看历史主存储
- `_recentEpisodeIndices`
  - 系列详情页用来决定默认落到哪一集
- `_recentPlayableItemIds`
  - 系列详情页用来定位最近播放的具体可播放条目
- `_lastServerSyncTimes`
  - 控制播放中心跳同步节流
- `_activePlaybackKeys`
  - 当前活跃播放中的项目集合
- `_optimisticSeekStates`
  - 处理 seek 后短时间内的乐观位置保护

对外提供给 UI 的历史列表是：

- `watchHistory`

它不是独立存储，而是运行时由 `_historyMap.values` 转成列表后按 `updatedAt` 倒序排序得到。

## 5. continueWatching 是怎么组装出来的

### 5.1 UserDataProvider 先输出 watchHistory

入口：

- [lib/providers/user_data_provider.dart:68](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:68)

逻辑：

- 把 `_historyMap.values` 转成列表
- 按 `updatedAt` 倒序

所以“继续播放”的原始顺序，来自这里的排序结果。

### 5.2 MediaWithUserDataProvider 再输出 continueWatching

入口：

- [lib/providers/media_with_user_data_provider.dart:82](/Users/yunlang/meowhub/meowhub/lib/providers/media_with_user_data_provider.dart:82)

组装过程：

1. 先把媒体库里的电影、剧集做 enriched
2. 建一个 `itemLookup`
3. 遍历 `UserDataProvider.watchHistory`
4. 每条历史调用 `_buildRecentItem()`
5. 如果历史是剧集，优先按 `seriesId` 找系列主条目
6. 如果能匹配媒体库，就把历史进度覆盖到媒体项上
7. 如果媒体库里找不到，就生成 fallback `MediaItem`
8. 用 `seenMediaKeys` 去重
9. 最终得到 `_cachedContinueWatching`

可以把它理解成：

```text
watchHistory（原始历史）
  -> 反查媒体库
  -> 用历史补齐进度/lastPlayedAt/封面等字段
  -> 归并为适合首页展示的 MediaItem
  -> continueWatching
```

### 5.3 为什么继续播放里既可能是电影，也可能是剧集

因为 `_buildRecentItem()` 有两条路径：

- 历史项带 `seriesId`
  - 优先把它折叠成“剧集所属的系列条目”
- 历史项不带 `seriesId`
  - 作为电影或单体媒体项展示

这也是为什么首页看到的“继续播放”更多像“还可以继续的作品”，而不完全等于“最近看的具体 episode 列表”。

## 6. UI 是怎么消费 continueWatching 的

### 6.1 首页

入口：

- [lib/ui/responsive/home_view.dart:36](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/home_view.dart:36)
- [lib/ui/mobile/home/mobile_home_screen.dart:113](/Users/yunlang/meowhub/meowhub/lib/ui/mobile/home/mobile_home_screen.dart:113)

逻辑：

- `HomeView` 通过 `context.watch<MediaWithUserDataProvider>()` 获取 `continueWatching`
- 将其传给首页货架组件
- 卡片内部再通过 `UserDataProvider.progressFractionForItem(mediaItem)` 获取进度条比例

所以首页展示的继续播放，不是直接绑定 `UserDataProvider.watchHistory`，而是绑定加工后的 `MediaWithUserDataProvider.continueWatching`。

### 6.2 详情页

入口：

- [lib/ui/responsive/media_detail_view.dart:52](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/media_detail_view.dart:52)

详情页不直接使用 `continueWatching` 列表，而是使用 `UserDataProvider` 的几个派生接口：

- `playbackProgressForItem(mediaItem)`
- `resumePlayableItemIdForItem(mediaItem)`
- `episodeIndexForItem(mediaItem)`

这三个值共同决定：

- 当前作品有没有续播点
- 默认应该落到哪一集
- 点击继续播放时应该选择哪个具体条目

### 6.3 播放页初始化

入口：

- [lib/ui/responsive/player_view.dart:155](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/player_view.dart:155)

播放器初始化时会：

1. 从 `UserDataProvider.playbackProgressForItem(widget.mediaItem)` 读取已保存的进度
2. 把它作为 `_initialPosition`
3. 后续基于这个位置准备播放方案

所以“继续播放”不只是首页用，它也是播放器初始续播点的数据来源。

## 7. 更新路径总览

继续播放的更新不是单点，而是发生在多个时机。

完整路径可以分成四类：

1. 播放前的内存标记
2. 播放中的内存进度更新
3. 播放中的服务器心跳同步
4. 退出播放器时的最终停止同步与重载

## 8. 播放前：先做内存标记

入口：

- [lib/ui/responsive/media_detail_view.dart:102](/Users/yunlang/meowhub/meowhub/lib/ui/responsive/media_detail_view.dart:102)
- [lib/providers/user_data_provider.dart:347](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:347)

当用户在详情页点击播放时，逻辑是：

```text
详情页点击播放
  -> markContinueWatchingItemMemoryOnly()
    -> updateProgressMemoryOnly()
      -> _upsertWatchHistory()
        -> _historyMap 写入
        -> _registerRecentProgress()
        -> notifyListeners()
```

这个阶段的特点：

- 只更新内存
- 不做远端 IO
- 目的主要是让 UI 立刻感知“最近播放对象”发生变化

## 9. 播放中：本地进度更新

入口：

- [lib/providers/user_data_provider.dart:405](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:405)

播放过程中，播放器会持续把当前位置回传给：

- `updatePlaybackProgressForItem()`

这条路径会：

1. 从 `MediaItem` 构建 `WatchHistoryItem`
2. 进入 `updateProgressMemoryOnly()`
3. 通过 `_upsertWatchHistory()` 更新 `_historyMap`
4. 根据 `notify` 决定要不要刷新 UI

这条链路只关心内存态，让界面上的进度可以即时变化。

## 10. 播放中：同步到服务器

入口：

- [lib/providers/user_data_provider.dart:443](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:443)

方法：

- `syncProgressToServerForItem()`

它的逻辑是：

1. 先更新本地内存 `_upsertWatchHistory()`
2. 读取 `_lastServerSyncTimes`
3. 做 15 秒节流
4. 节流通过后调用 `WatchHistoryRepository.updateProgress()`
5. Repository 同时更新本地 local history 与远端 Emby progress

对应仓库层调用：

- [lib/data/repositories/watch_history_repository_impl.dart:91](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart:91)

也就是说，播放中心跳同步的真正落点是“双写”：

- 写本地缓存
- 写远端服务

## 11. 播放开始与播放停止

### 11.1 开始播放

入口：

- [lib/providers/user_data_provider.dart:471](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:471)

`startPlaybackForItem()` 会：

1. 标记 `_activePlaybackKeys`
2. 先把最新位置写进 `_historyMap`
3. `notifyListeners()`
4. 调用 `WatchHistoryRepository.startPlayback()`

对应仓库落点：

- [lib/data/repositories/watch_history_repository_impl.dart:67](/Users/yunlang/meowhub/meowhub/lib/data/repositories/watch_history_repository_impl.dart:67)

### 11.2 停止播放

入口：

- [lib/providers/user_data_provider.dart:563](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:563)

`stopPlaybackForItem()` 会：

1. 用退出时的最终位置构建最新历史项
2. 更新 `_historyMap`
3. `notifyListeners()`
4. 调用 `WatchHistoryRepository.stopPlayback()`
5. 清理 active playback 状态
6. 重新执行 `_loadWatchHistory()`

这个“停止后重载”很关键，因为它会用仓库最新返回的历史结果重新覆盖当前源的历史状态。

## 12. 退出播放器时的真实链路

### 12.1 手机端

入口：

- [lib/ui/mobile/player/mobile_player_screen.dart:497](/Users/yunlang/meowhub/meowhub/lib/ui/mobile/player/mobile_player_screen.dart:497)

链路：

```text
退出播放器
  -> 捕获最后一个稳定进度 snapshot
  -> _applyLocalProgressOnExit()
    -> UserDataProvider.updatePlaybackProgressForItem()
  -> UserDataProvider.stopPlaybackForItem()
    -> Repository.stopPlayback()
    -> _loadWatchHistory()
```

### 12.2 平板端

入口：

- [lib/ui/tablet/player/tablet_player_screen.dart:275](/Users/yunlang/meowhub/meowhub/lib/ui/tablet/player/tablet_player_screen.dart:275)

链路和手机端一致，只是封装细节不同。

## 13. 定时后台刷新

`UserDataProvider` 在初始化时会启动 `_serverWatchHistorySyncTimer`。

入口：

- [lib/providers/user_data_provider.dart:717](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:717)

行为：

- 每 15 秒触发一次 `_syncWatchHistoryFromServerInBackground()`
- 如果当前存在活跃播放 `_activePlaybackKeys`，跳过
- 否则调用 `_loadWatchHistory(rethrowOnError: false)`

这个机制的意义是：

- 非播放状态下，继续播放可以定时向服务端靠拢
- 播放进行中，则优先相信当前内存态，避免被后台刷新打断

## 14. 系列续播的派生信息是怎么来的

除了列表本身，继续播放还会生成两套给详情页使用的派生状态：

- `_recentEpisodeIndices`
- `_recentPlayableItemIds`

入口：

- [lib/providers/user_data_provider.dart:1051](/Users/yunlang/meowhub/meowhub/lib/providers/user_data_provider.dart:1051)

生成方式：

1. 每次 `_historyMap` 更新后，调用 `_registerRecentProgress()`
2. 如果历史项带 `seriesId`
3. 把 `seriesId -> 最近播放的具体 item.id`
4. 把 `seriesId -> 最近 episode index`

详情页随后会用：

- `resumePlayableItemIdForItem()`
- `episodeIndexForItem()`

来决定“继续播放”的默认目标。

## 15. 用一句话串起完整路径

可以把当前实现浓缩成下面这条总线：

```text
当前服务器环境由 AppProvider 决定
  -> UserDataProvider 通过 WatchHistoryRepository 拉取和维护 watchHistory
  -> MediaWithUserDataProvider 把 watchHistory 与媒体库拼成 continueWatching
  -> 首页展示 continueWatching
  -> 详情页和播放器读取 playbackProgress / resume item / episode index
  -> 播放前、播放中、停止播放时再反向更新 UserDataProvider 和 Repository
```

## 16. 调试时建议优先看的点

如果后面需要排查“继续播放为什么不对”，建议优先看这几个位置：

- `UserDataProvider._loadWatchHistory()`
  - 看历史是不是已经正确进了 `_historyMap`
- `UserDataProvider.watchHistory`
  - 看排序结果是否符合预期
- `MediaWithUserDataProvider._updateCache()`
  - 看 `watchHistory -> continueWatching` 的映射是否正确
- `media_detail_view.dart`
  - 看系列详情页拿到的 `resumePlayableItemId` 和 `episodeIndex`
- `mobile_player_screen.dart` / `tablet_player_screen.dart`
  - 看退出播放时是否把最终位置同步回去了

## 17. 当前职责边界总结

最后再用职责边界收口一次：

- `AppProvider`
  - 负责当前媒体服务环境，不负责继续播放数据本身
- `WatchHistoryRepository`
  - 负责历史读取和持久化同步
- `UserDataProvider`
  - 负责继续播放原始状态、播放进度状态、系列续播派生状态
- `MediaWithUserDataProvider`
  - 负责把历史转换成首页与列表真正消费的展示数据
- `HomeView / MediaDetailView / PlayerView`
  - 负责消费这些状态，不负责历史计算

如果后续要继续整理，可以在本文基础上再拆两篇：

- 一篇只讲“播放进度同步协议”
- 一篇只讲“系列续播定位规则”
