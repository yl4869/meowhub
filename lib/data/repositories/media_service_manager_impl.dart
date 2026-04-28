import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_service_manager.dart';

class MediaServiceManagerImpl implements IMediaServiceManager {
  MediaServiceManagerImpl({required SharedPreferences preferences})
    : _prefs = preferences;

  final SharedPreferences _prefs;
  static const String _configKey = 'active_media_service_config';

  // 内存缓存，避免频繁读取磁盘
  MediaServiceConfig? _cachedConfig;

  @override
  Future<void> initialize() async {
    final jsonStr = _prefs.getString(_configKey);
    if (jsonStr != null) {
      try {
        _cachedConfig = MediaServiceConfig.fromJson(jsonDecode(jsonStr));
      } catch (error) {
        _cachedConfig = null;
      }
    } else {}
  }

  @override
  MediaServiceConfig? getSavedConfig() => _cachedConfig;

  @override
  Future<void> clearConfig() async {
    _cachedConfig = null;
    await _prefs.remove(_configKey);
    _configController.add(null);
  }

  @override
  Future<bool> verifyConfig(
    MediaServiceConfig config, {
    required MediaConfigValidator validator,
  }) async {
    try {
      final result = await validator(config);
      return result;
    } catch (error) {
      rethrow;
    }
  }

  // 创建一个流控制器
  final _configController = StreamController<MediaServiceConfig?>.broadcast();

  @override
  Stream<MediaServiceConfig?> get configStream => _configController.stream;

  @override
  Future<void> setConfig(MediaServiceConfig config) async {
    _cachedConfig = config;
    await _prefs.setString(_configKey, jsonEncode(config.toJson()));
    // 🚀 向流中发送新配置，通知所有听众
    _configController.add(config);
  }
}
