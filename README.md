# MeowHub

基于 Flutter 的媒体中心客户端，支持连接 Emby / Jellyfin 服务器，提供媒体浏览、详情查看、视频播放及观看进度同步。

## 文档

详细的技术文档位于 [`docs/`](docs/) 目录：

| 文档 | 说明 |
|------|------|
| [快速开始](docs/01-getting-started.md) | 环境搭建与运行 |
| [架构总览](docs/02-architecture.md) | 分层设计与目录结构 |
| [依赖注入](docs/03-dependency-injection.md) | Provider 装配图 |
| [状态管理](docs/04-state-management.md) | 所有 Provider 详解 |
| [数据层](docs/05-data-layer.md) | Repository / DataSource / DTO |
| [路由系统](docs/06-routing.md) | GoRouter 配置与导航 |
| [播放系统](docs/07-playback-system.md) | PlaybackPlan 与视频播放 |
| [观看历史](docs/08-watch-history.md) | 历史同步与继续播放 |
| [响应式布局](docs/09-responsive-layout.md) | Mobile / Tablet 适配 |
| [Emby 集成](docs/10-emby-integration.md) | Emby API 与认证 |
| [扩展指南](docs/11-extending.md) | 添加新媒体服务 |

## 环境要求

- Flutter SDK >= 3.11.4
- Dart >= 3.11.4

## 快速开始

```bash
git clone git@github.com:yl4869/meowhub.git
cd meowhub
flutter pub get
flutter run
```

首次启动后填写服务器地址、用户名和密码即可连接。

Mock 数据模式（无需服务器）：
```bash
flutter run --dart-define=USE_MOCK_REPOSITORY=true
```

## 常用命令

```bash
flutter pub get       # 安装依赖
flutter run           # 运行应用
flutter analyze       # 静态分析
flutter test          # 运行测试
flutter build apk     # Android 构建
flutter build ios     # iOS 构建
```
