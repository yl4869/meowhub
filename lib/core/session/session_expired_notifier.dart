import 'package:flutter/foundation.dart';

/// 全局登录态失效通知。
/// 用于在拦截器收到 401 后，把应用带回登录页。
class SessionExpiredNotifier extends ChangeNotifier {
  bool _requiresLogin = false;

  bool get requiresLogin => _requiresLogin;

  void notifySessionExpired() {
    if (_requiresLogin) {
      return;
    }
    _requiresLogin = true;
    notifyListeners();
  }

  void markAuthenticated() {
    if (!_requiresLogin) {
      return;
    }
    _requiresLogin = false;
    notifyListeners();
  }
}
