# 08 - 观看历史

## 概述

观看历史系统负责"继续播放"数据的获取、更新、组装和消费。它涉及 3 个 Provider、2 个 Repository、2 个 DataSource。

## 职责边界

```
AppProvider
  → 决定"当前连接哪个媒体服务"
  → 不保存历史数据

UserDataProvider
  → 观看历史的"唯一数据源"（内存中）
  → 管理播放进度、收藏、track selection
  → 协调同步策略

MediaWithUserDataProvider
  → 把历史与媒体库组装成 UI 直接消费的 continueWatching 列表
  → 为媒体列表补上收藏/进度状态
```

## 数据结构

### 内存主存储

`UserDataProvider._historyMap`: `Map<String, WatchHistoryItem>`

- Key: `"${sourceType.name}:${id}"` — 如 `"emby:12345"`
- 所有查询 O(1)，不需要遍历

### WatchHistoryItem 关键字段

| 字段 | 说明 |
|------|------|
| `id` | 媒体 ID |
| `sourceType` | `emby` / `local` |
| `position` | 已播放时长 |
| `duration` | 总时长 |
| `updatedAt` | 最后更新时间（用于排序） |
| `seriesId` | 系列 ID（剧集时有值） |
| `indexNumber` | 集编号 |
| `parentIndexNumber` | 季编号 |

### 派生状态

每次 `_historyMap` 变更时重建：

- `_recentEpisodeIndices` — `seriesId → 最近播放的集索引`
- `_recentPlayableItemIds` — `seriesId → 最近播放的具体 item.id`

详情页用这两个数据决定"继续播放默认选中哪一集"。

## 数据来源

### 远端来源
`EmbyWatchHistoryRemoteDataSource.getHistory()` → `EmbyApiClient.getContinueWatching()`

对应 API: `GET /Items/Resume`，返回 `List<EmbyResumeItemDto>`

### 本地来源
`LocalWatchHistoryDataSource.getHistory()` → 从 `SharedPreferences` 读取 JSON 序列化的 `PlaybackRecord` 列表

### 合并策略
`WatchHistoryRepositoryImpl` 将两种来源合并：
- 远端 Emby 历史 + 本地历史
- 合并后按源写入 `_historyMap`
- 本地数据使 UI 在无网络时仍然可用

## 初始化流程

```
UserDataProvider 构造
  │
  ├──▶ 订阅 mediaServiceManager.configStream
  │
  ├──▶ _restartServerWatchHistorySync()
  │       启动 15s 定时器
  │
  └──▶ _loadWatchHistory()
          │
          ▼
    WatchHistoryRepository.getHistoryBySource(emby)
          │
          ▼
    _replaceWatchHistoryItemsForSource(emby, items)
          │
          ▼
    _historyMap 写入 → _rebuildDerivedProgressState() → notifyListeners()
```

## ContinueWatching 组装

`MediaWithUserDataProvider` 在 `_updateCache()` 中组装 continueWatching：

1. 从 `MediaLibraryProvider` 获取所有媒体项
2. 建立 `itemLookup`（按 mediaKey 索引）
3. 遍历 `UserDataProvider.watchHistory`（按 updatedAt 倒序）
4. 每条历史尝试反查媒体库：
   - 有 `seriesId` → 折叠为系列主条目（而不是具体 episode）
   - 无 `seriesId` → 作为电影展示
5. 用 `seenMediaKeys` 去重
6. 用媒体项自身的海报、标题覆盖历史中的占位信息

```
watchHistory (原始历史)
  → 反查媒体库
  → 用历史补齐进度/封面对应的 MediaItem
  → 归并删除重复项
  → continueWatching (首页展示)
```

## 播放中的进度更新

### 三层更新策略

| 层次 | 频率 | 目的 |
|------|------|------|
| 内存更新 | 实时（每次 position 变化） | UI 进度条即时响应 |
| 心跳同步 | 每 15 秒 | 服务器持久化 |
| 后台刷新 | 每 15 秒 | 同步其他设备的进度 |

### 内存更新

`updatePlaybackProgressForItem()` → `updateProgressMemoryOnly()` → `_upsertWatchHistory()`

- 只改 `_historyMap`
- `notify: false`（避免频繁重绘）
- 位置合并：取 max(existing.position, incoming.position)

### 心跳同步

`syncProgressToServerForItem()`:
1. 先 `_upsertWatchHistory()`（内存）
2. 检查 `_lastServerSyncTimes`，15 秒内跳过
3. 发送 `drainPendingSyncItems()`（处理之前的失败队列）
4. 调用 `WatchHistoryRepository.updateProgress()` → `POST /Sessions/Playing/Progress`

### 离线队列

网络失败时进度项入队 `_pendingSyncItems`：
- 下次心跳时优先发送
- 最多重试 3 次
- 同一 uniqueKey 只保留最新一条

## 播放生命周期

### 1. 播放前（详情页）

```dart
markContinueWatchingItemMemoryOnly(mediaItem)
  → updateProgressMemoryOnly()  // 仅内存，无 IO
  → notifyListeners()            // UI 立即显示
```

目的：在进入播放器前预先更新"最近观看"位置，避免 UI 断层。

### 2. 开始播放

```dart
startPlaybackForItem(mediaItem, position, playSessionId, ...)
  → _setPlaybackActive(mediaItem, active: true)
  → _upsertWatchHistory()        // 内存更新
  → notifyListeners()
  → WatchHistoryRepository.startPlayback()  // POST /Sessions/Playing
```

### 3. 播放中

播放器持续回传 position → `updatePlaybackProgressForItem()`（内存）+
`syncProgressToServerForItem()`（15s 心跳）

### 4. 停止播放

```dart
stopPlaybackForItem(mediaItem, position, playSessionId, ...)
  → _upsertWatchHistory()        // 最终位置
  → notifyListeners()
  → WatchHistoryRepository.stopPlayback()   // POST /Sessions/Playing/Stopped
  → _setPlaybackActive(mediaItem, active: false)
  → _loadWatchHistory()          // 刷新（拉取服务端最终状态）
```

## Optimistic Seek

用户手动 seek 后，短时间内从播放器回传的 position 可能不准确（播放器尚未完成 seek）。

保护机制：
1. 用户 seek → `registerOptimisticSeekForItem()` → 写入 `_optimisticSeekStates`
2. 8 秒内的进度更新 → `_resolveOptimisticSeekConflict()` 判断是否和 seek 目标一致
3. 一致 → 接受；不一致且超出容差（前 900ms / 后 4s）→ 保持 seek 位置

## 服务器切换

当检测到 `configStream` 更新且 credentialNamespace 变化时：

```dart
updateDependencies(manager, watchHistoryRepository)
  → 清空 _historyMap, _favoriteItems, _trackSelections
  → _resetForServerChange()
    → clearCachedHistory(emby)
    → _loadWatchHistory()  // 从新服务器加载
```

## 调试检查点

- `_historyMap` 是否包含预期数据（`UserDataProvider._loadWatchHistory()`）
- `watchHistory` getter 排序是否正确
- `MediaWithUserDataProvider._updateCache()` 中映射是否正确
- `resumePlayableItemId` / `episodeIndex` 在详情页是否正确
- `mobile_player_screen.dart` / `tablet_player_screen.dart` 退出时是否同步最终位置
