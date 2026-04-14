import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import 'package:media_kit/media_kit.dart' show Player;
import '../../../providers/app_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/duration_formatter.dart';
import '../../atoms/meow_video_player.dart';

class MobilePlayerScreen extends StatefulWidget {
  const MobilePlayerScreen({
    super.key,
    required this.mediaItem,
    required this.selectedServer,
    required this.savedProgress,
    required this.initialPosition,
    required this.onPlaybackStatusChanged,
    this.playUrlOverride,
    this.onShowTrackSelector,
    this.selectionRequest,
    this.subtitleUri,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.disableSubtitleTrack = false,
  });

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final MediaPlaybackProgress? savedProgress;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged onPlaybackStatusChanged;
  final String? playUrlOverride;
  final VoidCallback? onShowTrackSelector;
  // 播放页移除音轨/字幕选择
  final Object? selectionRequest;
  final String? subtitleUri;
  final String? subtitleTitle;
  final String? subtitleLanguage;
  final bool disableSubtitleTrack;

  @override
  State<MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends State<MobilePlayerScreen> {
  MeowVideoPlaybackStatus? _latestStatus;
  Player? _player;
  late final UserDataProvider _udp;

  @override
  void initState() {
    super.initState();
    // 预先抓取 Provider 引用，避免在 dispose/异步回调里向上查找祖先导致断言
    _udp = context.read<UserDataProvider>();
  }

  // 播放页移除本地字幕切换

  bool get _hasPlayableUrl {
    final playUrl = widget.mediaItem.playUrl;
    return playUrl != null && playUrl.isNotEmpty;
  }

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    _latestStatus = status;
    // 仅内存更新，切断重绘循环
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
    final capturedItem = widget.mediaItem;
    final status = _latestStatus;
    if (status != null && status.isInitialized) {
      _udp.updatePlaybackProgressMemoryOnlyForItem(
        capturedItem,
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
    await _udp.syncProgressToServerForItem(capturedItem);
    return true;
  }

  @override
  void dispose() {
    // 退出时：先尝试同步最后位置
    final status = _latestStatus;
    if (status != null && status.isInitialized) {
      _udp.updatePlaybackProgressMemoryOnlyForItem(
        widget.mediaItem,
        position: status.position,
        duration: status.duration,
      );
    }
    // 尽量先停止音频流并释放 VideoController，避免退出后残留音轨
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
    _udp.syncProgressToServerForItem(widget.mediaItem);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 支持预测性返回：先停音频/同步，再退出
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        final navigator = Navigator.of(context);
        final ok = await _stopAndSync();
        if (!didPop && ok && mounted) navigator.pop();
      },
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isLandscape = orientation == Orientation.landscape;

          if (isLandscape) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: _buildPlayer()),
            );
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(widget.mediaItem.title),
              centerTitle: true,
              backgroundColor: AppTheme.backgroundColor,
              surfaceTintColor: Colors.transparent,
            ),
            body: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _buildPlayer(),
                                // Track selector under the player
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
                _buildTitleSection(context),
                const SizedBox(height: 18),
                _PlaybackInfoCard(
                  selectedServer: widget.selectedServer,
                  playbackProgress: widget.savedProgress,
                  initialPosition: widget.initialPosition,
                ),
                const SizedBox(height: 18),
                _PlaybackHintCard(
                  hasSavedProgress: widget.savedProgress != null,
                  overview: widget.mediaItem.overview,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 抽离播放器构建逻辑
  Widget _buildPlayer() {
    if (!_hasPlayableUrl) {
      return _UnavailablePlayerCard(title: widget.mediaItem.title);
    }
    return MeowVideoPlayer(
      key: ObjectKey(widget.mediaItem.dataSourceId),
      url: widget.playUrlOverride ?? widget.mediaItem.playUrl!,
      autoPlay: true,
      initialPosition: widget.initialPosition,
      onPlaybackStatusChanged: _handlePlaybackStatusChanged,
      onPlayerCreated: (p) async {
        _player = p;
      },
      overlayCcButton: widget.onShowTrackSelector != null,
      onTapCc: widget.onShowTrackSelector,
      subtitleUri: widget.subtitleUri,
      subtitleTitle: widget.subtitleTitle,
      subtitleLanguage: widget.subtitleLanguage,
      disableSubtitleTrack: widget.disableSubtitleTrack,
    );
  }

  // 抽离标题区域逻辑
  Widget _buildTitleSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.mediaItem.title, style: theme.textTheme.headlineMedium),
        if (widget.mediaItem.originalTitle.isNotEmpty &&
            widget.mediaItem.originalTitle != widget.mediaItem.title) ...[
          const SizedBox(height: 8),
          Text(
            widget.mediaItem.originalTitle,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }
}

// --- 以下辅助组件保持不变 ---

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
