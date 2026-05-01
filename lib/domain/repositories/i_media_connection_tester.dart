import '../entities/connection_test_result.dart';
import '../entities/media_service_config.dart';

abstract class IMediaConnectionTester {
  Future<bool> validate(MediaServiceConfig config);

  Future<ConnectionTestResult> testConnection(MediaServiceConfig config);
}
