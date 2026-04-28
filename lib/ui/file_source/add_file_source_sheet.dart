import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_service_config.dart';
import '../../domain/repositories/i_media_connection_tester.dart';
import '../../domain/repositories/i_media_maintainer.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../atoms/app_surface_card.dart';
import 'file_source_form_section.dart';
import 'file_source_type_selector.dart';
import 'local_file_source_form.dart';

class AddFileSourceSheet extends StatefulWidget {
  const AddFileSourceSheet({super.key, this.initialServer});

  final MediaServerInfo? initialServer;

  @override
  State<AddFileSourceSheet> createState() => _AddFileSourceSheetState();
}

enum _ConnectionTestState { idle, success, failure }

class _AddFileSourceSheetState extends State<AddFileSourceSheet> {
  final _embyFormKey = GlobalKey<FormState>();
  final _localFormKey = GlobalKey<LocalFileSourceFormState>();
  final _serverNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8096');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  MediaServiceType? _selectedType;
  String _protocol = 'http';
  bool _showValidation = false;
  bool _isTestingConnection = false;
  bool _isSaving = false;
  _ConnectionTestState _connectionTestState = _ConnectionTestState.idle;
  String? _connectionFeedback;
  String? _lastSuccessfulEndpointSignature;

  // Local media state
  final List<String> _localPaths = [];
  final _localNameController = TextEditingController();

  bool get _isEditMode => widget.initialServer != null;
  String? get _editingServerId => widget.initialServer?.id;

  @override
  void initState() {
    super.initState();
    _hydrateInitialServer();
    _addressController.addListener(_handleEndpointChanged);
    _portController.addListener(_handleEndpointChanged);
  }

  void _hydrateInitialServer() {
    final server = widget.initialServer;
    if (server?.config case final config?) {
      _selectedType = config.type;
      _serverNameController.text = server!.name;
      if (config.type == MediaServiceType.local) {
        _localPaths.addAll(config.localPaths);
        _localNameController.text = server.name != '本地视频' ? server.name : '';
        return;
      }
      _usernameController.text = config.username ?? '';
      _passwordController.text = config.password ?? '';
      final uri = Uri.tryParse(config.normalizedServerUrl);
      _protocol = uri?.scheme == 'https' ? 'https' : 'http';
      _addressController.text = uri?.host ?? config.normalizedServerUrl;
      final port = uri?.hasPort == true
          ? uri!.port.toString()
          : (_protocol == 'https' ? '8920' : '8096');
      _portController.text = port;
    }
  }

