# MeowHub 技术文档

## 文档索引

### 快速开始
- [01-快速开始](01-getting-started.md) — 环境搭建、运行、构建

### 架构与设计
- [02-架构总览](02-architecture.md) — 分层架构、目录结构、设计模式、核心概念
- [03-依赖注入](03-dependency-injection.md) — Provider 装配图、ProxyProvider 链路、组合根
- [04-状态管理](04-state-management.md) — 所有 Provider 的职责、状态结构、更新策略

### 数据与路由
- [05-数据层](05-data-layer.md) — Repository、DataSource、DTO、API Client、映射器
- [06-路由系统](06-routing.md) — GoRouter 配置、路由表、守卫、参数传递

### 核心子系统
- [07-播放系统](07-playback-system.md) — PlaybackPlan、视频播放器、字幕处理、转码
- [08-观看历史](08-watch-history.md) — 历史同步、继续播放组装、本地/远端合并、心跳上报

### 平台与集成
- [09-响应式布局](09-responsive-layout.md) — ResponsiveLayoutBuilder、断点、移动端/平板端
- [10-Emby集成](10-emby-integration.md) — Emby API 客户端、认证、设备配置、协议细节

### 扩展
- [11-扩展指南](11-extending.md) — 添加新媒体服务、新 Provider、新功能

---

## 阅读路径建议

**首次接触项目：**
1. 先读 [架构总览](02-architecture.md) 了解整体结构
2. 再读 [依赖注入](03-dependency-injection.md) 理解组件装配方式
3. 然后读 [状态管理](04-state-management.md) 掌握数据流

**调试播放相关功能：**
1. [播放系统](07-playback-system.md)
2. [观看历史](08-watch-history.md)

**添加新媒体服务（如 Plex）：**
1. [扩展指南](11-extending.md)
2. [Emby 集成](10-emby-integration.md)（参考现有实现）
3. [数据层](05-data-layer.md)
