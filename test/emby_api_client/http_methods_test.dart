// test/emby_api_client/http_methods_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:meowhub/data/datasources/emby_api_client.dart';
import 'package:meowhub/domain/entities/media_service_config.dart';
import '../mocks/mock_classes.dart';

void main() {
  late MockSecurityService mockSecurityService;
  late MockSessionExpiredNotifier mockNotifier;
  late MockDio mockDio;
  late EmbyApiClient client;

  setUp(() {
    mockSecurityService = MockSecurityService();
    mockNotifier = MockSessionExpiredNotifier();
    mockDio = MockDio();

    when(
      () => mockSecurityService.readAccessToken(namespace: any(named: 'namespace')),
    ).thenAnswer((_) async => null);
    when(
      () => mockSecurityService.readUserId(namespace: any(named: 'namespace')),
    ).thenAnswer((_) async => null);
    when(
      () => mockSecurityService.readPassword(namespace: any(named: 'namespace')),
    ).thenAnswer((_) async => null);
    when(
      () => mockSecurityService.writeAccessToken(
        any(),
        namespace: any(named: 'namespace'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockSecurityService.writeUserId(
        any(),
        namespace: any(named: 'namespace'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockSecurityService.writePassword(
        any(),
        namespace: any(named: 'namespace'),
      ),
    ).thenAnswer((_) async {});
  });

  group('HTTP 方法测试', () {
    test('GET 请求在已有 session 时直接发起请求', () async {
      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        deviceId: 'test-device',
      );

      // 模拟 token 和 userId
      when(
        () => mockSecurityService.readAccessToken(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'existing-token');
      when(
        () => mockSecurityService.readUserId(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'existing-user');

      // 模拟 GET 响应
      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: {'key': 'value'},
        headers: {'content-type': 'application/json'},
      );

      when(
        () => mockDio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => mockResponse);

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 执行 GET
      await client.get<Map<String, dynamic>>('/test');

      // 验证被调用
      verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/test',
          queryParameters: null,
        ),
      ).called(1);
    });

    test('当 token 过期时自动重新认证', () async {
      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        username: 'user',
        deviceId: 'test-device',
      );

      String? accessToken;
      when(
        () => mockSecurityService.readAccessToken(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => accessToken);

      when(
        () => mockSecurityService.readUserId(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'user-id');

      // 模拟认证调用
      when(
        () => mockSecurityService.readPassword(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'password');
      when(
        () => mockSecurityService.writeAccessToken(
          any(),
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((invocation) async {
        accessToken = invocation.positionalArguments.first as String;
      });

      final authResponse = MockResponse<Map<String, dynamic>>(
        data: {
          'AccessToken': 'new-token',
          'User': {'Id': 'user-id', 'Name': 'test-user'},
        },
      );

      final apiResponse = MockResponse<Map<String, dynamic>>(
        data: {'success': true},
      );

      // 设置 Dio 调用序列
      when(
        () => mockDio.post<Map<String, dynamic>>(
          '/emby/Users/AuthenticateByName',
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => authResponse);

      when(
        () => mockDio.get<Map<String, dynamic>>(
          any(),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => apiResponse);

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 执行 GET，应该触发自动认证
      await client.get<Map<String, dynamic>>('/test');

      // 验证认证被调用
      verify(
        () => mockSecurityService.readPassword(
          namespace: config.credentialNamespace,
        ),
      ).called(greaterThanOrEqualTo(1));
    });
  });
}
