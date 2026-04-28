import 'package:flutter/material.dart';

import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../atoms/app_surface_card.dart';

class FileSourceTile extends StatelessWidget {
  const FileSourceTile({
    super.key,
    required this.server,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
  });

  final MediaServerInfo server;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AppSurfaceCard(
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.dns_rounded,
                color: isSelected ? AppTheme.accentColor : Colors.white70,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            server.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (onEdit != null && !server.isPlaceholder) ...[
                          IconButton(
                            onPressed: onEdit,
                            tooltip: '编辑服务器',
                            icon: const Icon(Icons.edit_rounded, size: 18),
                            color: Colors.white70,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                        ],
                        _SourceTypeChip(label: server.type.displayName),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      server.baseUrl.isEmpty ? '还没有可用服务器' : server.baseUrl,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      Text(
                        '当前已选中',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.accentColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTypeChip extends StatelessWidget {
  const _SourceTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
    );
  }
}
