import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart' show Player;

import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/playback_plan.dart';
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
    this.subtitleUri,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.disableSubtitleTrack = false,
    this.playSessionId,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.audioStreams = const [],
  });

  final double maxWidth;
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
  final String? playSessionId;
  final String? mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final List<PlaybackStream> audioStreams;

  @override
  State<TabletPlayerScreen> createState() => _TabletPlayerScreenState();
}

class _TabletPlayerScreenState extends State<TabletPlayerScreen> {
  static const Duration _backgroundSyncInterval = Duration(seconds: 15);
  static const Duration _meaningfulProgressThreshold = Duration(seconds: 5);
  static const Duration _progressRollbackTolerance = Duration(seconds: 3);

  MeowVideoPlaybackStatus? _latestStatus;
  MediaPlaybackProgress? _lastStablePlaybackProgress;
  Player? _player;
  late final UserDataProvider _udp;
  Future<void>? _syncOnExitFuture;
  bool _isExiting = false;
  bool _allowImmediatePop = false;
  bool _hasReportedPlaybackStarted = false;
  DateTime? _lastBackgroundSyncAt;
  int _lastUiProgressSecond = -1;
  int _lastLoggedPlaybackSecond = -1;

  bool get _hasPlayableUrl {
    final playUrl = widget.mediaItem.playUrl;
    return playUrl != null && playUrl.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _udp = context.read<UserDataProvider>();
    _lastStablePlaybackProgress = widget.savedProgress;
  }

