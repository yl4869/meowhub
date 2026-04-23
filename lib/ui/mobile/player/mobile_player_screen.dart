import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart'
    as progress_bar;
import 'package:media_kit/media_kit.dart' show Player;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../atoms/duration_formatter.dart';
import '../../atoms/meow_video_player.dart';

class MobilePlayerScreen extends StatefulWidget {
  const MobilePlayerScreen({
    super.key,
    required this.mediaItem,
    required this.selectedServer,
    required this.savedProgress,
    required this.initialPosition,
    required this.isTranscoding,
    required this.onPlaybackStatusChanged,
    this.onServerSeekRequested,
    this.playUrlOverride,
    this.onShowTrackSelector,
    this.resolutionOptions = const [],
    this.selectedResolution,
    this.onResolutionSelected,
    this.selectionRequest,
    this.subtitleUri,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.disableSubtitleTrack = false,
    this.playSessionId,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final MediaPlaybackProgress? savedProgress;
  final Duration initialPosition;
  final bool isTranscoding;
  final MeowVideoPlaybackStatusChanged onPlaybackStatusChanged;
  final Future<void> Function(Duration target)? onServerSeekRequested;
  final String? playUrlOverride;
  final VoidCallback? onShowTrackSelector;
  final List<PlayerResolutionOption> resolutionOptions;
  final PlayerResolutionOption? selectedResolution;
  final Future<void> Function(PlayerResolutionOption)? onResolutionSelected;
  final Object? selectionRequest;
  final String? subtitleUri;
  final String? subtitleTitle;
  final String? subtitleLanguage;
  final bool disableSubtitleTrack;
  final String? playSessionId;
  final String? mediaSourceId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  @override
  State<MobilePlayerScreen> createState() => _MobilePlayerScreenState();
}

class _MobilePlayerScreenState extends State<MobilePlayerScreen> {
  static const Duration _backgroundSyncInterval = Duration(seconds: 15);
  static const Duration _exitSyncTimeout = Duration(seconds: 8);
  static const Duration _initialSeekStabilityTolerance = Duration(seconds: 2);
  static const Duration _playbackStartStabilityThreshold = Duration(seconds: 1);
  static const Duration _meaningfulProgressThreshold = Duration(seconds: 5);
  static const Duration _progressRollbackTolerance = Duration(seconds: 3);
  static const Duration _manualSeekTargetTolerance = Duration(seconds: 15);
  static const Duration _controlsAutoHideDelay = Duration(seconds: 3);
  static const double _progressBarTouchHeight = 30;
  static const List<double> _playbackSpeeds = [1.0, 1.25, 1.5, 2.0];

  final GlobalKey _playerBoundaryKey = GlobalKey();

  MeowVideoPlaybackStatus? _latestStatus;
  MediaPlaybackProgress? _lastStablePlaybackProgress;
  Player? _player;
  late final UserDataProvider _udp;
  Future<void>? _syncOnExitFuture;
  bool _isExiting = false;
  bool _allowImmediatePop = false;
  bool _controlsVisible = true;
  bool _isLocked = false;
  bool _isScrubbing = false;
  bool _isInitialSeeking = true;
  bool _hasReportedPlaybackStarted = false;
  Duration? _pendingManualSeekTarget;
  _PlayerOptionPanel? _activeOptionPanel;
  double _currentSpeed = 1.0;
  double? _scrubValue;
  String? _centerToastText;
  DateTime? _lastBackgroundSyncAt;
  int _lastUiProgressSecond = -1;
  int _lastLoggedPlaybackSecond = -1;
  Timer? _controlsHideTimer;
  Timer? _centerToastTimer;

  @override
  void initState() {
    super.initState();
    _udp = context.read<UserDataProvider>();
    _lastStablePlaybackProgress = widget.savedProgress;
    _isInitialSeeking = true;
    // ignore: discarded_futures
    _enterImmersiveLandscapeMode();
    _scheduleControlsAutoHide();
  }

  @override
  void didUpdateWidget(covariant MobilePlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaItem.dataSourceId != widget.mediaItem.dataSourceId ||
        oldWidget.playUrlOverride != widget.playUrlOverride ||
        oldWidget.playSessionId != widget.playSessionId ||
        oldWidget.mediaSourceId != widget.mediaSourceId) {
      _hasReportedPlaybackStarted = false;
      _isInitialSeeking = true;
      _pendingManualSeekTarget = null;
    }
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _centerToastTimer?.cancel();
    // ignore: discarded_futures
    _syncOnExit();
    final detachedPlayer = _detachPlayer();
    if (detachedPlayer != null) {
      // ignore: discarded_futures
      _disposePlayerSafely(detachedPlayer);
    }
    // ignore: discarded_futures
    _restoreSystemUi();
    super.dispose();
  }

  // 切换横竖屏
  Future<void> _toggleOrientation() async {
    _handleScreenInteraction(); // 保持控制条显示

    // 检查当前方向
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    if (isPortrait) {
      // 切换到横屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _showCenterToast('已切换至横屏');
    } else {
      // 切换到竖屏
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      _showCenterToast('已切换至竖屏');
    }
  }

  Future<void> _enterImmersiveLandscapeMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  bool get _hasPlayableUrl {
    final playUrl = widget.mediaItem.playUrl;
    return playUrl != null && playUrl.isNotEmpty;
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

  Duration get _displayPosition {
    final current = _currentPlaybackProgress?.position ?? Duration.zero;
    if (_scrubValue == null || _currentPlaybackProgress == null) {
      return current;
    }
    final duration = _currentPlaybackProgress!.duration;
    return duration * _scrubValue!;
  }

  Duration get _displayDuration {
    return _currentPlaybackProgress?.duration ?? Duration.zero;
  }

  bool get _isPlaying => _latestStatus?.isPlaying ?? false;

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    final isManualSeekAction = _consumeManualSeekAllowance(status.position);
    if (_shouldShieldInitialProgress(status)) {
      return;
    }

    if (_isScrubbing || isManualSeekAction) {
      _applyValidStatusUpdate(status, allowPositionRegression: true);
      return;
    }

    if (_isExiting ||
        _shouldIgnoreZeroProgressUpdate(status) ||
        _shouldIgnoreRegressiveProgressUpdate(
          status,
          allowPositionRegression: false,
        )) {
      return;
    }

    _applyValidStatusUpdate(status, allowPositionRegression: false);
  }

  void _applyValidStatusUpdate(
    MeowVideoPlaybackStatus status, {
    required bool allowPositionRegression, // 为 true 时通常意味着用户手动 Seek 了
  }) {
    _latestStatus = status;
    if (status.isInitialized) {
      // 1. 更新内存和本地 UI
      _udp.updatePlaybackProgressForItem(
        widget.mediaItem,
        position: status.position,
        duration: status.duration,
        allowPositionRegression: allowPositionRegression,
        notify: true, 
      );

      // 2. 如果是 Seek 操作，强制立即同步服务器
      if (allowPositionRegression) {
        _udp.syncProgressToServerForItem(
          widget.mediaItem,
          position: status.position,
          duration: status.duration,
          force: true, // 关键：Seek 后立即上报
          // ... 其他参数
        );
      } else {
        // 普通播放心跳，走节流逻辑
        _maybeSyncProgressInBackground(status);
      }
    }
  }

  bool _shouldShieldInitialProgress(MeowVideoPlaybackStatus status) {
    if (!_isInitialSeeking || _isExiting) {
      return false;
    }
    if (_hasStableInitialPlayback(status)) {
      _isInitialSeeking = false;
      return false;
    }
    return true;
  }

  bool _hasStableInitialPlayback(MeowVideoPlaybackStatus status) {
    if (!status.isInitialized) {
      return false;
    }

    final initialPosition = widget.initialPosition;
    if (initialPosition > Duration.zero) {
      return _durationDistance(status.position, initialPosition) <=
              _initialSeekStabilityTolerance ||
          status.position >= initialPosition;
    }

    return status.position >= _playbackStartStabilityThreshold;
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

  bool _shouldIgnoreRegressiveProgressUpdate(
    MeowVideoPlaybackStatus status, {
    required bool allowPositionRegression,
  }) {
    if (allowPositionRegression) {
      return false;
    }

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

  bool _consumeManualSeekAllowance(Duration position) {
    final target = _pendingManualSeekTarget;
    if (target == null) {
      return false;
    }

    final delta = _durationDistance(position, target);
    if (delta <= _manualSeekTargetTolerance) {
      _pendingManualSeekTarget = null;
      return true;
    }
    return false;
  }

  Duration _durationDistance(Duration left, Duration right) {
    return left >= right ? left - right : right - left;
  }

  void _refreshUi(MeowVideoPlaybackStatus status) {
    final nextSecond = status.position.inSeconds;
    if (_lastUiProgressSecond == nextSecond || !mounted) {
      return;
    }
    _lastUiProgressSecond = nextSecond;
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
      '[Resume][Mobile][Playing] item=${widget.mediaItem.dataSourceId} '
      'position=${status.position.inMilliseconds}ms '
      'duration=${status.duration.inMilliseconds}ms',
    );
  }

  void _maybeSyncProgressInBackground(MeowVideoPlaybackStatus status) {
    if (!status.isPlaying || status.position <= Duration.zero) {
      return;
    }

    // 直接调用，由 Provider 内部的 _serverSyncThrottleInterval 决定是否真的发请求
    _udp.syncProgressToServerForItem(
      widget.mediaItem,
      position: status.position,
      duration: status.duration,
      playSessionId: widget.playSessionId,
      mediaSourceId: widget.mediaSourceId,
      audioStreamIndex: widget.audioStreamIndex,
      subtitleStreamIndex: widget.subtitleStreamIndex,
      force: false, // 普通心跳
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
      await player.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  MediaPlaybackProgress _captureExitSnapshot() {
    final status = _latestStatus;
    if (status != null &&
        status.isInitialized &&
        status.position > Duration.zero) {
      return MediaPlaybackProgress(
        position: status.position,
        duration: status.duration,
      );
    }
    return _lastStablePlaybackProgress ??
        widget.savedProgress ??
        const MediaPlaybackProgress(
          position: Duration.zero,
          duration: Duration.zero,
        );
  }

  void _applyLocalProgressOnExit(MediaPlaybackProgress snapshot) {
    if (snapshot.position <= Duration.zero) {
      return;
    }
    _lastStablePlaybackProgress = snapshot;
    _udp.updatePlaybackProgressForItem(
      widget.mediaItem,
      position: snapshot.position,
      duration: snapshot.duration,
      notify: true,
    );
  }

  Future<void> _performSyncOnExit() async {
    final capturedItem = widget.mediaItem;
    final snapshot = _captureExitSnapshot();
    _isExiting = true;
    final player = _detachPlayer();
    debugPrint(
      '[Resume][Mobile][Exit] item=${capturedItem.dataSourceId} '
      'position=${snapshot.position.inMilliseconds}ms '
      'duration=${snapshot.duration.inMilliseconds}ms '
      'sync=start',
    );
    _applyLocalProgressOnExit(snapshot);
    try {
      if (player != null) {
        await _stopPlayerSafely(player);
      }
      await _udp
          .stopPlaybackForItem(
            capturedItem,
            position: snapshot.position,
            duration: snapshot.duration,
            playSessionId: widget.playSessionId,
            mediaSourceId: widget.mediaSourceId,
            audioStreamIndex: widget.audioStreamIndex,
            subtitleStreamIndex: widget.subtitleStreamIndex,
          )
          .timeout(_exitSyncTimeout);
      debugPrint(
        '[Resume][Mobile][Exit] item=${capturedItem.dataSourceId} '
        'stopped=done',
      );
    } on TimeoutException {
      debugPrint(
        '[Resume][Mobile][Exit] item=${capturedItem.dataSourceId} '
        'stopped=timeout',
      );
    } finally {
      if (player != null) {
        await _disposePlayerSafely(player);
      }
    }
  }

  void _scheduleControlsAutoHide() {
    _controlsHideTimer?.cancel();
    if (_isLocked || !_controlsVisible || !_isPlaying) {
      return;
    }
    _controlsHideTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || _isLocked) {
        return;
      }
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _handleScreenInteraction() {
    if (_isLocked) {
      return;
    }
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    if (_activeOptionPanel != null) {
      setState(() {
        _activeOptionPanel = null;
      });
    }
    _scheduleControlsAutoHide();
  }

  Future<void> _togglePlayPause() async {
    if (_isLocked) {
      return;
    }
    _handleScreenInteraction();
    final p = _player;
    if (p == null) {
      return;
    }
    try {
      if (_isPlaying) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (_) {}
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    final p = _player;
    if (p == null) {
      return;
    }
    try {
      await p.setRate(speed);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentSpeed = speed;
      });
      _showCenterToast('${speed.toStringAsFixed(speed == 1.0 ? 1 : 2)}x');
      _handleScreenInteraction();
    } catch (_) {}
  }

  Future<void> _showSpeedOptions() async {
    if (_isLocked) {
      return;
    }
    _handleScreenInteraction();
    setState(() {
      _activeOptionPanel = _activeOptionPanel == _PlayerOptionPanel.speed
          ? null
          : _PlayerOptionPanel.speed;
    });
  }

  Future<void> _showResolutionOptions() async {
    if (_isLocked || widget.onResolutionSelected == null) {
      return;
    }
    _handleScreenInteraction();
    setState(() {
      _activeOptionPanel = _activeOptionPanel == _PlayerOptionPanel.resolution
          ? null
          : _PlayerOptionPanel.resolution;
    });
  }

  Future<void> _selectResolutionOption(PlayerResolutionOption option) async {
    setState(() {
      _activeOptionPanel = null;
    });
    await widget.onResolutionSelected!(option);
    _showCenterToast(option.label);
  }

  Future<void> _handlePiP() async {
    _handleScreenInteraction();
    _showCenterToast('PiP');
  }

  Future<void> _takeScreenshot() async {
    if (_isLocked) {
      return;
    }
    _handleScreenInteraction();
    try {
      final boundary =
          _playerBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('boundary unavailable');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('image bytes unavailable');
      }
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/meowhub-shot-${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      _showCenterToast('Saved');
    } catch (_) {
      _showCenterToast('Shot failed');
    }
  }

  void _showCenterToast(String text) {
    _centerToastTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _centerToastText = text;
    });
    _centerToastTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _centerToastText = null;
      });
    });
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _controlsVisible = false;
      } else {
        _controlsVisible = true;
      }
    });
    _scheduleControlsAutoHide();
  }

  Future<void> _seekToFraction(double value) async {
    final p = _player;
    final duration = _displayDuration;
    if (duration <= Duration.zero) {
      return;
    }
    final target = duration * value.clamp(0.0, 1.0);
    if (widget.isTranscoding && widget.onServerSeekRequested != null) {
      try {
        await widget.onServerSeekRequested!(target);
        _latestStatus = null;
        _lastStablePlaybackProgress = MediaPlaybackProgress(
          position: target,
          duration: duration,
        );
        _udp.registerOptimisticSeekForItem(
          widget.mediaItem,
          position: target,
          duration: duration,
          notify: true,
        );
        if (mounted) {
          setState(() {});
        }
        return;
      } catch (error) {
        debugPrint(
          '[Resume][Mobile][Seek][Server][Error] '
          'item=${widget.mediaItem.dataSourceId} '
          'target=${target.inMilliseconds}ms error=$error',
        );
      }
    }
    if (p == null) {
      return;
    }
    _lastStablePlaybackProgress = MediaPlaybackProgress(
      position: target,
      duration: duration,
    );
    _udp.registerOptimisticSeekForItem(
      widget.mediaItem,
      position: target,
      duration: duration,
      notify: true,
    );
    try {
      await p.seek(target);
    } catch (_) {}
  }

  void _handleScrubChanged(double value) {
    _handleScreenInteraction();
    setState(() {
      _isScrubbing = true;
      _scrubValue = value;
    });
  }

  void _handleScrubStarted() {
    _handleScreenInteraction();
    if (_isScrubbing) {
      return;
    }
    setState(() {
      _isScrubbing = true;
    });
  }

  Future<void> _handleScrubEnd(double value) async {
    final duration = _displayDuration;
    if (duration > Duration.zero) {
      _pendingManualSeekTarget = duration * value.clamp(0.0, 1.0);
    }
    await _seekToFraction(value);
    if (!mounted) {
      return;
    }
    setState(() {
      _isScrubbing = false;
      _scrubValue = null;
    });
    _scheduleControlsAutoHide();
  }

  Future<void> _handleProgressBarSeek(Duration duration) async {
    final total = _displayDuration;
    if (total <= Duration.zero) {
      return;
    }
    final fraction =
        duration.inMilliseconds / total.inMilliseconds.clamp(1, 1 << 30);
    await _handleScrubEnd(fraction.clamp(0.0, 1.0));
  }

  Widget _buildPlayer() {
    if (!_hasPlayableUrl) {
      return _UnavailablePlayerView(title: widget.mediaItem.title);
    }

    return RepaintBoundary(
      key: _playerBoundaryKey,
      child: MeowVideoPlayer(
        key: ObjectKey(widget.mediaItem.dataSourceId),
        url: widget.playUrlOverride ?? widget.mediaItem.playUrl!,
        autoPlay: true,
        fit: BoxFit.contain,
        expandToFill: true,
        borderRadius: BorderRadius.zero,
        initialPosition: widget.initialPosition,
        onPlaybackStatusChanged: _handlePlaybackStatusChanged,
        onPlaybackStarted: _handlePlaybackStarted,
        onPlayerCreated: (p) async {
          _player = p;
          try {
            await p.setRate(_currentSpeed);
          } catch (_) {}
        },
        overlayCcButton: false,
        onTapCc: widget.onShowTrackSelector,
        subtitleUri: widget.subtitleUri,
        subtitleTitle: widget.subtitleTitle,
        subtitleLanguage: widget.subtitleLanguage,
        disableSubtitleTrack: widget.disableSubtitleTrack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaPadding = MediaQuery.of(context).padding;
    final safeLeft = mediaPadding.left > 0 ? mediaPadding.left + 2.0 : 0.0;
    final safeRight = mediaPadding.right > 0 ? mediaPadding.right + 2.0 : 0.0;
    final safeTop = mediaPadding.top > 0 ? mediaPadding.top + 2.0 : 2.0;
    final safeBottom = mediaPadding.bottom > 0
        ? mediaPadding.bottom + 2.0
        : 2.0;

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
          // ignore: discarded_futures
          _restoreSystemUi();
          _allowImmediatePop = true;
          navigator.pop();
        });
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            Positioned.fill(child: _buildPlayer()),

            // 基础手势层：点击切换控制条
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_isLocked) {
                    return;
                  }
                  setState(() {
                    _controlsVisible = !_controlsVisible;
                    if (!_controlsVisible) {
                      _activeOptionPanel = null;
                    }
                  });
                  _scheduleControlsAutoHide();
                },
                onDoubleTap: _handleScreenInteraction,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 112,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.52),
                        Colors.black.withValues(alpha: 0.14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 148,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.66),
                        Colors.black.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_controlsVisible && !_isLocked)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: _activeOptionPanel != null,
                  child: _ControlsOverlay(
                    state: this,
                    safeLeft: safeLeft,
                    safeRight: safeRight,
                    safeTop: safeTop,
                    safeBottom: safeBottom,
                  ),
                ),
              ),
            if (_controlsVisible || _isLocked)
              Positioned(
                left: safeLeft,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: _activeOptionPanel != null && !_isLocked,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _SideActionButton(
                      icon: _isLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      onPressed: _toggleLock,
                    ),
                  ),
                ),
              ),
            if (_controlsVisible && !_isLocked)
              Positioned(
                right: safeRight,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: _activeOptionPanel != null,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _SideActionButton(
                      icon: Icons.photo_camera_outlined,
                      onPressed: _takeScreenshot,
                    ),
                  ),
                ),
              ),
            if (_controlsVisible && !_isLocked && _activeOptionPanel != null)
              Positioned.fill(
                child: _OptionDrawerLayer(
                  activePanel: _activeOptionPanel!,
                  safeTop: safeTop,
                  safeRight: safeRight,
                  title: _activeOptionPanel == _PlayerOptionPanel.speed
                      ? '倍速'
                      : '分辨率',
                  onClose: () {
                    setState(() {
                      _activeOptionPanel = null;
                    });
                  },
                  children: _activeOptionPanel == _PlayerOptionPanel.speed
                      ? [
                          for (final speed in _playbackSpeeds)
                            _DrawerOptionTile(
                              label:
                                  '${speed.toStringAsFixed(speed == 1.0 ? 1 : 2)}x',
                              selected: _currentSpeed == speed,
                              onTap: () => _setPlaybackSpeed(speed).then((_) {
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _activeOptionPanel = null;
                                });
                              }),
                            ),
                        ]
                      : [
                          for (final option in widget.resolutionOptions)
                            _DrawerOptionTile(
                              label: option.label,
                              selected: widget.selectedResolution == option,
                              onTap: () => _selectResolutionOption(option),
                            ),
                        ],
                ),
              ),
            if (_isLocked)
              Positioned(
                left: safeLeft + 56,
                right: safeRight + 56,
                bottom: safeBottom + 2,
                child: Center(
                  child: Text(
                    'Screen Locked',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      shadows: _premiumShadows,
                    ),
                  ),
                ),
              ),
            if (_centerToastText case final toast?)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: 1,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          toast,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                shadows: _premiumShadows,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.state,
    required this.safeLeft,
    required this.safeRight,
    required this.safeTop,
    required this.safeBottom,
  });

  final _MobilePlayerScreenState state;
  final double safeLeft;
  final double safeRight;
  final double safeTop;
  final double safeBottom;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: safeTop,
          left: safeLeft,
          right: safeRight,
          child: _TopControlBar(state: state),
        ),
        Positioned(
          left: safeLeft,
          right: safeRight,
          bottom: safeBottom + 2,
          child: _BottomControlBar(state: state),
        ),
        if (!state._isPlaying)
          const Positioned.fill(
            child: IgnorePointer(child: Center(child: _PausedPlayGlyph())),
          ),
      ],
    );
  }
}

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({required this.state});

  final _MobilePlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
          iconSize: 16,
          padding: const EdgeInsets.all(7),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            state.widget.mediaItem.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 19,
              height: 1.05,
              color: Colors.white.withValues(alpha: 0.96),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              shadows: _premiumShadows,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GlassIconButton(
              icon: Icons.cast_connected_rounded,
              onPressed: state._handlePiP,
              iconSize: 16,
              padding: const EdgeInsets.all(7),
            ),
            const SizedBox(width: 4),
            _GlassIconButton(
              icon: Icons.tune_rounded,
              onPressed: state.widget.onShowTrackSelector ?? () {},
              iconSize: 16,
              padding: const EdgeInsets.all(7),
            ),
          ],
        ),
      ],
    );
  }
}

