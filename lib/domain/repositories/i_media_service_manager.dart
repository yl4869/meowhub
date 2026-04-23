// lib/domain/repositories/i_media_service_manager.dart
import '../entities/media_service_config.dart';

/// 媒体服务配置验证器的函数签名，用于解耦校验逻辑
typedef MediaConfigValidator = Future<bool> Function(MediaServiceConfig config);

abstract class IMediaServiceManager {
  Future<void> initialize();
  MediaServiceConfig? getSavedConfig();
  Future<void> setConfig(MediaServiceConfig config);
  Future<void> clearConfig();
  
  /// 校验配置：不再内部构建 ApiClient，而是接受一个外部验证器
  Future<bool> verifyConfig(
    MediaServiceConfig config, {
    required MediaConfigValidator validator,
  });
}