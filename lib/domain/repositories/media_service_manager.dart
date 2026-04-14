import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../data/datasources/emby_api_client.dart';
import '../entities/media_service_config.dart';

/// 媒体服务管理器
/// 负责媒体配置持久化和连接验证，不再持有运行时 service 实例。
class MediaServiceManager extends ChangeNotifier {
  MediaServiceManager({
    required SharedPreferences preferences,
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  }) : _preferences = preferences,
       _securityService = securityService,
       _sessionExpiredNotifier = sessionExpiredNotifier;

  static const String _typeKey = 'media_service_type';
  static const String _serverUrlKey = 'media_service_server_url';
  static const String _usernameKey = 'media_service_username';
  static const String _deviceIdKey = 'media_service_device_id';

  final SharedPreferences _preferences;
  final SecurityService _securityService;
  final SessionExpiredNotifier _sessionExpiredNotifier;

  MediaServiceConfig? _savedConfig;

  bool get hasConfiguredService => _savedConfig != null;

  MediaServiceConfig? getSavedConfig() => _savedConfig;

  Future<MediaServiceConfig?> _loadSavedConfig() async {
    final typeStr = _preferences.getString(_typeKey);
    final serverUrl = _preferences.getString(_serverUrlKey);
    final username = _preferences.getString(_usernameKey);

    if (typeStr == null || serverUrl == null) {
      return null;
    }

    final type = MediaServiceType.values.firstWhere(
      (value) => value.name == typeStr,
      orElse: () => MediaServiceType.emby,
    );

    final normalizedServerUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    final credentialNamespace =
        '$typeStr:${normalizedServerUrl.toLowerCase()}:${(username ?? '').trim().toLowerCase()}';

    return MediaServiceConfig(
      type: type,
      serverUrl: normalizedServerUrl,
      username: username,
      password: await _securityService.readPassword(
        namespace: credentialNamespace,
      ),
      deviceId: _preferences.getString(_deviceIdKey),
    );
  }

  Future<void> setConfig(MediaServiceConfig config) async {
    final effectivePassword =
        config.password ??
        await _securityService.readPassword(
          namespace: config.credentialNamespace,
        );
    final normalizedConfig = config.copyWith(
      serverUrl: config.normalizedServerUrl,
      password: effectivePassword,
    );

    if (!normalizedConfig.isValid) {
      throw ArgumentError('Invalid media service config');
    }

    await Future.wait([
      _preferences.setString(_typeKey, normalizedConfig.type.name),
      _preferences.setString(
        _serverUrlKey,
        normalizedConfig.normalizedServerUrl,
      ),
      if (normalizedConfig.username != null)
        _preferences.setString(_usernameKey, normalizedConfig.username!)
      else
        _preferences.remove(_usernameKey),
      if (normalizedConfig.deviceId != null)
        _preferences.setString(_deviceIdKey, normalizedConfig.deviceId!)
      else
        _preferences.remove(_deviceIdKey),
      if (normalizedConfig.password != null)
        _securityService.writePassword(
          normalizedConfig.password!,
          namespace: normalizedConfig.credentialNamespace,
        ),
      _securityService.clearAuthSession(
        namespace: normalizedConfig.credentialNamespace,
      ),
    ]);
    _savedConfig = normalizedConfig;
    notifyListeners();
  }

  Future<void> initialize() async {
    _savedConfig = await _loadSavedConfig();
    notifyListeners();
  }

  Future<void> clearConfig() async {
    await Future.wait([
      _preferences.remove(_typeKey),
      _preferences.remove(_serverUrlKey),
      _preferences.remove(_usernameKey),
      _preferences.remove(_deviceIdKey),
      if (_savedConfig != null)
        _securityService.clearAllSensitiveData(
          namespace: _savedConfig!.credentialNamespace,
        ),
    ]);

    _savedConfig = null;
    notifyListeners();
  }

  Future<bool> verifyConfig(MediaServiceConfig config) async {
    try {
      final apiClient = EmbyApiClient(
        config: config,
        securityService: _securityService,
        sessionExpiredNotifier: _sessionExpiredNotifier,
      );
      await apiClient.authenticate();
      await apiClient.getSystemInfo();
      return true;
    } catch (_) {
      return false;
    }
  }

  SecurityService get securityService => _securityService;

  SessionExpiredNotifier get sessionExpiredNotifier => _sessionExpiredNotifier;
}
