import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 敏感信息安全存储封装。
/// 服务器地址等普通设置继续存储在 shared_preferences 中。
class SecurityService {
  SecurityService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _accessTokenKey = 'emby_access_token';
  static const String _userIdKey = 'emby_user_id';
  static const String _passwordKey = 'emby_password';

  final FlutterSecureStorage _secureStorage;

  String _scopedKey(String key, String? namespace) {
    if (namespace == null || namespace.trim().isEmpty) {
      return key;
    }
    return '${namespace.trim()}::$key';
  }

  Future<void> write({required String key, required String value}) {
    return _secureStorage.write(key: key, value: value);
  }

  Future<String?> read(String key) {
    return _secureStorage.read(key: key);
  }

  Future<void> delete(String key) {
    return _secureStorage.delete(key: key);
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
