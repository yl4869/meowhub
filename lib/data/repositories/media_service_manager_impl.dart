import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_service_manager.dart';

class MediaServiceManagerImpl implements IMediaServiceManager {
  MediaServiceManagerImpl({
    required SharedPreferences preferences,
  }) : _prefs = preferences;

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
      } catch (_) {
        _cachedConfig = null;
      }
    }
  }

  @override
  MediaServiceConfig? getSavedConfig() => _cachedConfig;

  @override
  Future<void> setConfig(MediaServiceConfig config) async {
    _cachedConfig = config;
    await _prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  @override
  Future<void> clearConfig() async {
    _cachedConfig = null;
    await _prefs.remove(_configKey);
  }

  @override
  Future<bool> verifyConfig(
    MediaServiceConfig config, {
    required MediaConfigValidator validator,
  }) async {
    // 自身不具备网络通讯能力，完全依赖外部传入的校验逻辑
    return await validator(config);
  }
}