import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/media_service_config.dart';

class MockEmbyBootstrapConfig {
  const MockEmbyBootstrapConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
    required this.deviceId,
    required this.userId,
  });

  static const String assetPath = 'assets/config/mock_emby_bootstrap.json';

  final String serverUrl;
  final String username;
  final String password;
  final String deviceId;
  final String userId;

  factory MockEmbyBootstrapConfig.fromJson(Map<String, dynamic> json) {
    return MockEmbyBootstrapConfig(
      serverUrl: json['serverUrl']?.toString().trim() ?? '',
      username: json['username']?.toString().trim() ?? '',
      password: json['password']?.toString() ?? '',
      deviceId: json['deviceId']?.toString().trim() ?? '',
      userId: json['userId']?.toString().trim() ?? '',
    );
  }

  MediaServiceConfig toMediaServiceConfig() {
    return MediaServiceConfig(
      type: MediaServiceType.emby,
      serverUrl: serverUrl,
      username: username,
      password: password,
      deviceId: deviceId,
    );
  }
}

Future<MockEmbyBootstrapConfig> loadMockEmbyBootstrapConfig() async {
  final raw = await rootBundle.loadString(MockEmbyBootstrapConfig.assetPath);
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid mock Emby bootstrap config');
  }
  return MockEmbyBootstrapConfig.fromJson(decoded);
}
