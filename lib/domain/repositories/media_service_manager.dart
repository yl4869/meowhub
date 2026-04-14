import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../data/datasources/emby_api_client.dart';
import '../entities/media_service_config.dart';

/// 媒体服务管理器
/// 负责媒体配置持久化和连接验证，不再持有运行时 service 实例。
class MediaServiceManager {
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

    if (typeStr == null || serverUrl == null) {
      return null;
    }

    final type = MediaServiceType.values.firstWhere(
      (value) => value.name == typeStr,
      orElse: () => MediaServiceType.emby,
    );

    return MediaServiceConfig(
      type: type,
      serverUrl: serverUrl,
      username: _preferences.getString(_usernameKey),
      password: await _securityService.readPassword(),
      deviceId: _preferences.getString(_deviceIdKey),
    );
  }

  Future<void> setConfig(MediaServiceConfig config) async {
    if (!config.isValid) {
      throw ArgumentError('Invalid media service config');
    }

    await Future.wait([
      _preferences.setString(_typeKey, config.type.name),
      _preferences.setString(_serverUrlKey, config.serverUrl),
      if (config.username != null)
        _preferences.setString(_usernameKey, config.username!)
      else
        _preferences.remove(_usernameKey),
      if (config.deviceId != null)
        _preferences.setString(_deviceIdKey, config.deviceId!)
      else
        _preferences.remove(_deviceIdKey),
      if (config.password != null)
        _securityService.writePassword(config.password!)
      else
        _securityService.deletePassword(),
      _securityService.clearAuthSession(),
    ]);
    _savedConfig = config;
  }

  Future<void> initialize() async {
    _savedConfig = await _loadSavedConfig();
  }

  Future<void> clearConfig() async {
    await Future.wait([
      _preferences.remove(_typeKey),
      _preferences.remove(_serverUrlKey),
      _preferences.remove(_usernameKey),
      _preferences.remove(_deviceIdKey),
      _securityService.clearAllSensitiveData(),
    ]);

    _savedConfig = null;
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
