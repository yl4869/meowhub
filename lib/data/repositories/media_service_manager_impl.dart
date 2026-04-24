import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/app_diagnostics.dart';
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
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaServiceManager] initialize:start | storageKey=$_configKey',
      );
    }
    final jsonStr = _prefs.getString(_configKey);
    if (jsonStr != null) {
      try {
        _cachedConfig = MediaServiceConfig.fromJson(jsonDecode(jsonStr));
        if (kDebugMode) {
          debugPrint(
            '[Diag][MediaServiceManager] initialize:loaded | '
            '${AppDiagnostics.configSummary(_cachedConfig)}',
          );
        }
      } catch (error, stackTrace) {
        _cachedConfig = null;
        if (kDebugMode) {
          debugPrint(
            '[Diag][MediaServiceManager] initialize:decode_failed | '
            'error=${AppDiagnostics.summarizeError(error)}',
          );
          debugPrint(stackTrace.toString());
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('[Diag][MediaServiceManager] initialize:no_saved_config');
      }
    }
  }

  @override
  MediaServiceConfig? getSavedConfig() => _cachedConfig;

  

  @override
  Future<void> clearConfig() async {
    if (kDebugMode) {
      debugPrint('[Diag][MediaServiceManager] clearConfig:start');
    }
    _cachedConfig = null;
    await _prefs.remove(_configKey);
    if (kDebugMode) {
      debugPrint('[Diag][MediaServiceManager] clearConfig:done');
    }
  }

  @override
  Future<bool> verifyConfig(
    MediaServiceConfig config, {
    required MediaConfigValidator validator,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaServiceManager] verifyConfig:start | '
        '${AppDiagnostics.configSummary(config)}',
      );
    }
    try {
      final result = await validator(config);
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaServiceManager] verifyConfig:done | '
          '${{
            ...AppDiagnostics.configSummary(config),
            'result': result,
          }}',
        );
      }
      return result;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][MediaServiceManager] verifyConfig:failed | '
          'config=${AppDiagnostics.configSummary(config)}, '
          'error=${AppDiagnostics.summarizeError(error)}',
        );
        debugPrint(stackTrace.toString());
      }
      rethrow;
    }
  }

  // 创建一个流控制器
  final _configController = StreamController<MediaServiceConfig?>.broadcast();

  @override
  Stream<MediaServiceConfig?> get configStream => _configController.stream;
  
  @override
  Future<void> setConfig(MediaServiceConfig config) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaServiceManager] setConfig:start | '
        '${AppDiagnostics.configSummary(config)}',
      );
    }
    _cachedConfig = config;
    await _prefs.setString(_configKey, jsonEncode(config.toJson()));
    // 🚀 向流中发送新配置，通知所有听众
    _configController.add(config); 
    
    debugPrint('[Diag] MediaServiceManager: 流已发出新配置');
    if (kDebugMode) {
      debugPrint(
        '[Diag][MediaServiceManager] setConfig:stored | '
        '${AppDiagnostics.configSummary(_cachedConfig)}',
      );
    }
  }

}
