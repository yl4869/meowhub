import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../entities/media_service_config.dart';
import '../repositories/media_service.dart';

/// 媒体服务管理器
/// 负责管理当前活跃的媒体服务和配置持久化。
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

  MediaService? _currentService;
  MediaServiceConfig? _savedConfig;

  MediaService? get currentService => _currentService;
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
    _currentService = _createService(config);
  }

  Future<void> initialize() async {
    _savedConfig = await _loadSavedConfig();
    if (_savedConfig != null) {
      _currentService = _createService(_savedConfig!);
    }
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
    _currentService = null;
  }

  Future<bool> verifyConfig(MediaServiceConfig config) async {
    try {
      final service = _createService(config);
      return await service.verifyConnection();
    } catch (_) {
      return false;
    }
  }

  MediaService _createService(MediaServiceConfig config) {
    return MediaServiceFactory.create(
      config,
      securityService: _securityService,
      sessionExpiredNotifier: _sessionExpiredNotifier,
    );
  }
}
