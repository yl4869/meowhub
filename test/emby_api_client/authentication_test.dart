// test/emby_api_client/authentication_test.dart
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

  group('认证测试', () {
    test('成功认证 - 返回有效 token 和 userId', () async {
      // 配置 Mock
      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        username: 'testuser',
        password: 'testpass',
        deviceId: 'test-device',
      );

      // 模拟读取密码
      when(
        () => mockSecurityService.readPassword(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'testpass');

      // 模拟认证成功响应
      final authResponse = {
        'AccessToken': 'mock-token-123',
        'User': {'Id': 'user-456', 'Name': 'test-user'},
      };

      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: authResponse,
        headers: {'content-type': 'application/json'},
      );

      when(
        () => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockResponse);

      // 创建客户端
      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 执行认证
      await expectLater(client.authenticate(), completes);

      // 验证写入调用
      verify(
        () => mockSecurityService.writeAccessToken(
          'mock-token-123',
          namespace: config.credentialNamespace,
        ),
      ).called(1);
      verify(
        () => mockSecurityService.writeUserId(
          'user-456',
          namespace: config.credentialNamespace,
        ),
      ).called(1);
    });

    test('认证失败 - 缺少用户名密码', () async {
      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        username: null, // 缺少用户名
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 验证抛出异常
      await expectLater(client.authenticate(), throwsA(isA<Exception>()));
    });

    test('认证失败 - 服务器返回无效响应', () async {
      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        username: 'testuser',
        password: 'testpass',
        deviceId: 'test-device',
      );

      when(
        () => mockSecurityService.readPassword(
          namespace: config.credentialNamespace,
        ),
      ).thenAnswer((_) async => 'testpass');

      // 模拟返回空 token
      final authResponse = {
        'AccessToken': '', // 空 token
        'User': {'Id': 'user-456', 'Name': 'test-user'},
      };

      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: authResponse,
        headers: {'content-type': 'application/json'},
      );

      when(
        () => mockDio.post<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => mockResponse);

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 验证抛出异常
      await expectLater(client.authenticate(), throwsA(isA<Exception>()));
    });
  });
}
