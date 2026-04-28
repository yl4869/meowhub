# 09 - 响应式布局

## 概述

MeowHub 通过 `ResponsiveLayoutBuilder` 实现移动端和平板端的自适应。每个页面有两套实现（mobile / tablet），由响应式构建器在运行时选择。

## 核心组件

### ResponsiveLayoutBuilder

**文件**: `lib/ui/responsive/responsive_layout_builder.dart`

核心 Widget，接受两个 builder：

```dart
ResponsiveLayoutBuilder(
  mobileBuilder: (context, maxWidth) => MobileHomeScreen(...),
  tabletBuilder: (context, maxWidth) => TabletHomeScreen(...),
)
```

**工作原理**:
- 使用 `LayoutBuilder` 获取当前可用宽度
- 断点: **720px**（`AppResponsiveBreakpoints.tablet`）
- `shortestSide >= 720` → tablet，否则 → mobile
- 使用 `KeyedSubtree` 包裹，确保只有匹配的子树被创建

### ResponsiveLayoutContext

```dart
class ResponsiveLayoutContext {
  final double maxWidth;
  final ResponsiveLayoutType layoutType;  // mobile / tablet
  bool get isTablet => layoutType == ResponsiveLayoutType.tablet;
  bool get isMobile => layoutType == ResponsiveLayoutType.mobile;
}
```

## 移动端布局

所有移动端页面位于 `lib/ui/mobile/`，主要使用 `CustomScrollView` + `Sliver`。

### MobileHomeScreen

- 顶部: 服务器切换器 + 刷新/搜索按钮
- "继续观看"横幅: 水平滑动的 PosterCard 列表
- "最近添加"区域
- 各媒体库的 PosterCard 网格（2-3 列）
- 下拉刷新支持
- Loading / Error / 无服务器 三种空状态

### MobileMediaDetailScreen

- 背景 backdrop 图
- 元数据区域（标题、评分、年份、时长）
- 剧集选择 Chips（横向滚动）
- 播放按钮 + 收藏按钮
- 演员列表
- 可展开简介
- 轨道选择器入口

### MobilePlayerScreen

- 全屏视频播放
- 进度条（`audio_video_progress_bar`）
- 播放/暂停控制
- 分辨率选择
- 音轨/字幕选择入口
- 播放错误覆盖层

## 平板端布局

所有平板端页面位于 `lib/ui/tablet/`，采用双面板布局。

### TabletHomeScreen

- 左侧面板（300-340px 固定宽度）:
  - Logo + 应用名
  - 搜索输入
  - 当前服务器信息
  - 统计数字
  - 特色内容预览
- 右侧内容区:
  - "继续观看"网格（3-5 列）
  - "最近添加"网格
  - 各媒体库内容

### TabletMediaDetailScreen

- 更大的 backdrop
- 详情信息布局更宽松
- 剧集列表可使用网格展示

### TabletPlayerScreen

- 视频播放器
- 右侧信息面板（可选）
- 与移动端相同的核心播放控制

## 响应式页面入口

每个路由对应的入口视图位于 `lib/ui/responsive/`：

| 入口视图 | 路由 | Mobile 实现 | Tablet 实现 |
|----------|------|------------|-------------|
| `HomeView` | `/` | `MobileHomeScreen` | `TabletHomeScreen` |
| `MediaDetailView` | `/media/:id` | `MobileMediaDetailScreen` | `TabletMediaDetailScreen` |
| `PlayerView` | `/player/:id` | `MobilePlayerScreen` | `TabletPlayerScreen` |

入口视图负责：
- 路由参数解析
- 数据获取（FutureBuilder / Provider）
- 回调协调（播放、收藏、导航）
- 通过 `ResponsiveLayoutBuilder` 分支

## 布局参数传递

Tablet 页面通常接收 `maxWidth` 参数以计算网格列数：

```dart
tabletBuilder: (context, maxWidth) {
  return TabletHomeScreen(maxWidth: maxWidth, ...);
}
```

## 设备预览

开发时自动在桌面/Web 平台启用 `device_preview`，可以模拟移动端和平板端效果。

配置常量 `DEVICE_PREVIEW`:
- `auto`（默认）: 桌面/Web 自动开启
- `true`: 强制开启
- `false` / Release 模式: 关闭

## 适配策略

1. **断点单一**: 只有 720px 一个断点，简单明确
2. **组件分离**: mobile/tablet 各自独立 Widget，不共享状态逻辑
3. **入口统一**: 响应式入口处理共享逻辑（数据获取、回调），分支只负责布局
4. **KeyedSubtree**: 确保未激活的分支不会构建，节省性能
