class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    this.serverName,
    this.version,
    this.errorMessage,
  });

  final bool success;
  final String? serverName;
  final String? version;
  final String? errorMessage;

  String get displayMessage {
    if (!success) return errorMessage ?? '连接测试失败';
    final parts = <String>[];
    if (serverName != null && serverName!.isNotEmpty) parts.add(serverName!);
    if (version != null && version!.isNotEmpty) parts.add('版本 $version');
    parts.add('连接测试成功');
    return parts.join(' · ');
  }
}