class _BottomControlBar extends StatelessWidget {
  const _BottomControlBar({required this.state});

  final _MobilePlayerScreenState state;

  @override
  Widget build(BuildContext context) {
    final displayDuration = state._displayDuration;
    final displayPosition = state._displayPosition;
    final cappedPosition = displayPosition > displayDuration
        ? displayDuration
        : displayPosition;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            sliderTheme: SliderTheme.of(
              context,
            ).copyWith(overlayShape: SliderComponentShape.noOverlay),
          ),
          child: SizedBox(
            height: _MobilePlayerScreenState._progressBarTouchHeight,
            width: double.infinity,
            child: progress_bar.ProgressBar(
              progress: cappedPosition,
              total: displayDuration,
              timeLabelLocation: progress_bar.TimeLabelLocation.none,
              barHeight: state._isScrubbing ? 4 : 3,
              baseBarColor: Colors.white.withValues(alpha: 0.18),
              progressBarColor: Colors.white,
              thumbColor: const Color(0xFFE5484D),
              thumbRadius: state._isScrubbing ? 8 : 6,
              thumbGlowRadius: 14,
              bufferedBarColor: Colors.transparent,
              onSeek: state._handleProgressBarSeek,
              onDragStart: (_) => state._handleScrubStarted(),
              onDragUpdate: (details) {
                if (displayDuration <= Duration.zero) {
                  return;
                }
                final fraction =
                    details.timeStamp.inMilliseconds /
                    displayDuration.inMilliseconds.clamp(1, 1 << 30);
                state._handleScrubChanged(fraction.clamp(0.0, 1.0));
              },
              onDragEnd: () => state._scheduleControlsAutoHide(),
            ),
          ),
        ),
        const SizedBox(height: 0),
        Row(
          children: [
            Text(
              formatDurationLabel(cappedPosition),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.98),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: _premiumShadows,
              ),
            ),
            const Spacer(),
            Text(
              formatDurationLabel(displayDuration),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                shadows: _premiumShadows,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _ControlDock(
              child: _PrimaryActionButton(
                icon: state._isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                onPressed: state._togglePlayPause,
                size: 32,
              ),
            ),
            const Spacer(),
            _ControlDock(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _GlassIconButton(
                    icon: Icons.speed_rounded,
                    onPressed: state._showSpeedOptions,
                    showChrome: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    iconSize: 18,
                  ),
                  const SizedBox(width: 4),
                  _GlassIconButton(
                    icon: Icons.high_quality_rounded,
                    onPressed: state._showResolutionOptions,
                    showChrome: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    iconSize: 18,
                  ),
                  const SizedBox(width: 4),
                  // 新增：横竖屏切换按钮
                  _GlassIconButton(
                    icon: Icons.screen_rotation_rounded,
                    onPressed: state._toggleOrientation,
                    showChrome: false,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    iconSize: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.padding = const EdgeInsets.all(12),
    this.iconSize = 20,
    this.showChrome = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final EdgeInsets padding;
  final double iconSize;
  final bool showChrome;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            color: showChrome
                ? Colors.black.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: showChrome
                ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                : null,
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: Colors.white,
            shadows: _premiumShadows,
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.icon,
    required this.onPressed,
    required this.size,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      iconSize: size,
      splashRadius: size * 0.7,
      color: Colors.white,
      icon: Icon(icon, shadows: _premiumShadows),
    );
  }
}

