import 'package:flutter/material.dart';

import 'file_source_form_section.dart';

class EmbyFileSourceForm extends StatelessWidget {
  const EmbyFileSourceForm({
    super.key,
    required this.formKey,
    required this.serverNameController,
    required this.addressController,
    required this.portController,
    required this.usernameController,
    required this.passwordController,
    required this.protocol,
    required this.onProtocolChanged,
    required this.onSubmit,
    required this.onBack,
    this.autovalidateMode = AutovalidateMode.disabled,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController serverNameController;
  final TextEditingController addressController;
  final TextEditingController portController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String protocol;
  final ValueChanged<String> onProtocolChanged;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      autovalidateMode: autovalidateMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('更换类型'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加 Emby'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FileSourceFormSection(
            title: '名称',
            subtitle: '用于在文件源列表和切换菜单里识别这个服务器。',
            child: TextFormField(
              controller: serverNameController,
              decoration: const InputDecoration(
                labelText: '服务器名称',
                hintText: '例如：家里 Emby',
              ),
              validator: _validateRequiredText,
            ),
          ),
          const SizedBox(height: 12),
          FileSourceFormSection(
            title: '连接信息',
            subtitle: '将协议、地址和端口拆开，后续单独调整会更方便。',
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: 'http', label: Text('HTTP')),
                      ButtonSegment<String>(
                        value: 'https',
                        label: Text('HTTPS'),
                      ),
                    ],
                    selected: {protocol},
                    onSelectionChanged: (value) {
                      onProtocolChanged(value.first);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: addressController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '地址',
                    hintText: '192.168.1.100 或 media.example.com',
                  ),
                  validator: _validateAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '8096',
                  ),
                  validator: _validatePort,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FileSourceFormSection(
            title: '账号信息',
            subtitle: '当前 Emby 连接需要用户名和密码。',
            child: Column(
              children: [
                TextFormField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: '用户名'),
                  validator: _validateRequiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  validator: _validateRequiredText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
}
