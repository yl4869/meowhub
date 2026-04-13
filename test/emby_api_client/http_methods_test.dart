// test/emby_api_client/http_methods_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';

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
  });

  group('HTTP 方法测试', () {
    test('GET 请求自动添加认证头', () async {
      // 模拟 token 和 userId
      when(() => mockSecurityService.readAccessToken())
          .thenAnswer((_) async => 'existing-token');
      when(() => mockSecurityService.readUserId())
          .thenAnswer((_) async => 'existing-user');

      // 模拟 GET 响应
      final mockResponse = MockResponse<Map<String, dynamic>>(
        data: {'key': 'value'},
        headers: {'content-type': 'application/json'},
      );

      when(() => mockDio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      )).thenAnswer((invocation) async {
        // 验证请求头
        final options = invocation.namedArguments[#options] as Options?;
        final headers = options?.headers ?? {};

        // 验证认证头存在
        expect(headers['X-Emby-Authorization'], isNotNull);
        return mockResponse;
      });

      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 执行 GET
      await client.get<Map<String, dynamic>>('/test');

      // 验证被调用
      verify(() => mockDio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
        options: any(named: 'options'),
      )).called(1);
    });

    test('当 token 过期时自动重新认证', () async {
      // 第一次：token 不存在
      var callCount = 0;
      when(() => mockSecurityService.readAccessToken())
          .thenAnswer((_) async {
            if (callCount == 0) {
              callCount++;
              return null;  // 第一次返回 null
            }
            return 'new-token';
          });

      when(() => mockSecurityService.readUserId())
          .thenAnswer((_) async => 'user-id');

      // 模拟认证调用
      when(() => mockSecurityService.readPassword())
          .thenAnswer((_) async => 'password');

      final authResponse = MockResponse<Map<String, dynamic>>(
        data: {
          'AccessToken': 'new-token',
          'User': {'Id': 'user-id'},
        },
      );

      final apiResponse = MockResponse<Map<String, dynamic>>(
        data: {'success': true},
      );

      // 设置 Dio 调用序列
      when(() => mockDio.post<Map<String, dynamic>>(
        '/emby/Users/AuthenticateByName',
        data: any(named: 'data'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => authResponse);

      when(() => mockDio.get<Map<String, dynamic>>(
        any(),
        options: any(named: 'options'),
      )).thenAnswer((_) async => apiResponse);

      final config = MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: 'http://test.com',
        username: 'user',
        deviceId: 'test-device',
      );

      client = EmbyApiClient(
        config: config,
        securityService: mockSecurityService,
        sessionExpiredNotifier: mockNotifier,
        dio: mockDio,
      );

      // 执行 GET，应该触发自动认证
      await client.get<Map<String, dynamic>>('/test');

      // 验证认证被调用
      verify(() => mockSecurityService.readPassword()).called(1);
    });
  });
}
