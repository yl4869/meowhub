# 07 - 播放系统

## 概述

播放系统是项目最复杂的子系统，负责从"用户点击播放"到"视频开始播放"再到"播放状态持续上报"的完整链路。

## 核心参与组件

| 组件 | 文件 | 职责 |
|------|------|------|
| `PlayerView` | `ui/responsive/player_view.dart` | 播放会话协调器 |
| `GetPlaybackPlanUseCase` | `domain/usecases/get_playback_plan.dart` | 获取播放方案 |
| `PlaybackRepository` | `domain/repositories/playback_repository.dart` | 播放方案抽象 |
| `EmbyPlaybackRepositoryImpl` | `data/repositories/emby_playback_repository_impl.dart` | 播放方案实现 |
| `EmbyApiClient` | `data/datasources/emby_api_client.dart` | Emby HTTP API |
| `MeowVideoPlayer` | `ui/atoms/meow_video_player.dart` | 视频播放器组件 |
| `MobilePlayerScreen` | `ui/mobile/player/mobile_player_screen.dart` | 移动端播放 UI |
| `TabletPlayerScreen` | `ui/tablet/player/tablet_player_screen.dart` | 平板端播放 UI |

## 播放链路总览

```
详情页点击播放
    │
    ▼
PlayerView._preparePlaybackPlan()
    │
    ▼
GetPlaybackPlanUseCase(PlaybackRepository)
    │
    ▼
EmbyPlaybackRepositoryImpl.getPlaybackPlan()
    │
    ├──▶ EmbyApiClient.getPlaybackInfo()
    │       POST /Items/{id}/PlaybackInfo
    │       请求体: UserId, DeviceId, DeviceProfile, MaxStreamingBitrate,
    │              AudioStreamIndex, SubtitleStreamIndex, PlaySessionId
    │
    ├──▶ _pickBestSource()
    │       优先 DirectPlay → DirectStream → Transcode
    │
    ├──▶ _resolvePlaybackAccess()
    │       构建带认证参数的播放 URL
    │
    ├──▶ 映射音轨、字幕、章节、片头尾标记
    │
    └──▶ 返回 PlaybackPlan
            │
            ▼
      PlayerView → MobilePlayerScreen / TabletPlayerScreen
            │
            ▼
      MeowVideoPlayer (media_kit)
```

## PlaybackPlan

Domain 实体，完成播放所需全部信息：

| 字段 | 类型 | 说明 |
|------|------|------|
| `url` | `String` | 最终播放地址（含认证参数） |
| `isTranscoding` | `bool` | 是否服务端转码 |
| `playSessionId` | `String?` | Emby 播放会话 ID（上报必需） |
| `mediaSourceId` | `String?` | 媒体源 ID |
| `audioStreams` | `List<PlaybackStream>` | 可用音轨列表 |
| `subtitleStreams` | `List<PlaybackStream>` | 可用字幕列表 |
| `chapters` | `List<VideoChapter>` | 章节节点 |
| `markers` | `Map<String, DurationRange>` | 片头/片尾标记 |
| `videoInfo` | `PlaybackVideoInfo?` | 视频分辨率/编码信息 |

### PlaybackStream

单条音轨或字幕流：

| 字段 | 说明 |
|------|------|
| `index` | Emby 流索引 |
| `title` | 显示名称 |
| `language` | 语言 |
| `codec` | 编码格式 |
| `isExternal` | 是否外挂 |
| `isTextSubtitleStream` | 是否文本字幕 |
| `deliveryUrl` | 字幕分发 URL（非 null 时需客户端独立加载） |

## 媒体源选择策略

`_pickBestSource()` 按以下优先级选择：

1. **DirectPlay** — 客户端原生支持，无需服务端处理
2. **DirectStream** — 容器转换，编码不变
3. **Transcode** — 服务端重新编码

如果有指定 `audioStreamIndex` / `subtitleStreamIndex`，优先选择包含这些流的媒体源。

## URL 构建

`_resolvePlaybackAccess()` 构建最终播放 URL，途径：

1. **服务端推荐** — 使用 `PlaybackInfo` 返回的 `transcodingUrl`（转码场景）
2. **DirectStream URL** — 使用 `directStreamUrl`
3. **客户端直连** — 构建 `/Videos/{id}/stream?Static=true` URL

所有 URL 通过 `_buildAuthorizedUrl()` 附加：
- `api_key` (AccessToken)
- `UserId`
- `MediaSourceId`
- `PlaySessionId`
- `AudioStreamIndex` / `SubtitleStreamIndex`

