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

  Future<void> write({required String key, required String value}) {
    return _secureStorage.write(key: key, value: value);
  }

  Future<String?> read(String key) {
    return _secureStorage.read(key: key);
  }

  Future<void> delete(String key) {
    return _secureStorage.delete(key: key);
  }

  Future<void> writeAccessToken(String token) {
    return write(key: _accessTokenKey, value: token);
  }

  Future<String?> readAccessToken() {
    return read(_accessTokenKey);
  }

  Future<void> deleteAccessToken() {
    return delete(_accessTokenKey);
  }

  Future<void> writeUserId(String userId) {
    return write(key: _userIdKey, value: userId);
  }

  Future<String?> readUserId() {
    return read(_userIdKey);
  }

  Future<void> deleteUserId() {
    return delete(_userIdKey);
  }

  Future<void> writePassword(String password) {
    return write(key: _passwordKey, value: password);
  }

  Future<String?> readPassword() {
    return read(_passwordKey);
  }

  Future<void> deletePassword() {
    return delete(_passwordKey);
  }

  Future<void> clearAuthSession() async {
    await Future.wait([deleteAccessToken(), deleteUserId()]);
  }

  Future<void> clearAllSensitiveData() async {
    await Future.wait([deleteAccessToken(), deleteUserId(), deletePassword()]);
  }
}
