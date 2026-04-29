import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/services/storage_permission_service.dart';
import '../../domain/entities/media_service_config.dart';
import '../atoms/app_surface_card.dart';
import 'file_source_form_section.dart';

class LocalFileSourceForm extends StatefulWidget {
  const LocalFileSourceForm({
    super.key,
    this.initialPaths = const [],
    this.initialName,
    this.onScanRequested,
  });

  final List<String> initialPaths;
  final String? initialName;
  final VoidCallback? onScanRequested;

  @override
  State<LocalFileSourceForm> createState() => LocalFileSourceFormState();
}

class LocalFileSourceFormState extends State<LocalFileSourceForm> {
  final _nameController = TextEditingController();
  final List<String> _paths = [];

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName ?? '';
    _paths.addAll(widget.initialPaths);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    if (!await StoragePermissionService.hasFullStorageAccess()) {
      if (!mounted) return;
      final granted = await StoragePermissionService.requestStoragePermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要存储权限才能访问文件夹，请在系统设置中授予"所有文件访问"权限。'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && path.isNotEmpty && !_paths.contains(path)) {
      setState(() {
        _paths.add(path);
      });
    }
  }

  void _removePath(int index) {
    setState(() {
      _paths.removeAt(index);
    });
  }

  MediaServiceConfig buildConfig() {
    return MediaServiceConfig(
      type: MediaServiceType.local,
      serverUrl: '',
      localPaths: List<String>.from(_paths),
    );
  }

  bool get isValid => _paths.isNotEmpty;

  String? get name => _nameController.text.trim().isNotEmpty
      ? _nameController.text.trim()
      : null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: null,
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('更换类型'),
            ),
            const Spacer(),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  '本地视频',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FileSourceFormSection(
          title: '基础信息',
          subtitle: '给这个媒体源起一个名字，方便识别。',
          child: TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '例如：本机视频库',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FileSourceFormSection(
          title: '视频文件夹',
          subtitle: '选择包含视频文件的文件夹。支持递归扫描子目录。',
          child: Column(
            children: [
              ...List.generate(_paths.length, (i) {
                return Padding(
                  padding: EdgeInsets.only(bottom: i < _paths.length - 1 ? 8 : 0),
                  child: _PathChip(
                    path: _paths[i],
                    onRemove: () => _removePath(i),
                  ),
                );
              }),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: const Text('添加文件夹'),
                ),
              ),
              if (_paths.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '至少需要选择一个文件夹',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
                  ),
                ),
            ],
          ),
        ),
        if (widget.onScanRequested != null) ...[
          const SizedBox(height: 12),
          FileSourceFormSection(
            title: '扫描媒体库',
            subtitle: '保存配置后可以立即扫描文件夹中的视频文件。',
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: widget.onScanRequested,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('扫描媒体库'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PathChip extends StatelessWidget {
  const _PathChip({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Row(
        children: [
          const Icon(Icons.folder_rounded, color: Colors.white54, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, color: Colors.white38, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
