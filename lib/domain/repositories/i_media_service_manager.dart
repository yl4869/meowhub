// lib/domain/repositories/i_media_service_manager.dart
import '../entities/media_service_config.dart';

/// 媒体服务配置验证器的函数签名，用于解耦校验逻辑
typedef MediaConfigValidator = Future<bool> Function(MediaServiceConfig config);

abstract class IMediaServiceManager {
  Future<void> initialize();
  MediaServiceConfig? getSavedConfig();
  Future<void> setConfig(MediaServiceConfig config);

  // 🚀 使用 Dart 原生的 Stream，而不是 ChangeNotifier
  // 任何感兴趣的人都可以订阅这个“流”，看看配置有没有变
  Stream<MediaServiceConfig?> get configStream;

  Future<void> clearConfig();

  /// 校验配置：不再内部构建 ApiClient，而是接受一个外部验证器
  Future<bool> verifyConfig(
    MediaServiceConfig config, {
    required MediaConfigValidator validator,
  });
}
