import '../../domain/entities/media_service_config.dart';

class AppDiagnostics {
  static Map<String, Object?> configSummary(MediaServiceConfig? config) {
    if (config == null) {
      return const <String, Object?>{'configured': false};
    }

    final uri = Uri.tryParse(config.normalizedServerUrl);
    return <String, Object?>{
      'configured': true,
      'type': config.type.name,
      'server': config.normalizedServerUrl,
      'host': uri?.host,
      'port': uri?.port == 0 ? null : uri?.port,
      'username': _maskText(config.username),
      'deviceId': _maskText(config.deviceId),
      'namespace': _maskText(config.credentialNamespace, keepEnd: 4),
      'hasPassword': config.password?.isNotEmpty == true,
    };
  }

  static Map<String, Object?> sanitizeMap(Map<String, dynamic>? source) {
    if (source == null) {
      return const <String, Object?>{};
    }

    final output = <String, Object?>{};
    for (final entry in source.entries) {
      output[entry.key] = _sanitizeValue(entry.key, entry.value);
    }
    return output;
  }

  static String summarizeError(Object error) {
    final text = error.toString().replaceAll('\n', ' ').trim();
    return text.length <= 240 ? text : '${text.substring(0, 240)}...';
  }

  static String? maskText(
    String? value, {
    int keepStart = 3,
    int keepEnd = 2,
  }) {
    return _maskText(value, keepStart: keepStart, keepEnd: keepEnd);
  }

  static Object? _sanitizeValue(String key, Object? value) {
    final normalizedKey = key.toLowerCase();
    if (normalizedKey.contains('password') ||
        normalizedKey.contains('token') ||
        normalizedKey.contains('secret') ||
        normalizedKey.contains('authorization')) {
      return _maskText(value?.toString(), keepEnd: 2);
    }

    if (value is Map<String, dynamic>) {
      return sanitizeMap(value);
    }
    if (value is Map) {
      return value.map(
        (mapKey, mapValue) => MapEntry(
          mapKey.toString(),
          _sanitizeValue(mapKey.toString(), mapValue),
        ),
      );
    }
    if (value is List) {
      return value.take(6).toList(growable: false);
    }
    if (value is String) {
      return value.length <= 180 ? value : '${value.substring(0, 180)}...';
    }
    return value;
  }

  static String? _maskText(
    String? value, {
    int keepStart = 3,
    int keepEnd = 2,
  }) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      return text;
    }
    if (text.length <= keepStart + keepEnd) {
      return '*' * text.length;
    }
    return '${text.substring(0, keepStart)}***${text.substring(text.length - keepEnd)}';
  }
}
