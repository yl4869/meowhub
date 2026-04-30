import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/services/security_service.dart';
import '../../core/session/session_expired_notifier.dart';
import '../../domain/entities/connection_test_result.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_connection_tester.dart';
import '../datasources/emby_api_client.dart';

class EmbyConnectionTester implements IMediaConnectionTester {
  EmbyConnectionTester({
    required SecurityService securityService,
    required SessionExpiredNotifier sessionExpiredNotifier,
  }) : _securityService = securityService,
       _sessionExpiredNotifier = sessionExpiredNotifier;

  final SecurityService _securityService;
  final SessionExpiredNotifier _sessionExpiredNotifier;

  @override
  Future<bool> validate(MediaServiceConfig config) async {
    if (config.type == MediaServiceType.local) {
      if (config.localPaths.isEmpty) return false;
      for (final path in config.localPaths) {
        final dir = Directory(path.trim());
        if (!await dir.exists()) return false;
      }
      return true;
    }

    if (config.type != MediaServiceType.emby &&
        config.type != MediaServiceType.jellyfin) {
      return false;
    }

    try {
      final apiClient = EmbyApiClient(
        config: config,
        securityService: _securityService,
        sessionExpiredNotifier: _sessionExpiredNotifier,
      );
      await apiClient.authenticate();
      await apiClient.getSystemInfo();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ConnectionTestResult> testConnection(MediaServiceConfig config) async {
    try {
      final apiClient = EmbyApiClient(
        config: config,
        securityService: _securityService,
        sessionExpiredNotifier: _sessionExpiredNotifier,
      );
      final publicInfo = await apiClient.getPublicSystemInfo();
      final serverName = publicInfo['ServerName']?.toString().trim();
      final version = publicInfo['Version']?.toString().trim();
      return ConnectionTestResult(
        success: true,
        serverName: serverName,
        version: version,
      );
    } catch (error) {
      return ConnectionTestResult(
        success: false,
        errorMessage: _describeError(error),
      );
    }
  }

  String _describeError(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout => '连接超时，请检查服务器地址',
        DioExceptionType.receiveTimeout => '服务器响应超时',
        DioExceptionType.connectionError => '无法连接到服务器，请检查地址和网络',
        DioExceptionType.badResponse => '服务器返回错误：${error.response?.statusCode}',
        _ => '连接失败：${error.message}',
      };
    }
    return '连接失败：$error';
  }
}
