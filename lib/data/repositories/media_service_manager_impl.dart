import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_service_manager.dart';
import '../mappers/media_service_config_serializer.dart';

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
        _cachedConfig = MediaServiceConfigSerializer.fromJson(jsonDecode(jsonStr));
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
    debugPrint('[MediaServiceManager] setConfig: type=${config.type.name}');
    _cachedConfig = config;
    await _prefs.setString(_configKey, jsonEncode(MediaServiceConfigSerializer.toJson(config)));
    debugPrint('[MediaServiceManager] setConfig: 发布到 configStream');
    _configController.add(config);
  }
}
