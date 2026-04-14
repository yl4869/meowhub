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
    try {
      // 1. 获取“是否需要 Token”的信号，默认需要
      final bool requiresToken = options.extra['withToken'] ?? true;

      debugPrint(
        '🛡️ [Interceptor] 正在处理请求: ${options.path}, 需要Token: $requiresToken',
      );

      // 2. 无论是否需要 Token，设备信息通常是需要的
      options.headers['X-Emby-Authorization'] =
          'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="$deviceId", Version="1.0.0"';

      // 3. 只有当明确需要 Token 时，才去读取并注入
      if (requiresToken) {
        final accessToken = await _securityService.readAccessToken();
        if (accessToken != null && accessToken.isNotEmpty) {
          options.headers['X-Emby-Token'] = accessToken;
          debugPrint('🛡️ [Interceptor] 已注入 Token');
        } else {
          debugPrint('⚠️ [Interceptor] 需要 Token 但本地未找到');
        }
      } else {
        debugPrint('🛡️ [Interceptor] 登录/公开请求，跳过 Token 注入');
      }

      // 4. 必须调用，否则请求永远停在这里
      handler.next(options);
    } catch (e, stack) {
      debugPrint('🚨 [Interceptor] 内部逻辑崩溃: $e');
      // 即使拦截器崩了，也建议让请求继续或报错，而不是卡死
      handler.reject(DioException(requestOptions: options, error: e));
    }
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
