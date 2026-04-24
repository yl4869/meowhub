import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../core/utils/app_diagnostics.dart';

class EmbyAuthInterceptor extends QueuedInterceptor {
  EmbyAuthInterceptor({
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
    this.namespace = '',
    this.deviceId = 'meowhub-device',
  }) : _securityService = securityService,
       _sessionExpiredNotifier = sessionExpiredNotifier;

  final SecurityService _securityService;
  final SessionExpiredNotifier _sessionExpiredNotifier;
  final String namespace;
  final String deviceId;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final bool requiresToken = options.extra['withToken'] ?? true;
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyAuthInterceptor] onRequest | '
          'method=${options.method}, path=${options.path}, '
          'requiresToken=$requiresToken, namespace=$namespace',
        );
      }

      options.headers['X-Emby-Authorization'] =
          'MediaBrowser Client="MeowHub", Device="MeowHub", DeviceId="$deviceId", Version="1.0.0"';
      options.headers['X-Emby-Device-Id'] = deviceId;

      if (requiresToken) {
        final accessToken = await _securityService.readAccessToken(
          namespace: namespace,
        );
        if (accessToken != null && accessToken.isNotEmpty) {
          options.headers['X-Emby-Token'] = accessToken;
          if (kDebugMode) {
            debugPrint(
              '[Diag][EmbyAuthInterceptor] token_attached | '
              'path=${options.path}, namespace=$namespace',
            );
          }
        } else {
          if (kDebugMode) {
            debugPrint(
              '[Diag][EmbyAuthInterceptor] token_missing | '
              'path=${options.path}, namespace=$namespace',
            );
          }
        }
      }
      handler.next(options);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyAuthInterceptor] onRequest:failed | '
          'method=${options.method}, path=${options.path}, '
          'error=${AppDiagnostics.summarizeError(e)}',
        );
        debugPrint(stackTrace.toString());
      }
      handler.reject(DioException(requestOptions: options, error: e));
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (kDebugMode) {
      debugPrint(
        '[Diag][EmbyAuthInterceptor] onError | '
        'path=${err.requestOptions.path}, statusCode=${err.response?.statusCode}',
      );
    }
    if (err.response?.statusCode == 401) {
      await _securityService.clearAuthSession(namespace: namespace);
      _sessionExpiredNotifier.notifySessionExpired();
      if (kDebugMode) {
        debugPrint(
          '[Diag][EmbyAuthInterceptor] session_cleared_after_401 | '
          'namespace=$namespace',
        );
      }
    }
    handler.next(err);
  }
}