## 字幕处理

### 字幕类型识别

| 条件 | 类型 | 处理方式 |
|------|------|----------|
| `isTextSubtitleStream == true` | 文本字幕 (SRT/ASS/VTT) | 客户端直接渲染 |
| `codec ∈ {pgs, pgssub, sup, dvdsub}` + 内嵌 | 图像字幕 (PGS 等) | 需要服务端烧录（转码） |
| `isExternal == true` | 外挂字幕 | 通过 `deliveryUrl` 独立加载 |
| `deliveryMethod == 'encode'` | 服务端编码字幕 | 通过 VTT 端点加载 |

### 字幕选择流程

1. `PlayerView._resolveSubtitleSelection()` — 优先用户保存的选择
2. 回退到 `PlaybackPlan` 中的默认字幕流
3. 图像内嵌字幕自动触发转码：`_needsTranscodingForSubtitles()` → `_preparePlaybackPlan(preferTranscoding: true)`

### 字幕 UI

通过 `_openTrackSelector()` 弹出 `ModalBottomSheet`，提供音轨和字幕选择：
- 每行显示 title + 详细信息（语言、编码、声道数、码率）
- "应用"后调用 `_applyTrackSelection()`，图像字幕会触发转码重新获取播放方案

## 播放计划缓存

`EmbyPlaybackRepositoryImpl` 内部有静态缓存：

- **TTL**: 12 秒
- **Key**: namespace + itemId + bitrate + audio/subtitle/preferTranscoding
- **去重**: 相同参数的并发请求返回同一个 Future

## 分辨率切换

PlayerView 暴露 4 档分辨率：Auto / 1080P / 720P / 480P

切换时调用 `_applyResolutionOption()`：
1. 保存当前播放位置
2. 用新的 `maxStreamingBitrate` 重新获取 `PlaybackPlan`
3. 通过 `_resumePositionOverride` 恢复位置

## MeowVideoPlayer

封装 `media_kit` 的视频播放组件。

**关键参数**:

| 参数 | 说明 |
|------|------|
| `url` | 播放地址 |
| `initialPosition` | 续播起始位置 |
| `subtitleUri` | 外挂字幕 URL |
| `subtitleTitle` / `subtitleLanguage` | 字幕元数据 |
| `disableSubtitleTrack` | 关闭字幕 |
| `audioStreamIndex` / `subtitleStreamIndex` | 流选择 |

**关键回调**:

| 回调 | 说明 |
|------|------|
| `onPlaybackStatusChanged` | 连续回传播放器状态（position/duration/buffering...） |
| `onPlaybackStarted` | 首次确认开始播放 |
| `onPlaybackError` | 播放错误 |

**状态模型 `MeowVideoPlaybackStatus`**: position, duration, isInitialized, isPlaying, isBuffering, isCompleted

## 播放错误处理

PlayerView 区分两类错误：

1. **播放方案获取失败** — `_planErrorMessage` 非空 + `_hasStrictPlaybackPlan == false`
   - 显示错误视图 + "重试"按钮
   - 重试调用 `_preparePlaybackPlan()`

2. **播放中错误** — `MobilePlayerScreen` / `TabletPlayerScreen` 处理
   - 提供 `onRetryWithTranscoding` 回调
   - 尝试关闭 DirectPlay 限制重新获取方案

## 播放会话上报

播放过程中的三个上报时机，由 `UserDataProvider` 协调：

1. **开始播放** → `startPlaybackForItem()` → `WatchHistoryRepository.startPlayback()` → `POST /Sessions/Playing`
2. **播放中** → `syncProgressToServerForItem()` (15秒节流) → `POST /Sessions/Playing/Progress`
3. **停止播放** → `stopPlaybackForItem()` → `WatchHistoryRepository.stopPlayback()` → `POST /Sessions/Playing/Stopped`

详细见 [08-观看历史](08-watch-history.md)。

## 设计要点

1. **PlaybackPlan 和 WatchHistory 的协同**：`playSessionId` 是两者的关键纽带
2. **内嵌图像字幕的自动转码**：PlayerView 检测到 PGS 字幕且当前为 DirectPlay 时，自动重新请求转码方案
3. **音轨/字幕选择持久化**：用户选择通过 `UserDataProvider.setTrackSelectionForItem()` 保存到 SharedPreferences
4. **播放位置恢复**：`_resumePositionOverride` 在切换分辨率/转码时保持用户位置
