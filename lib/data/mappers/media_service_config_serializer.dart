import '../../domain/entities/media_service_config.dart';

class MediaServiceConfigSerializer {
  MediaServiceConfigSerializer._();

  static Map<String, dynamic> toJson(
    MediaServiceConfig config, {
    bool includePassword = false,
  }) {
    return <String, dynamic>{
      'type': config.type.name,
      'serverUrl': config.normalizedServerUrl,
      if (config.username != null) 'username': config.username,
      if (includePassword && config.password != null)
        'password': config.password,
      if (config.deviceId != null) 'deviceId': config.deviceId,
      if (config.localPaths.isNotEmpty) 'localPaths': config.localPaths,
    };
  }

  static MediaServiceConfig fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString().trim();
    final type = MediaServiceType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => MediaServiceType.emby,
    );

    final localPaths = (json['localPaths'] as List<dynamic>?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false) ??
        const [];

    return MediaServiceConfig(
      type: type,
      serverUrl: json['serverUrl']?.toString().trim() ?? '',
      username: json['username']?.toString().trim(),
      password: json['password']?.toString(),
      deviceId: json['deviceId']?.toString().trim(),
      localPaths: localPaths,
    );
  }
}
