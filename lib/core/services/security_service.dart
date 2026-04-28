import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 敏感信息安全存储封装。
/// 服务器地址等普通设置继续存储在 shared_preferences 中。
class SecurityService {
  SecurityService({
    FlutterSecureStorage? secureStorage,
    required SharedPreferences preferences,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _preferences = preferences;

  static const String _accessTokenKey = 'access_token';
  static const String _userIdKey = 'user_id';
  static const String _passwordKey = 'password';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _preferences;

  String _webScopedKey(String key) => 'web_secure_$key';

  String _scopedKey(String key, String? namespace) {
    if (namespace == null || namespace.trim().isEmpty) {
      return key;
    }
    return '${namespace.trim()}::$key';
  }

  Future<void> write({required String key, required String value}) async {
    try {
      if (kIsWeb) {
        await _preferences.setString(_webScopedKey(key), value);
      } else {
        await _secureStorage.write(key: key, value: value);
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<String?> read(String key) async {
    try {
      final value = kIsWeb
          ? _preferences.getString(_webScopedKey(key))
          : await _secureStorage.read(key: key);
      return value;
    } catch (error) {
      rethrow;
    }
  }

  Future<void> delete(String key) async {
    try {
      if (kIsWeb) {
        await _preferences.remove(_webScopedKey(key));
      } else {
        await _secureStorage.delete(key: key);
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<void> writeAccessToken(String token, {String? namespace}) {
    return write(key: _scopedKey(_accessTokenKey, namespace), value: token);
  }

  Future<String?> readAccessToken({String? namespace}) {
    return read(_scopedKey(_accessTokenKey, namespace));
  }

  Future<void> deleteAccessToken({String? namespace}) {
    return delete(_scopedKey(_accessTokenKey, namespace));
  }

  Future<void> writeUserId(String userId, {String? namespace}) {
    return write(key: _scopedKey(_userIdKey, namespace), value: userId);
  }

  Future<String?> readUserId({String? namespace}) {
    return read(_scopedKey(_userIdKey, namespace));
  }

  Future<void> deleteUserId({String? namespace}) {
    return delete(_scopedKey(_userIdKey, namespace));
  }

  Future<void> writePassword(String password, {String? namespace}) {
    return write(key: _scopedKey(_passwordKey, namespace), value: password);
  }

  Future<String?> readPassword({String? namespace}) {
    return read(_scopedKey(_passwordKey, namespace));
  }

  Future<void> deletePassword({String? namespace}) {
    return delete(_scopedKey(_passwordKey, namespace));
  }

  Future<void> clearAuthSession({String? namespace}) async {
    await Future.wait([
      deleteAccessToken(namespace: namespace),
      deleteUserId(namespace: namespace),
    ]);
  }

  Future<void> clearAllSensitiveData({String? namespace}) async {
    await Future.wait([
      deleteAccessToken(namespace: namespace),
      deleteUserId(namespace: namespace),
      deletePassword(namespace: namespace),
    ]);
  }
}
