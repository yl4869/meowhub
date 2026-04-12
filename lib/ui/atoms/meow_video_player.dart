import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../../theme/app_theme.dart';

enum MeowVideoRenderMode { flutter, androidNative, harmonyNative }

class MeowVideoNativeRenderConfig {
  const MeowVideoNativeRenderConfig({
    required this.url,
    required this.autoPlay,
    required this.looping,
    required this.aspectRatio,
    required this.borderRadius,
  });

  final String url;
  final bool autoPlay;
  final bool looping;
  final double aspectRatio;
  final BorderRadius borderRadius;
}

typedef MeowVideoNativeRendererBuilder =
    Widget Function(BuildContext context, MeowVideoNativeRenderConfig config);

class MeowVideoPlaybackStatus {
  const MeowVideoPlaybackStatus({
    required this.position,
    required this.duration,
    required this.isInitialized,
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
  });

  final Duration position;
  final Duration duration;
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
}

typedef MeowVideoPlaybackStatusChanged =
    void Function(MeowVideoPlaybackStatus status);

class MeowVideoPlayer extends StatefulWidget {
  const MeowVideoPlayer({
    super.key,
    required this.url,
    this.aspectRatio,
    this.autoPlay = false,
    this.looping = false,
    this.renderMode = MeowVideoRenderMode.flutter,
    this.flutterViewType = VideoViewType.textureView,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.httpHeaders = const {},
    this.androidNativeBuilder,
    this.harmonyNativeBuilder,
    this.initialPosition = Duration.zero,
    this.onPlaybackStatusChanged,
  });

  final String url;
  final double? aspectRatio;
  final bool autoPlay;
  final bool looping;
  final MeowVideoRenderMode renderMode;
  final VideoViewType flutterViewType;
  final BorderRadius borderRadius;
  final Map<String, String> httpHeaders;
  final MeowVideoNativeRendererBuilder? androidNativeBuilder;
  final MeowVideoNativeRendererBuilder? harmonyNativeBuilder;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged? onPlaybackStatusChanged;

  @override
  State<MeowVideoPlayer> createState() => _MeowVideoPlayerState();
}

