import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart' show Player;

import '../../../domain/entities/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/user_data_provider.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/duration_formatter.dart';
import '../../atoms/meow_video_player.dart';

class TabletPlayerScreen extends StatefulWidget {
  const TabletPlayerScreen({
    super.key,
    required this.maxWidth,
    required this.mediaItem,
    required this.selectedServer,
    required this.savedProgress,
    required this.initialPosition,
    required this.onPlaybackStatusChanged,
    this.playUrlOverride,
    this.onShowTrackSelector,
    this.selectionRequest,
  });

  final double maxWidth;
  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final MediaPlaybackProgress? savedProgress;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged onPlaybackStatusChanged;
  final String? playUrlOverride;
  final VoidCallback? onShowTrackSelector;
  final Object? selectionRequest; // removed feature; keep param slot stable

  @override
  State<TabletPlayerScreen> createState() => _TabletPlayerScreenState();
}

class _TabletPlayerScreenState extends State<TabletPlayerScreen> {
  MeowVideoPlaybackStatus? _latestStatus;
  Player? _player;
  late final UserDataProvider _udp;

  bool get _hasPlayableUrl {
    final playUrl = widget.mediaItem.playUrl;
    return playUrl != null && playUrl.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _udp = context.read<UserDataProvider>();
  }

  // Subtitle feature removed for stability

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    _latestStatus = status;
    if (status.isInitialized) {
      _udp.updatePlaybackProgressMemoryOnlyForItem(
        widget.mediaItem,
        position: status.position,
        duration: status.duration,
      );
    }
    widget.onPlaybackStatusChanged(status);
  }

  Future<bool> _stopAndSync() async {
    final item = widget.mediaItem;
    final status = _latestStatus;
    if (status != null && status.isInitialized) {
      _udp.updatePlaybackProgressMemoryOnlyForItem(
        item,
        position: status.position,
        duration: status.duration,
      );
    }
    final p = _player;
    if (p != null) {
      try {
        await p.stop();
      } catch (_) {}
    }
    await _udp.syncProgressToServerForItem(item);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final sideWidth = widget.maxWidth >= 1100 ? 340.0 : 300.0;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        final navigator = Navigator.of(context);
        final ok = await _stopAndSync();
        if (!didPop && ok) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('播放中')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (_hasPlayableUrl)
                        MeowVideoPlayer(
                          key: ObjectKey(widget.mediaItem.dataSourceId),
                          url:
                              widget.playUrlOverride ??
                              widget.mediaItem.playUrl!,
                          autoPlay: true,
                          initialPosition: widget.initialPosition,
                          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
                          onPlayerCreated: (p) async {
                            _player = p;
                          },
                          overlayCcButton: widget.onShowTrackSelector != null,
                          onTapCc: widget.onShowTrackSelector,
                        )
                      else
                        _UnavailablePlayerCard(title: widget.mediaItem.title),
                      if (widget.onShowTrackSelector != null) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: widget.onShowTrackSelector,
                            icon: const Icon(Icons.library_music_outlined),
                            label: const Text('音轨/字幕'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        widget.mediaItem.title,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      if (widget.mediaItem.originalTitle.isNotEmpty &&
                          widget.mediaItem.originalTitle !=
                              widget.mediaItem.title) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.mediaItem.originalTitle,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                      const SizedBox(height: 18),
                      AppSurfaceCard(
                        child: Text(
                          widget.mediaItem.overview.isNotEmpty
                              ? widget.mediaItem.overview
                              : '这部作品暂时没有更多介绍。',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: sideWidth,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _PlaybackInfoCard(
                        selectedServer: widget.selectedServer,
                        playbackProgress: widget.savedProgress,
                        initialPosition: widget.initialPosition,
                      ),
                      const SizedBox(height: 16),
                      _PlaybackHintCard(
                        hasSavedProgress: widget.savedProgress != null,
                        overview: widget.mediaItem.overview,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 仅负责尽力停止与释放底层资源；状态同步在 PopScope 中完成
    final p = _player;
    if (p != null) {
      try {
        // ignore: discarded_futures
        p.stop();
      } catch (_) {}
      try {
        p.dispose();
      } catch (_) {}
    }
    super.dispose();
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
                ? '播放中会持续回写进度，适合在平板和手机之间无缝续播。'
                : '这次播放会自动开始记录进度，之后可以直接恢复到上次位置。',
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
