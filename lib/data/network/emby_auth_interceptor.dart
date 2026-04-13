import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';

class EmbyAuthInterceptor extends QueuedInterceptor {
  EmbyAuthInterceptor({
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
    this.deviceId = 'debug-mac-device', // 传入设备ID
  }) : _securityService = securityService,
       _sessionExpiredNotifier = sessionExpiredNotifier;

  final SecurityService _securityService;
  final SessionExpiredNotifier _sessionExpiredNotifier;
  final String deviceId;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _securityService.readAccessToken();

    debugPrint('emby_auth_interceptor: the deviceid is $deviceId');

  // 1. Authorization 只放设备信息，不放 Token
  options.headers['X-Emby-Authorization'] = 
      'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="$deviceId", Version="1.0.0"';

  // 2. 将 Token 独立出来，作为一个单独的 Header
  // 这种写法能避开 99% 的服务器字符串解析 Bug
  if (accessToken != null && accessToken.isNotEmpty) {
    options.headers['X-Emby-Token'] = accessToken; 
  }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      await _securityService.clearAuthSession();
      _sessionExpiredNotifier.notifySessionExpired();
    }
    handler.next(err);
  }
}
