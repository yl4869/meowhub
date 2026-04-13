// test/mocks/mock_classes.dart
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:meowhub/core/services/security_service.dart';
import 'package:meowhub/core/session/session_expired_notifier.dart';

// Mock SecurityService
class MockSecurityService extends Mock implements SecurityService {}

// Mock SessionExpiredNotifier
class MockSessionExpiredNotifier extends Mock
    implements SessionExpiredNotifier {}

// Mock Dio
class MockDio extends Mock implements Dio {
  @override
  BaseOptions get options => BaseOptions();

  @override
  set options(BaseOptions? _options) {}

  @override
  Interceptors get interceptors => Interceptors();
}

// Mock Response
class MockResponse<T> extends Mock implements Response<T> {
  MockResponse({T? data, Map<String, dynamic>? headers}) {
    when(() => this.data).thenReturn(data);
    when(() => this.headers).thenReturn(
      headers != null
        ? Headers.fromMap(headers.map((k, v) => MapEntry(k, [v.toString()])))
        : Headers.fromMap({})
    );
  }
}
