import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session/session_expired_notifier.dart';
import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_service_manager.dart';
import '../responsive/home_view.dart';

/// 媒体服务配置屏幕
/// 允许用户配置和验证媒体服务连接
class MediaServiceConfigScreen extends StatefulWidget {
  const MediaServiceConfigScreen({super.key});

  static const String routePath = '/login';

  @override
  State<MediaServiceConfigScreen> createState() =>
      _MediaServiceConfigScreenState();
}

class _MediaServiceConfigScreenState extends State<MediaServiceConfigScreen> {
  late final IMediaServiceManager _manager;
  late final MediaConfigValidator _configValidator;
  late TextEditingController _serverUrlController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _deviceIdController;

  MediaServiceType _selectedType = MediaServiceType.emby;
  bool _isVerifying = false;
  String? _verificationMessage;
  bool? _verificationSuccess;

  @override
  void initState() {
    super.initState();
    _manager = context.read<IMediaServiceManager>();
    _configValidator = context.read<MediaConfigValidator>();

    final savedConfig = _manager.getSavedConfig();
    _selectedType = savedConfig?.type ?? MediaServiceType.emby;
    _serverUrlController = TextEditingController(
      text: savedConfig?.serverUrl ?? '',
    );
    _usernameController = TextEditingController(
      text: savedConfig?.username ?? '',
    );
    _passwordController = TextEditingController(
      text: savedConfig?.password ?? '',
    );
    _deviceIdController = TextEditingController(
      text: savedConfig?.deviceId ?? '',
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _verifyConnection() async {
    setState(() {
      _isVerifying = true;
      _verificationMessage = null;
      _verificationSuccess = null;
    });

    try {
      final config = MediaServiceConfig(
        type: _selectedType,
        serverUrl: _serverUrlController.text,
        username: _usernameController.text.isEmpty
            ? null
            : _usernameController.text,
        password: _passwordController.text.isEmpty
            ? null
            : _passwordController.text,
        deviceId: _deviceIdController.text.isEmpty
            ? null
            : _deviceIdController.text,
      );

      final isValid = await _manager.verifyConfig(
        config,
        validator: _configValidator,
      );

      setState(() {
        _verificationSuccess = isValid;
        _verificationMessage = _selectedType == MediaServiceType.local
            ? (isValid ? '文件夹验证通过' : '部分文件夹不存在')
            : (isValid ? '连接成功' : '连接失败，请检查配置');
      });

      if (isValid && mounted) {
        await _manager.setConfig(config);
        if (mounted) {
          context.read<SessionExpiredNotifier>().markAuthenticated();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('配置已保存')));
          context.go(HomeView.routePath);
        }
      }
    } catch (e) {
      setState(() {
        _verificationSuccess = false;
        _verificationMessage = '错误: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除配置'),
        content: const Text('确定要清除媒体服务配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _manager.clearConfig();
      if (mounted) {
        context.read<SessionExpiredNotifier>().notifySessionExpired();
        _serverUrlController.clear();
        _usernameController.clear();
        _passwordController.clear();
        _deviceIdController.clear();
        setState(() {
          _verificationMessage = null;
          _verificationSuccess = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置已清除')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('媒体服务配置')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 服务类型选择
            Text('服务类型', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<MediaServiceType>(
              segments: const [
                ButtonSegment(
                  value: MediaServiceType.emby,
                  label: Text('Emby'),
                ),
                ButtonSegment(
                  value: MediaServiceType.plex,
                  label: Text('Plex'),
                  enabled: false,
                ),
                ButtonSegment(
                  value: MediaServiceType.jellyfin,
                  label: Text('Jellyfin'),
                  enabled: false,
                ),
                ButtonSegment(
                  value: MediaServiceType.local,
                  label: Text('本地'),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (selected) {
                setState(() {
                  _selectedType = selected.first;
                });
              },
            ),
            const SizedBox(height: 24),

            // 服务器地址
            TextField(
              controller: _serverUrlController,
              decoration: InputDecoration(
                labelText: '服务器地址',
                hintText: 'http://192.168.1.100:8096',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 用户名
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 密码
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            // 设备ID（可选）
            TextField(
              controller: _deviceIdController,
              decoration: InputDecoration(
                labelText: '设备ID（可选）',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 验证消息
            if (_verificationMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _verificationSuccess == true
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _verificationSuccess == true
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                child: Text(
                  _verificationMessage!,
                  style: TextStyle(
                    color: _verificationSuccess == true
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // 按钮
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isVerifying ? null : _verifyConnection,
                    child: _isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('验证并保存'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _clearConfig,
                  child: const Text('清除配置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