class _MeowVideoPlayerState extends State<MeowVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeVideoFuture;
  Timer? _hideControlsTimer;
  bool _showControls = true;
  bool _isScrubbing = false;
  double? _scrubValueMs;
  bool _wasPlaying = false;

  bool get _usesFlutterRenderer {
    return widget.renderMode == MeowVideoRenderMode.flutter;
  }

  double get _fallbackAspectRatio => widget.aspectRatio ?? 16 / 9;

  @override
  void initState() {
    super.initState();
    _configureRenderer();
  }

  @override
  void didUpdateWidget(covariant MeowVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldReconfigure =
        oldWidget.url != widget.url ||
        oldWidget.renderMode != widget.renderMode ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.looping != widget.looping ||
        oldWidget.flutterViewType != widget.flutterViewType ||
        oldWidget.initialPosition != widget.initialPosition;

    if (shouldReconfigure) {
      _configureRenderer();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  void _configureRenderer() {
    _hideControlsTimer?.cancel();
    _showControls = true;
    _isScrubbing = false;
    _scrubValueMs = null;
    _wasPlaying = false;

    if (_usesFlutterRenderer) {
      _initializeFlutterController();
    } else {
      _disposeController();
      if (mounted) {
        setState(() {
          _initializeVideoFuture = null;
        });
      }
    }
  }

  void _initializeFlutterController() {
    _disposeController();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
      httpHeaders: widget.httpHeaders,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      viewType: widget.flutterViewType,
    );

    controller.addListener(_handlePlaybackStateChange);

    final initializeFuture = controller.initialize().then((_) async {
      await controller.setLooping(widget.looping);
      final initialPosition = _clampedInitialPosition(
        controller.value.duration,
      );
      if (initialPosition > Duration.zero) {
        await controller.seekTo(initialPosition);
      }
      if (widget.autoPlay) {
        await controller.play();
        _scheduleControlsAutoHide();
      }
      _emitPlaybackStatus(controller.value);
    });

    setState(() {
      _controller = controller;
      _initializeVideoFuture = initializeFuture;
    });
  }

  void _disposeController() {
    _controller?.removeListener(_handlePlaybackStateChange);
    _controller?.dispose();
    _controller = null;
  }

  void _handlePlaybackStateChange() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }

    final value = controller.value;
    final isPlaying = value.isPlaying;

    if (isPlaying && !_wasPlaying) {
      _scheduleControlsAutoHide();
    }

    if (!isPlaying && _wasPlaying) {
      _hideControlsTimer?.cancel();
      if (!_showControls) {
        setState(() {
          _showControls = true;
        });
      }
    }

    final isFinished =
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying;

    if (isFinished) {
      _hideControlsTimer?.cancel();
      if (!_showControls) {
        setState(() {
          _showControls = true;
        });
      }
    }

    _wasPlaying = isPlaying;
    _emitPlaybackStatus(value);
  }

  Duration _clampedInitialPosition(Duration totalDuration) {
    final requestedPosition = widget.initialPosition;
    if (requestedPosition <= Duration.zero || totalDuration <= Duration.zero) {
      return Duration.zero;
    }

    final maxResumePosition = totalDuration > const Duration(seconds: 2)
        ? totalDuration - const Duration(seconds: 2)
        : Duration.zero;

    if (requestedPosition > maxResumePosition) {
      return maxResumePosition;
    }

    return requestedPosition;
  }

  void _emitPlaybackStatus(VideoPlayerValue value) {
    final callback = widget.onPlaybackStatusChanged;
    if (callback == null) {
      return;
    }

    final completionThreshold =
        value.duration > const Duration(milliseconds: 600)
        ? value.duration - const Duration(milliseconds: 600)
        : value.duration;
    final isCompleted =
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= completionThreshold &&
        !value.isPlaying;

    callback(
      MeowVideoPlaybackStatus(
        position: value.position,
        duration: value.duration,
        isInitialized: value.isInitialized,
        isPlaying: value.isPlaying,
        isBuffering: value.isBuffering,
        isCompleted: isCompleted,
      ),
    );
  }

  void _scheduleControlsAutoHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isScrubbing) {
        return;
      }
      setState(() {
        _showControls = false;
      });
    });
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
      _scheduleControlsAutoHide();
    }
  }

  void _toggleControlsVisibility() {
    final controller = _controller;
    final canAutoHide = controller?.value.isPlaying ?? false;

    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls && canAutoHide) {
      _scheduleControlsAutoHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _seekBy(Duration delta) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final duration = controller.value.duration;
    final target = controller.value.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > duration ? duration : target);
    controller.seekTo(clamped);
  }

  @override
  Widget build(BuildContext context) {
    if (!_usesFlutterRenderer) {
      return _NativeRendererShell(
        widget: widget,
        fallbackAspectRatio: _fallbackAspectRatio,
      );
    }

    return FutureBuilder<void>(
      future: _initializeVideoFuture,
      builder: (context, snapshot) {
        final controller = _controller;
        final initialized = controller?.value.isInitialized ?? false;
        final aspectRatio = initialized
            ? controller!.value.aspectRatio
            : _fallbackAspectRatio;

        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio > 0 ? aspectRatio : _fallbackAspectRatio,
            child: Material(
              color: Colors.black,
              child: InkWell(
                onTap: _toggleControlsVisibility,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting ||
                        !initialized)
                      const _VideoLoadingState()
                    else
                      VideoPlayer(controller!),
                    if (snapshot.hasError)
                      const _VideoErrorState()
                    else if (initialized)
                      _PlaybackOverlay(
                        controller: controller!,
                        showControls: _showControls,
                        isScrubbing: _isScrubbing,
                        scrubValueMs: _scrubValueMs,
                        onPlayPausePressed: _togglePlayback,
                        onReplayPressed: () =>
                            _seekBy(const Duration(seconds: -10)),
                        onForwardPressed: () =>
                            _seekBy(const Duration(seconds: 10)),
                        onScrubbingStart: (value) {
                          _hideControlsTimer?.cancel();
                          _isScrubbing = true;
                          _scrubValueMs = value;
                        },
                        onScrubbingUpdate: (value) {
                          setState(() {
                            _scrubValueMs = value;
                          });
                        },
                        onScrubbingEnd: (value) {
                          final target = Duration(milliseconds: value.round());
                          controller.seekTo(target);
                          _isScrubbing = false;
                          _scrubValueMs = null;
                          if (controller.value.isPlaying) {
                            _scheduleControlsAutoHide();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NativeRendererShell extends StatelessWidget {
  const _NativeRendererShell({
    required this.widget,
    required this.fallbackAspectRatio,
  });

  final MeowVideoPlayer widget;
  final double fallbackAspectRatio;

  @override
  Widget build(BuildContext context) {
    final config = MeowVideoNativeRenderConfig(
      url: widget.url,
      autoPlay: widget.autoPlay,
      looping: widget.looping,
      aspectRatio: fallbackAspectRatio,
      borderRadius: widget.borderRadius,
    );

    final builder = switch (widget.renderMode) {
      MeowVideoRenderMode.androidNative => widget.androidNativeBuilder,
      MeowVideoRenderMode.harmonyNative => widget.harmonyNativeBuilder,
      MeowVideoRenderMode.flutter => null,
    };

    final content = builder != null
        ? builder(context, config)
        : const _UnsupportedNativeRendererState();

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(aspectRatio: fallbackAspectRatio, child: content),
    );
  }
}

class _PlaybackOverlay extends StatelessWidget {
  const _PlaybackOverlay({
    required this.controller,
    required this.showControls,
    required this.isScrubbing,
    required this.scrubValueMs,
    required this.onPlayPausePressed,
    required this.onReplayPressed,
    required this.onForwardPressed,
    required this.onScrubbingStart,
    required this.onScrubbingUpdate,
    required this.onScrubbingEnd,
  });

  final VideoPlayerController controller;
  final bool showControls;
  final bool isScrubbing;
  final double? scrubValueMs;
  final VoidCallback onPlayPausePressed;
  final VoidCallback onReplayPressed;
  final VoidCallback onForwardPressed;
  final ValueChanged<double> onScrubbingStart;
  final ValueChanged<double> onScrubbingUpdate;
  final ValueChanged<double> onScrubbingEnd;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final totalMs = value.duration.inMilliseconds.toDouble();
    final currentMs = isScrubbing
        ? (scrubValueMs ?? 0)
        : value.position.inMilliseconds.toDouble();

    return AnimatedOpacity(
      opacity: showControls ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !showControls,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.38),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.6),
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: value.isBuffering
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white70,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _OverlayButton(
                      icon: Icons.replay_10_rounded,
                      onPressed: onReplayPressed,
                    ),
                    const SizedBox(width: 14),
                    _OverlayButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 68,
                      fill: true,
                      onPressed: onPlayPausePressed,
                    ),
                    const SizedBox(width: 14),
                    _OverlayButton(
                      icon: Icons.forward_10_rounded,
                      onPressed: onForwardPressed,
                    ),
                  ],
                ),
                const Spacer(),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: AppTheme.accentColor,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppTheme.accentColor,
                    overlayColor: AppTheme.accentColor.withValues(alpha: 0.18),
                  ),
                  child: Slider(
                    min: 0,
                    max: totalMs > 0 ? totalMs : 1,
                    value: currentMs.clamp(0, totalMs > 0 ? totalMs : 1),
                    onChanged: onScrubbingUpdate,
                    onChangeStart: onScrubbingStart,
                    onChangeEnd: onScrubbingEnd,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(
                        Duration(milliseconds: currentMs.round()),
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(value.duration),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.onPressed,
    this.fill = false,
    this.size = 50,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill
          ? AppTheme.accentColor.withValues(alpha: 0.92)
          : Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: fill ? AppTheme.onAccentColor : Colors.white,
            size: fill ? 34 : 28,
          ),
        ),
      ),
    );
  }
}

class _VideoLoadingState extends StatelessWidget {
  const _VideoLoadingState();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF101010),
      highlightColor: const Color(0xFF1C1C1C),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

class _VideoErrorState extends StatelessWidget {
  const _VideoErrorState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white70),
              const SizedBox(height: 10),
              Text(
                '视频加载失败，请稍后重试。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnsupportedNativeRendererState extends StatelessWidget {
  const _UnsupportedNativeRendererState();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.cardColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '当前渲染模式还没有接入原生播放器实现。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