class _SideActionButton extends StatelessWidget {
  const _SideActionButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _GlassIconButton(
      icon: icon,
      onPressed: onPressed,
      padding: const EdgeInsets.all(7),
      iconSize: 22,
      showChrome: false,
    );
  }
}

class _PausedPlayGlyph extends StatelessWidget {
  const _PausedPlayGlyph();

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.play_arrow_rounded,
      size: 54,
      color: Colors.white.withValues(alpha: 0.94),
      shadows: const [
        Shadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 2)),
      ],
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // return DecoratedBox(
    //   decoration: BoxDecoration(
    //     color: Colors.black.withValues(alpha: 0.16),
    //     borderRadius: BorderRadius.circular(999),
    //     border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    //   ),
    //   child: Padding(
    //     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    //     child: child,
    //   ),
    // );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: child,
    );
  }
}

class _UnavailablePlayerView extends StatelessWidget {
  const _UnavailablePlayerView({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.link_off_rounded,
                size: 42,
                color: Colors.white54,
              ),
              const SizedBox(height: 14),
              Text(
                '$title 暂无可用播放地址',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<Shadow> _premiumShadows = [
  Shadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 2)),
];

enum _PlayerOptionPanel { speed, resolution }

class PlayerResolutionOption {
  const PlayerResolutionOption({
    required this.label,
    required this.maxStreamingBitrate,
  });

