import 'package:flutter/material.dart';

import '../../../models/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/duration_formatter.dart';
import '../../atoms/meow_video_player.dart';

class MobilePlayerScreen extends StatelessWidget {
  const MobilePlayerScreen({
    super.key,
    required this.mediaItem,
    required this.selectedServer,
    required this.savedProgress,
    required this.initialPosition,
    required this.onPlaybackStatusChanged,
  });

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final MediaPlaybackProgress? savedProgress;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged onPlaybackStatusChanged;

  bool get _hasPlayableUrl {
    final playUrl = mediaItem.playUrl;
    return playUrl != null && playUrl.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('播放中')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_hasPlayableUrl)
            MeowVideoPlayer(
              url: mediaItem.playUrl!,
              autoPlay: true,
              initialPosition: initialPosition,
              onPlaybackStatusChanged: onPlaybackStatusChanged,
            )
          else
            _UnavailablePlayerCard(title: mediaItem.title),
          const SizedBox(height: 20),
          Text(mediaItem.title, style: theme.textTheme.headlineMedium),
          if (mediaItem.originalTitle.isNotEmpty &&
              mediaItem.originalTitle != mediaItem.title) ...[
            const SizedBox(height: 8),
            Text(mediaItem.originalTitle, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 18),
          _PlaybackInfoCard(
            selectedServer: selectedServer,
            playbackProgress: savedProgress,
            initialPosition: initialPosition,
          ),
          const SizedBox(height: 18),
          _PlaybackHintCard(
            hasSavedProgress: savedProgress != null,
            overview: mediaItem.overview,
          ),
        ],
      ),
    );
  }
}

class _PlaybackInfoCard extends StatelessWidget {
  const _PlaybackInfoCard({
    required this.selectedServer,
    required this.playbackProgress,
    required this.initialPosition,
  });

  final MediaServerInfo selectedServer;
  final MediaPlaybackProgress? playbackProgress;
  final Duration initialPosition;

  @override
  Widget build(BuildContext context) {
    final hasResume = initialPosition > Duration.zero;

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('播放状态', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          _InfoLine(
            icon: Icons.dns_rounded,
            label: '当前线路',
            value: '${selectedServer.name} · ${selectedServer.region}',
          ),
          _InfoLine(
            icon: Icons.restore_rounded,
            label: '续播起点',
            value: hasResume ? formatDurationLabel(initialPosition) : '从头开始',
          ),
          _InfoLine(
            icon: Icons.timelapse_rounded,
            label: '当前记录',
            value: playbackProgress != null
                ? '${formatDurationLabel(playbackProgress!.position)} / '
                      '${formatDurationLabel(playbackProgress!.duration)}'
                : '尚未生成播放记录',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _PlaybackHintCard extends StatelessWidget {
  const _PlaybackHintCard({
    required this.hasSavedProgress,
    required this.overview,
  });

  final bool hasSavedProgress;
  final String overview;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasSavedProgress ? '已启用续播' : '首次播放',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            hasSavedProgress
                ? '播放器会在播放中自动保存进度，返回详情页后会继续显示最新续播位置。'
                : '这次播放会自动开始记录进度，退出后你可以从上次位置继续观看。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (overview.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(overview, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailablePlayerCard extends StatelessWidget {
  const _UnavailablePlayerCard({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: AppSurfaceCard(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link_off_rounded, size: 42, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              '$title 暂无可用播放地址',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '请先为这部作品配置可用的 playUrl，再进入播放页。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