  @override
  void didUpdateWidget(covariant TabletPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaItem.dataSourceId != widget.mediaItem.dataSourceId ||
        oldWidget.playUrlOverride != widget.playUrlOverride ||
        oldWidget.playSessionId != widget.playSessionId ||
        oldWidget.mediaSourceId != widget.mediaSourceId) {
      _hasReportedPlaybackStarted = false;
    }
  }

  // 播放页移除本地字幕切换

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    if (_isExiting ||
        _shouldIgnoreZeroProgressUpdate(status) ||
        _shouldIgnoreRegressiveProgressUpdate(status)) {
      return;
    }
    _latestStatus = status;
    if (status.isInitialized) {
      _lastStablePlaybackProgress = MediaPlaybackProgress(
        position: status.position,
        duration: status.duration,
      );
      _refreshPlaybackInfoUi(status);
      _logPlaybackProgress(status);
      _udp.updatePlaybackProgressForItem(
        widget.mediaItem,
        position: status.position,
        duration: status.duration,
      );
      _maybeSyncProgressInBackground(status);
    }
    widget.onPlaybackStatusChanged(status);
  }

  Future<void> _handlePlaybackStarted(MeowVideoPlaybackStatus status) async {
    if (_isExiting || _hasReportedPlaybackStarted) {
      return;
    }
    _hasReportedPlaybackStarted = true;
    final effectivePosition = status.position > Duration.zero
        ? status.position
        : widget.initialPosition;
    await _udp.startPlaybackForItem(
      widget.mediaItem,
      position: effectivePosition,
      duration: status.duration,
      playSessionId: widget.playSessionId,
      mediaSourceId: widget.mediaSourceId,
      audioStreamIndex: widget.audioStreamIndex,
      subtitleStreamIndex: widget.subtitleStreamIndex,
    );
  }

  bool _shouldIgnoreZeroProgressUpdate(MeowVideoPlaybackStatus status) {
    if (status.position > Duration.zero) {
      return false;
    }

    final latestPosition =
        _latestStatus?.position ?? _lastStablePlaybackProgress?.position;
    return latestPosition != null &&
        latestPosition > _meaningfulProgressThreshold;
  }

  bool _shouldIgnoreRegressiveProgressUpdate(MeowVideoPlaybackStatus status) {
    final latestPosition =
        _latestStatus?.position ??
        _lastStablePlaybackProgress?.position ??
        widget.savedProgress?.position;
    if (latestPosition == null ||
        latestPosition <= _meaningfulProgressThreshold ||
        status.position >= latestPosition) {
      return false;
    }

    return latestPosition - status.position > _progressRollbackTolerance;
  }

  void _refreshPlaybackInfoUi(MeowVideoPlaybackStatus status) {
    final nextSecond = status.position.inSeconds;
    if (_lastUiProgressSecond == nextSecond) {
      return;
    }
    _lastUiProgressSecond = nextSecond;
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _logPlaybackProgress(MeowVideoPlaybackStatus status) {
    final currentSecond = status.position.inSeconds;
    if (currentSecond <= 0 ||
        currentSecond == _lastLoggedPlaybackSecond ||
        currentSecond % 10 != 0) {
      return;
    }
    _lastLoggedPlaybackSecond = currentSecond;
    debugPrint(
      '[Resume][Tablet][Playing] item=${widget.mediaItem.dataSourceId} '
      'position=${status.position.inMilliseconds}ms '
      'duration=${status.duration.inMilliseconds}ms',
    );
  }

  void _maybeSyncProgressInBackground(MeowVideoPlaybackStatus status) {
    if (!status.isPlaying || status.position <= Duration.zero) {
      return;
    }

    final now = DateTime.now();
    final lastSyncAt = _lastBackgroundSyncAt;
    if (lastSyncAt != null &&
        now.difference(lastSyncAt) < _backgroundSyncInterval) {
      return;
    }

    _lastBackgroundSyncAt = now;
    // ignore: discarded_futures
    _udp.syncProgressToServerForItem(
      widget.mediaItem,
      position: status.position,
      duration: status.duration,
      playSessionId: widget.playSessionId,
      mediaSourceId: widget.mediaSourceId,
      audioStreamIndex: widget.audioStreamIndex,
      subtitleStreamIndex: widget.subtitleStreamIndex,
    );
  }

  Future<void> _syncOnExit() {
    final existing = _syncOnExitFuture;
    if (existing != null) {
      return existing;
    }

    final future = _performSyncOnExit();
    _syncOnExitFuture = future;
    return future;
  }

  Player? _detachPlayer() {
    final player = _player;
    _player = null;
    return player;
  }

  Future<void> _disposePlayerSafely(Player player) async {
    try {
      player.dispose();
    } catch (_) {}
  }

  Future<void> _stopPlayerSafely(Player player) async {
    try {
      await player.stop();
    } catch (_) {}
  }

  void _applyLocalProgressOnExit() {
    final status = _latestStatus;
    if (status == null ||
        !status.isInitialized ||
        status.position <= Duration.zero) {
      return;
    }
    _lastStablePlaybackProgress = MediaPlaybackProgress(
      position: status.position,
      duration: status.duration,
    );
    _udp.updatePlaybackProgressForItem(
      widget.mediaItem,
      position: status.position,
      duration: status.duration,
      notify: true,
    );
  }

  Future<void> _performSyncOnExit() async {
    final item = widget.mediaItem;
    final status = _latestStatus;
    final player = _detachPlayer();
    debugPrint(
      '[Resume][Tablet][Exit] item=${item.dataSourceId} '
      'position=${status?.position.inMilliseconds ?? 0}ms '
      'duration=${status?.duration.inMilliseconds ?? 0}ms '
      'sync=start',
    );
    _applyLocalProgressOnExit();
    try {
      if (player != null) {
        await _stopPlayerSafely(player);
      }
      await _udp.stopPlaybackForItem(
        item,
        position: status?.position ?? Duration.zero,
        duration: status?.duration ?? Duration.zero,
        playSessionId: widget.playSessionId,
        mediaSourceId: widget.mediaSourceId,
        audioStreamIndex: widget.audioStreamIndex,
        subtitleStreamIndex: widget.subtitleStreamIndex,
      );
      debugPrint(
        '[Resume][Tablet][Exit] item=${item.dataSourceId} '
        'stopped=done',
      );
    } finally {
      if (player != null) {
        await _disposePlayerSafely(player);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideWidth = widget.maxWidth >= 1100 ? 340.0 : 300.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (_allowImmediatePop) {
          _allowImmediatePop = false;
          return;
        }
        final navigator = Navigator.of(context);
        _isExiting = true;
        // ignore: discarded_futures
        _syncOnExit().whenComplete(() {
          if (!mounted) {
            return;
          }
          _allowImmediatePop = true;
          navigator.pop();
        });
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
                          onPlaybackStarted: _handlePlaybackStarted,
                          onPlayerCreated: (p) async {
                            _player = p;
                          },
                          overlayCcButton: widget.onShowTrackSelector != null,
                          onTapCc: widget.onShowTrackSelector,
                          subtitleUri: widget.subtitleUri,
                          subtitleTitle: widget.subtitleTitle,
                          subtitleLanguage: widget.subtitleLanguage,
                          disableSubtitleTrack: widget.disableSubtitleTrack,
                          audioStreamIndex: widget.audioStreamIndex,
                          audioStreams: widget.audioStreams,
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
                        playbackProgress: _currentPlaybackProgress,
                        initialPosition: widget.initialPosition,
                      ),
                      const SizedBox(height: 16),
                      _PlaybackHintCard(
                        hasSavedProgress: _currentPlaybackProgress != null,
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
    // ignore: discarded_futures
    _syncOnExit();
    final detachedPlayer = _detachPlayer();
    if (detachedPlayer != null) {
      // ignore: discarded_futures
      _disposePlayerSafely(detachedPlayer);
    }
    super.dispose();
  }

  MediaPlaybackProgress? get _currentPlaybackProgress {
    if (_isExiting) {
      return _lastStablePlaybackProgress ?? widget.savedProgress;
    }
    final status = _latestStatus;
    if (status != null && status.isInitialized) {
      return MediaPlaybackProgress(
        position: status.position,
        duration: status.duration,
      );
    }
    return _lastStablePlaybackProgress ?? widget.savedProgress;
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