  final String label;
  final int maxStreamingBitrate;

  @override
  bool operator ==(Object other) {
    return other is PlayerResolutionOption &&
        other.label == label &&
        other.maxStreamingBitrate == maxStreamingBitrate;
  }

  @override
  int get hashCode => Object.hash(label, maxStreamingBitrate);
}

class _OptionDrawerLayer extends StatelessWidget {
  const _OptionDrawerLayer({
    required this.activePanel,
    required this.safeTop,
    required this.safeRight,
    required this.title,
    required this.onClose,
    required this.children,
  });

  final _PlayerOptionPanel activePanel;
  final double safeTop;
  final double safeRight;
  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    // --- 动态计算尺寸和位置 ---
    // 竖屏下：宽度占 60%，最大 280；横屏下：宽度占 32%
    final drawerWidth = isPortrait
        ? (screenSize.width * 0.6).clamp(200.0, 280.0)
        : (screenSize.width * 0.32).clamp(180.0, 320.0);

    // 竖屏下也给一个明确高度，避免抽屉内部的 Flex 在无界高度下报错。
    final drawerHeight = isPortrait
        ? screenSize.height * 0.45
        : screenSize.height;

    return Stack(
      children: [
        // 1. 全屏背景遮罩：点击关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.12)),
          ),
        ),

        // 2. 动画面板
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          top: isPortrait ? null : 0,
          bottom: isPortrait ? 20 + MediaQuery.of(context).padding.bottom : 0,
          right: isPortrait ? 16 : 0,
          width: drawerWidth,
          height: isPortrait ? drawerHeight : null,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isPortrait ? 24 : 0),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    isPortrait ? 16 : (safeTop + 8),
                    16,
                    16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    borderRadius: BorderRadius.circular(isPortrait ? 24 : 0),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: onClose,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DrawerOptionTile extends StatelessWidget {
  const _DrawerOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    shadows: _premiumShadows,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
