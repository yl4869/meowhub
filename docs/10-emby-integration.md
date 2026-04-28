# 10 - Emby 集成

## 概述

MeowHub 支持 Emby 和 Jellyfin（API 兼容）作为后端媒体服务器。所有 Emby 协议交互集中在 `EmbyApiClient` 中。

## 连接配置

`MediaServiceConfig` 定义连接参数：

| 字段 | 说明 |
|------|------|
| `type` | `MediaServiceType.emby` 或 `MediaServiceType.jellyfin` |
| `serverUrl` | 服务器地址（如 `http://192.168.1.100:8096`） |
| `username` | 用户名 |
| `password` | 密码 |
| `deviceId` | 自动生成的设备标识 |

token 和 userId 由认证后自动管理，不存储在配置中。

## 认证流程

```
EmbyApiClient.authenticate()
  │
  ▼
POST /emby/Users/AuthenticateByName
  Headers: X-Emby-Authorization (Client/Device/Version)
  Body: { Username, Pw }
  │
  ▼
EmbyAuthResponse
  ├── AccessToken → SecurityService.writeAccessToken()
  ├── User.Id → SecurityService.writeUserId()
  └── SessionInfo → 用于后续请求
```

后续所有请求通过 `EmbyAuthInterceptor` 自动附加：
- `X-Emby-Token: {accessToken}`
- `X-Emby-Device-Id: {deviceId}`
- `X-Emby-Authorization: MediaBrowser Client="MeowHub", ...`

## 关键 API 映射

### 媒体浏览
| 操作 | HTTP 端点 |
|------|-----------|
| 获取媒体库列表 | `GET /Library/VirtualFolders` |
| 获取媒体项列表 | `GET /Items?IncludeItemTypes=...&SortBy=...&SortOrder=...` |
| 获取电影 | `GET /Items?IncludeItemTypes=Movie` |
| 获取剧集 | `GET /Items?IncludeItemTypes=Series` |
| 获取媒体详情 | `GET /Users/{userId}/Items/{itemId}` |
| 获取剧集列表 | `GET /Shows/{seriesId}/Episodes` |
| 获取季列表 | `GET /Shows/{seriesId}/Seasons` |
| 获取继续观看 | `GET /Items/Resume?Limit={limit}` |

### 搜索
| 操作 | HTTP 端点 |
|------|-----------|
| 搜索提示 | `GET /Search/Hints?SearchTerm={query}` |

### 播放
| 操作 | HTTP 端点 |
|------|-----------|
| 获取播放信息 | `POST /Items/{itemId}/PlaybackInfo` |
| 播放开始 | `POST /Sessions/Playing` |
| 播放进度 | `POST /Sessions/Playing/Progress` |
| 播放停止 | `POST /Sessions/Playing/Stopped` |
| 视频流 | `GET /Videos/{itemId}/stream?Static=true` |
| 字幕流 | `GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/...` |
| VTT 字幕 | `GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/...` |

### 系统
| 操作 | HTTP 端点 |
|------|-----------|
| 系统信息 | `GET /System/Info` |
| 公开系统信息 | `GET /System/Info/Public` |

## 设备配置 (DeviceProfile)

`EmbyDeviceProfile` 描述客户端能力，影响 Emby 的转码决策。

`EmbyProfileFactory.forCurrentPlatform()` 根据 `CapabilitySnapshot` 生成：

**编码支持**:
- 视频: H264, HEVC, VP9, AV1
- 音频: AAC, MP3, FLAC, AC3, EAC3, Opus

**DirectPlay 条件**: 容器为 mp4/mkv/webm，编码在支持列表中

**转码条件**: 当源高于设备最大分辨率或码率时触发

**图像字幕处理**: PGS, DVDSub 等不支持 → 服务端烧录

## ticks 单位

Emby 使用 100 纳秒的 ticks 作为时间单位。

转换函数:
```dart
int durationToEmbyTicks(Duration d);   // Duration → ticks (÷ 1000 纳秒)
Duration embyTicksToDuration(int t);    // ticks → Duration
```

## 图片 URL 构建

`EmbyMediaItemDtoMapper` 构建图片 URL 规则：

```
{serverUrl}/emby/Items/{itemId}/Images/Primary?maxHeight=360&tag={imageTag}&api_key={token}
```

支持的图片类型: Primary, Thumb, Backdrop, Logo

## 播放 URL 构建

### DirectPlay
```
{serverUrl}/emby/Videos/{itemId}/stream?Static=true&MediaSourceId={id}&api_key={token}&UserId={userId}&PlaySessionId={sid}
```

### 转码
使用 `PlaybackInfo` 返回的 `TranscodingUrl`，附加相同的认证和会话参数。

## Jellyfin 兼容性

Jellyfin API 与 Emby 高度兼容，共享同一套 `EmbyApiClient` 实现。区别仅在于：
- 认证请求的参数名略有差异（`Pw` vs `Password`）
- Server URL 路径可能不同

## 安全存储

认证信息（Token, UserId, Password）通过 `SecurityService` 存储：
- 原生平台: `flutter_secure_storage` (Keychain/Keystore)
- Web 平台: `SharedPreferences`（降级方案）

存储支持 namespace 隔离（按 `credentialNamespace = "{serverUrl}:{username}"` 分隔），切换服务器不会混淆凭据。

## HTTP 拦截器

`EmbyAuthInterceptor` (Dio `QueuedInterceptor`):
- `onRequest`: 附加 `X-Emby-Authorization`, `X-Emby-Device-Id`, `X-Emby-Token`
- `onError`: 捕获 401，清除 SecurityService，触发 `SessionExpiredNotifier`
