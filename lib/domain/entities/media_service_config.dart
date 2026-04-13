/// 媒体服务提供商类型
enum MediaServiceType {
  emby,
  plex,
  jellyfin,
  // 未来可扩展的服务类型
}

/// 媒体服务配置
class MediaServiceConfig {
  const MediaServiceConfig({
    required this.type,
    required this.serverUrl,
    this.username,
    this.password,
    this.deviceId,
  });

  /// 服务类型
  final MediaServiceType type;

  /// 服务器地址 (e.g., http://192.168.1.100:8096)
  final String serverUrl;

  /// 用户名（某些服务可能需要）
  final String? username;

  /// 密码（某些服务可能需要）
  final String? password;

  /// 设备ID（用于跟踪播放进度）
  final String? deviceId;

  /// 验证配置是否有效
  bool get isValid {
    return switch (type) {
      MediaServiceType.emby =>
        serverUrl.isNotEmpty &&
        (username?.trim().isNotEmpty ?? false) &&
        (password?.trim().isNotEmpty ?? false),
      MediaServiceType.plex || MediaServiceType.jellyfin =>
        serverUrl.isNotEmpty,
    };
  }

  /// 规范化服务器URL（移除末尾斜杠）
  String get normalizedServerUrl => serverUrl.endsWith('/')
      ? serverUrl.substring(0, serverUrl.length - 1)
      : serverUrl;

  MediaServiceConfig copyWith({
    MediaServiceType? type,
    String? serverUrl,
    String? username,
    String? password,
    String? deviceId,
  }) {
    return MediaServiceConfig(
      type: type ?? this.type,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}
