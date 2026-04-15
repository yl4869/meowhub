# meowhub

MeowHub 是一个基于 Flutter 的媒体浏览与播放项目，当前已集成 Emby 数据读取、媒体详情页、最近观看记录以及播放器能力。

## 环境要求

- Flutter 3.x
- Dart 3.x
- Android Studio / VS Code（二选一即可）
- 可访问的 Emby 服务器账号

## 获取项目

```bash
git clone git@github.com:yl4869/meowhub.git
cd meowhub
flutter pub get
```

## 运行项目

```bash
flutter run
```

如果需要指定设备，可以先执行：

```bash
flutter devices
```

然后使用：

```bash
flutter run -d <device-id>
```

## 首次使用

应用启动后，在项目内填写 Emby 服务器地址、用户名和密码进行连接。账号信息保存在本地安全存储中，不包含在仓库里，所以换一台电脑 clone 后需要重新登录一次。

## 常用命令

```bash
flutter analyze
flutter test
```
