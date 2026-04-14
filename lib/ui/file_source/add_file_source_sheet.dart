import 'package:flutter/material.dart';

import '../../domain/entities/media_service_config.dart';
import '../../providers/app_provider.dart';
import 'emby_file_source_form.dart';
import 'file_source_type_selector.dart';

class FileSourceDraft {
  const FileSourceDraft({required this.name, required this.config});

  final String name;
  final MediaServiceConfig config;
}

class AddFileSourceSheet extends StatefulWidget {
  const AddFileSourceSheet({super.key, required this.onSubmitted});

  final ValueChanged<FileSourceDraft> onSubmitted;

  @override
  State<AddFileSourceSheet> createState() => _AddFileSourceSheetState();
}

class _AddFileSourceSheetState extends State<AddFileSourceSheet> {
  final _embyFormKey = GlobalKey<FormState>();
  final _serverNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8096');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  MediaServiceType? _selectedType;
  String _protocol = 'http';
  bool _showValidation = false;

  @override
  void dispose() {
    _serverNameController.dispose();
    _addressController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedType == null
                          ? '添加文件源'
                          : '配置 ${_selectedType!.displayName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _selectedType == null
                    ? '先选择服务器类型，再填写对应配置。'
                    : '当前把 Emby 的配置拆成独立单元，后面要改单块组件会更轻松。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              if (_selectedType == null)
                FileSourceTypeSelector(
                  onSelected: (type) {
                    setState(() {
                      _selectedType = type;
                    });
                  },
                )
              else if (_selectedType == MediaServiceType.emby)
                EmbyFileSourceForm(
                  formKey: _embyFormKey,
                  serverNameController: _serverNameController,
                  addressController: _addressController,
                  portController: _portController,
                  usernameController: _usernameController,
                  passwordController: _passwordController,
                  protocol: _protocol,
                  onProtocolChanged: (value) {
                    setState(() {
                      _protocol = value;
                    });
                  },
                  autovalidateMode: _showValidation
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  onBack: () {
                    setState(() {
                      _selectedType = null;
                      _showValidation = false;
                    });
                  },
                  onSubmit: _submitEmbyDraft,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _submitEmbyDraft() {
    setState(() {
      _showValidation = true;
    });
    final isValid = _embyFormKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final address = _addressController.text.trim();
    final port = _portController.text.trim();
    final draft = FileSourceDraft(
      name: _serverNameController.text.trim(),
      config: MediaServiceConfig(
        type: MediaServiceType.emby,
        serverUrl: '$_protocol://$address:$port',
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
    );

    widget.onSubmitted(draft);
    Navigator.of(context).pop();
  }
}