  @override
  void dispose() {
    _addressController.removeListener(_handleEndpointChanged);
    _portController.removeListener(_handleEndpointChanged);
    _serverNameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _localNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final canSubmit = (_selectedType == MediaServiceType.emby ||
            _selectedType == MediaServiceType.local) &&
        !_isSaving;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + mediaQuery.viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                title: _isEditMode ? '编辑服务器' : '添加服务器',
                subtitle: _selectedType == null
                    ? '选择一个媒体服务类型后，我们会用分组表单帮你完成连接配置。'
                    : '你可以先测试连接再保存，但测试结果只作为辅助信息，不会影响保存。',
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 16),
              AppSurfaceCard(
                child: Row(
                  children: [
                    Icon(Icons.dns_rounded, color: AppTheme.accentColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isEditMode
                            ? '正在编辑 ${widget.initialServer?.name ?? '服务器'}'
                            : '当前表单会在保存后直接写入全局服务器列表。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _selectedType == null
                    ? _buildTypeSelector()
                    : _selectedType == MediaServiceType.local
                        ? _buildLocalManager(context)
                        : _buildEmbyManager(context),
              ),
              const SizedBox(height: 16),
              _ActionBar(
                canSave: canSubmit,
                isTestingConnection: _isTestingConnection,
                isSaving: _isSaving,
                isEditMode: _isEditMode,
                onTestConnection: _isTestingConnection ? null : _testConnection,
                onSave: canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return KeyedSubtree(
      key: const ValueKey<String>('type-selector'),
      child: FileSourceTypeSelector(
        onSelected: (type) {
          setState(() {
            _selectedType = type;
            _showValidation = false;
          });
        },
      ),
    );
  }

  Widget _buildEmbyManager(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey<String>('emby-manager'),
      child: Form(
        key: _embyFormKey,
        autovalidateMode: _showValidation
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isEditMode
                      ? null
                      : () {
                          setState(() {
                            _selectedType = null;
                            _connectionTestState = _ConnectionTestState.idle;
                            _connectionFeedback = null;
                            _lastSuccessfulEndpointSignature = null;
                          });
                        },
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('更换类型'),
                ),
                const Spacer(),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text(
                      _selectedType?.displayName ?? '',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FileSourceFormSection(
              title: '基础信息',
              subtitle: '给服务器起一个容易辨认的名字，方便后续在多个线路之间切换。',
              child: TextFormField(
                controller: _serverNameController,
                decoration: const InputDecoration(
                  labelText: '服务器名称',
                  hintText: '例如：家里 Emby',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
                validator: _validateRequiredText,
              ),
            ),
            const SizedBox(height: 12),
            FileSourceFormSection(
              title: '地址信息',
              subtitle: '连接测试会使用这里的地址匿名访问 `/emby/System/Info/Public`。',
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: 'http',
                          icon: Icon(Icons.http_rounded),
                          label: Text('HTTP'),
                        ),
                        ButtonSegment<String>(
                          value: 'https',
                          icon: Icon(Icons.lock_rounded),
                          label: Text('HTTPS'),
                        ),
                      ],
                      selected: {_protocol},
                      onSelectionChanged: (value) {
                        setState(() {
                          _protocol = value.first;
                        });
                        _handleEndpointChanged();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '地址',
                      hintText: '192.168.1.100 或 media.example.com',
                      prefixIcon: Icon(Icons.language_rounded),
                    ),
                    validator: _validateAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '端口',
                      hintText: '8096',
                      prefixIcon: Icon(Icons.numbers_rounded),
                    ),
                    validator: _validatePort,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FileSourceFormSection(
              title: '账号凭据',
              subtitle: '保存后应用会用这里的账号进行正式认证与媒体数据拉取。',
              child: Column(
                children: [
                  TextFormField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_rounded),
                    ),
                    validator: _validateRequiredText,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_rounded),
                    ),
                    validator: _validateRequiredText,
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child:
                  _connectionTestState == _ConnectionTestState.idle &&
                      (_connectionFeedback == null ||
                          _connectionFeedback!.trim().isEmpty)
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey<String>(
                        'feedback-${_connectionTestState.name}-${_connectionFeedback ?? ''}',
                      ),
                      padding: const EdgeInsets.only(top: 12),
                      child: _ConnectionFeedbackCard(
                        state: _connectionTestState,
                        message: _connectionFeedback ?? '',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalManager(BuildContext context) {
    return KeyedSubtree(
      key: const ValueKey<String>('local-manager'),
      child: LocalFileSourceForm(
        key: _localFormKey,
        initialPaths: _localPaths,
        initialName: _localNameController.text.isNotEmpty
            ? _localNameController.text
            : widget.initialServer?.name,
        onBack: _isEditMode
            ? null
            : () {
                setState(() {
                  _selectedType = null;
                  _connectionTestState = _ConnectionTestState.idle;
                  _connectionFeedback = null;
                });
              },
      ),
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _showValidation = true;
    });
    final isValid = _embyFormKey.currentState?.validate() ?? false;
    if (!isValid || _selectedType != MediaServiceType.emby) {
      return;
    }

    final config = _buildEmbyConfig();
    final endpointSignature = _endpointSignature(config);

    setState(() {
      _isTestingConnection = true;
      _connectionTestState = _ConnectionTestState.idle;
      _connectionFeedback = '正在检查服务器是否可达...';
    });

    try {
      final tester = context.read<IMediaConnectionTester>();
      final result = await tester.testConnection(config);
      setState(() {
        _connectionTestState = result.success
            ? _ConnectionTestState.success
            : _ConnectionTestState.failure;
        _connectionFeedback = result.displayMessage;
        if (result.success) {
          _lastSuccessfulEndpointSignature = endpointSignature;
        } else {
          _lastSuccessfulEndpointSignature = null;
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_connectionFeedback!)));
    } finally {
      if (mounted) {
        setState(() {
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final appProvider = context.read<AppProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() {
      _showValidation = true;
    });

    if (_selectedType == MediaServiceType.local) {
      final localFormState = _localFormKey.currentState;
      if (localFormState == null) return;

      if (!localFormState.isValid) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('请至少添加一个视频文件夹'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final config = localFormState.buildConfig();
      final customName = localFormState.name;
      debugPrint('[AddSource][Sheet] ===== 提交本地文件源 =====');
      debugPrint('[AddSource][Sheet] 路径数: ${config.localPaths.length}, 名称: ${customName ?? "默认"}, 编辑: $_isEditMode');
      for (var i = 0; i < config.localPaths.length; i++) {
        debugPrint('[AddSource][Sheet]   路径[$i]: ${config.localPaths[i]}');
      }

      setState(() {
        _isSaving = true;
      });

      try {
        debugPrint('[AddSource][Sheet] 步骤1: 调用 AppProvider.saveConfiguredServer...');
        await appProvider.saveConfiguredServer(
          customName: customName,
          config: config,
          editingServerId: _editingServerId,
        );
        debugPrint('[AddSource][Sheet] 步骤1: saveConfiguredServer 完成');
        if (!mounted) return;

        // Trigger scan. The onScanCompleted callback (set in main.dart)
        // will refresh the media library when the scan finishes.
        debugPrint('[AddSource][Sheet] 步骤2: 触发 runScan, 路径=${config.localPaths}');
        unawaited(context.read<IMediaMaintainer>().runScan(config.localPaths));

        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(_isEditMode ? '服务器已更新' : '媒体源已添加')),
        );
        navigator.pop();
      } catch (error) {
        debugPrint('[LocalMedia][Sheet] 保存失败: $error');
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(_describeSaveError(error))),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
      }
      return;
    }

    final isValid = _embyFormKey.currentState?.validate() ?? false;
    if (!isValid || _selectedType != MediaServiceType.emby) {
      return;
    }

    final config = _buildEmbyConfig();

    setState(() {
      _isSaving = true;
    });

    try {
      debugPrint('[AddSource][Sheet] ===== 提交 Emby 服务器 =====');
      debugPrint('[AddSource][Sheet] 地址: $_protocol://${_addressController.text.trim()}:${_portController.text.trim()}, 编辑: $_isEditMode');
      debugPrint('[AddSource][Sheet] 步骤1: 调用 AppProvider.saveConfiguredServer...');
      await appProvider.saveConfiguredServer(
        customName: _serverNameController.text.trim(),
        config: config,
        editingServerId: _editingServerId,
      );
      debugPrint('[AddSource][Sheet] 步骤1: saveConfiguredServer 完成');
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(_isEditMode ? '服务器已更新' : '服务器已添加')),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(_describeSaveError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  MediaServiceConfig _buildEmbyConfig() {
    final address = _addressController.text.trim();
    final port = _portController.text.trim();
    return MediaServiceConfig(
      type: MediaServiceType.emby,
      serverUrl: '$_protocol://$address:$port',
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  String _endpointSignature(MediaServiceConfig config) {
    return '${config.type.name}:${config.normalizedServerUrl.toLowerCase()}';
  }

  void _handleEndpointChanged() {
    final currentSignature = _selectedType == MediaServiceType.emby
        ? _endpointSignature(_buildEmbyConfig())
        : null;
    if (currentSignature != _lastSuccessfulEndpointSignature &&
        (_connectionTestState != _ConnectionTestState.idle ||
            _connectionFeedback != null)) {
      setState(() {
        _connectionTestState = _ConnectionTestState.idle;
        _connectionFeedback = null;
      });
    }
  }

  String? _validateRequiredText(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '此项不能为空';
    }
    return null;
  }

  String? _validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入服务器地址';
    }
    return null;
  }

  String? _validatePort(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '请输入端口';
    }

    final port = int.tryParse(value.trim());
    if (port == null || port <= 0 || port > 65535) {
      return '请输入有效端口';
    }

    return null;
  }

  String _describeSaveError(Object error) {
    return '保存失败，请稍后重试';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.canSave,
    required this.isTestingConnection,
    required this.isSaving,
    required this.isEditMode,
    required this.onTestConnection,
    required this.onSave,
  });

  final bool canSave;
  final bool isTestingConnection;
  final bool isSaving;
  final bool isEditMode;
  final VoidCallback? onTestConnection;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isSaving ? null : onTestConnection,
            icon: isTestingConnection
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded),
            label: Text(isTestingConnection ? '连接测试中' : '测试连接'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: canSave ? onSave : null,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(isEditMode ? Icons.save_rounded : Icons.add_rounded),
            label: Text(
              isSaving
                  ? (isEditMode ? '保存中' : '添加中')
                  : (isEditMode ? '保存修改' : '添加服务器'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionFeedbackCard extends StatelessWidget {
  const _ConnectionFeedbackCard({required this.state, required this.message});

  final _ConnectionTestState state;
  final String message;

  @override
  Widget build(BuildContext context) {
    final isSuccess = state == _ConnectionTestState.success;
    final accentColor = isSuccess
        ? const Color(0xFF3DDC97)
        : const Color(0xFFFF8A65);

    return AppSurfaceCard(
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: accentColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
