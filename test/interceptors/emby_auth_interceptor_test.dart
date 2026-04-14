// test/interceptors/emby_auth_interceptor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';

import 'package:meowhub/data/network/emby_auth_interceptor.dart';
import '../mocks/mock_classes.dart';

class _NoopErrorInterceptorHandler extends ErrorInterceptorHandler {
  @override
  void next(DioException error) {}
}

void main() {
  group('EmbyAuthInterceptor 测试', () {
    test('当响应 401 时触发会话过期通知', () async {
      final mockSecurityService = MockSecurityService();
      final mockNotifier = MockSessionExpiredNotifier();
      final mockRequestOptions = RequestOptions(path: '/test');
      final mockResponse = Response(
        requestOptions: mockRequestOptions,
        statusCode: 401, // 未授权
        data: {'error': 'Unauthorized'},
      );

      final interceptor = EmbyAuthInterceptor(
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
      );
      when(
        () => mockSecurityService.clearAuthSession(
          namespace: any(named: 'namespace'),
        ),
      ).thenAnswer((_) async {});

      // 模拟错误处理
      final error = DioException(
        requestOptions: mockRequestOptions,
        response: mockResponse,
        type: DioExceptionType.badResponse,
      );

      // 验证通知被触发
      await interceptor.onError(error, _NoopErrorInterceptorHandler());

      // 验证会话过期通知被调用
      verify(
        () => mockSecurityService.clearAuthSession(
          namespace: any(named: 'namespace'),
        ),
      ).called(1);
      verify(() => mockNotifier.notifySessionExpired()).called(1);
    });
  });
}
