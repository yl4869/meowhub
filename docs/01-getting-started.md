# 01 - 快速开始

## 环境要求

- Flutter SDK >= 3.11.4
- Dart >= 3.11.4
- Android Studio / VS Code
- 可访问的 Emby 或 Jellyfin 服务器

## 获取项目

```bash
git clone git@github.com:yl4869/meowhub.git
cd meowhub
flutter pub get
```

## 运行

```bash
# 默认设备
flutter run

# 指定设备
flutter devices          # 列出可用设备
flutter run -d <device-id>
```

## 首次使用

1. 启动应用后进入登录页
2. 填写服务器地址（如 `http://192.168.1.100:8096`）
3. 选择服务类型（Emby / Jellyfin）
4. 输入用户名和密码
5. 点击连接验证，成功后自动跳转首页

账号信息保存在本地安全存储中，不会随代码提交。

## 常用命令

```bash
flutter pub get          # 安装依赖
flutter run              # 运行应用
flutter analyze          # 静态分析
flutter test             # 运行测试
flutter test test/widget_test.dart  # 运行单个测试
flutter build apk        # Android
flutter build ios        # iOS
flutter build web        # Web
flutter build macos      # macOS
```

## 编译常量

通过 `--dart-define` 控制运行时行为：

```bash
# 使用 Mock 数据（无需服务器）
flutter run --dart-define=USE_MOCK_REPOSITORY=true

# 禁用设备预览
flutter run --dart-define=DEVICE_PREVIEW=false

# 强制开启设备预览
flutter run --dart-define=DEVICE_PREVIEW=true
```

| 常量 | 默认值 | 说明 |
|------|--------|------|
| `USE_MOCK_REPOSITORY` | `false` | 使用内置 Mock 数据，适合 UI 开发 |
| `DEVICE_PREVIEW` | `auto` | 桌面/Web 自动开启，移动端关闭 |

## 代码生成

项目使用 `json_serializable` 生成 JSON 序列化代码。修改 DTO 后需重新生成：

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 项目结构速览

```
lib/
  main.dart              # 入口 + 依赖装配
  domain/                # 实体、抽象接口、用例
    entities/            # MediaItem, PlaybackPlan, WatchHistoryItem 等
    repositories/        # IMediaRepository, PlaybackRepository 等接口
    usecases/            # 用例（薄包装，组合仓库调用）
  data/                  # 接口实现
    datasources/          # EmbyApiClient, 本地/远端数据源
    models/               # DTO (emby/ 子目录), PlaybackRecord
    repositories/         # Repository 实现 + 工厂
    network/              # Dio 拦截器
  providers/             # ChangeNotifier 状态管理
  ui/
    atoms/               # 基础组件（PosterCard, MeowVideoPlayer 等）
    responsive/          # 路由入口视图（HomeView, PlayerView 等）
    mobile/              # 移动端页面
    tablet/              # 平板端页面
    screens/             # 独立页面（搜索、配置）
    file_source/         # 文件源管理组件
  core/                  # 基础设施（安全存储、能力探测、ticks 工具）
  theme/                 # 主题配置
```
