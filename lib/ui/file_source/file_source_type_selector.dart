import 'package:flutter/material.dart';

import '../../domain/entities/media_service_config.dart';
import '../../providers/app_provider.dart';
import '../atoms/app_surface_card.dart';

class FileSourceTypeSelector extends StatelessWidget {
  const FileSourceTypeSelector({super.key, required this.onSelected});

  final ValueChanged<MediaServiceType> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FileSourceTypeCard(
          type: MediaServiceType.emby,
          enabled: true,
          onTap: () => onSelected(MediaServiceType.emby),
        ),
        const SizedBox(height: 12),
        const _FileSourceTypeCard(type: MediaServiceType.plex, enabled: false),
        const SizedBox(height: 12),
        const _FileSourceTypeCard(
          type: MediaServiceType.jellyfin,
          enabled: false,
        ),
      ],
    );
  }
}

class _FileSourceTypeCard extends StatelessWidget {
  const _FileSourceTypeCard({
    required this.type,
    required this.enabled,
    this.onTap,
  });

  final MediaServiceType type;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(24),
          child: AppSurfaceCard(
            child: Row(
              children: [
                Icon(_iconFor(type), color: Colors.white70),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        enabled ? _descriptionFor(type) : '即将支持',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  enabled
                      ? Icons.arrow_forward_ios_rounded
                      : Icons.schedule_rounded,
                  size: 18,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(MediaServiceType type) {
    return switch (type) {
      MediaServiceType.emby => Icons.video_settings_rounded,
      MediaServiceType.plex => Icons.hub_rounded,
      MediaServiceType.jellyfin => Icons.live_tv_rounded,
    };
  }

  String _descriptionFor(MediaServiceType type) {
    return switch (type) {
      MediaServiceType.emby => '填写 Emby 服务器地址、端口和账户信息',
      MediaServiceType.plex => '添加 Plex 文件源',
      MediaServiceType.jellyfin => '添加 Jellyfin 文件源',
    };
  }
}
