import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shimmer/shimmer.dart';

// --- 保留你原有且优秀的架构定义 ---

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

// --- 核心组件重构 ---

class MeowVideoPlayer extends StatefulWidget {
  const MeowVideoPlayer({
    super.key,
    required this.url,
    this.aspectRatio,
    this.autoPlay = false,
    this.looping = false,
    this.renderMode = MeowVideoRenderMode.flutter,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.httpHeaders = const {},
    this.androidNativeBuilder,
    this.harmonyNativeBuilder,
    this.initialPosition = Duration.zero,
    this.onPlaybackStatusChanged,
    this.onPlayerCreated,
    this.overlayCcButton = false,
    this.onTapCc,
    this.subtitleUri,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.disableSubtitleTrack = false,
  });

  final String url;
  final double? aspectRatio;
  final bool autoPlay;
  final bool looping;
  final MeowVideoRenderMode renderMode;
  final BorderRadius borderRadius;
  final Map<String, String> httpHeaders;
  final MeowVideoNativeRendererBuilder? androidNativeBuilder;
  final MeowVideoNativeRendererBuilder? harmonyNativeBuilder;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged? onPlaybackStatusChanged;
  final ValueChanged<Player>? onPlayerCreated;
  final bool overlayCcButton;
  final VoidCallback? onTapCc;
  final String? subtitleUri;
  final String? subtitleTitle;
  final String? subtitleLanguage;
  final bool disableSubtitleTrack;

  @override
  State<MeowVideoPlayer> createState() => _MeowVideoPlayerState();
}

class _MeowVideoPlayerState extends State<MeowVideoPlayer> {
  Player? _player;
  VideoController? _videoController;
  Future<void>? _initializeVideoFuture;
  bool _switchingSource = false; // 串行化切源，避免双音轨窗口

  // Cached state for callback synthesis
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;

  bool get _usesFlutterRenderer =>
      widget.renderMode == MeowVideoRenderMode.flutter;
  double get _fallbackAspectRatio => widget.aspectRatio ?? 16 / 9;

  @override
  void initState() {
    super.initState();
    _configureRenderer();
  }

  @override
  void didUpdateWidget(covariant MeowVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 渲染模式变化需要重配；仅 URL 变化时在同一 Player 上 reopen，避免重建导致双音轨
    if (oldWidget.renderMode != widget.renderMode) {
      _configureRenderer();
      return;
    }
    if (oldWidget.url != widget.url) {
      // ignore: discarded_futures
      _reopenOnSamePlayer(url: widget.url);
      return;
    }
    if (oldWidget.subtitleUri != widget.subtitleUri ||
        oldWidget.subtitleTitle != widget.subtitleTitle ||
        oldWidget.subtitleLanguage != widget.subtitleLanguage ||
        oldWidget.disableSubtitleTrack != widget.disableSubtitleTrack) {
      // ignore: discarded_futures
      _applySubtitleSelection();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _videoController = null;
    final p = _player;
    _player = null;
    if (p != null) {
      // 先尝试停止，确保音频流关闭，再释放底层资源
      try {
        // stop() 是异步；此处在 dispose 中无法 await，但调用可提示底层尽快切断流
        // 若你希望严格 await，可将播放器抽到可控生命周期（如上层 State）并在其 dispose 中 await。
        // ignore: discarded_futures
        p.stop();
      } catch (_) {}
      try {
        p.dispose();
      } catch (_) {}
    }
  }

  void _configureRenderer() {
    if (_usesFlutterRenderer) {
      _initializeFlutterPlayer();
    } else {
      _disposeControllers();
      setState(() {
        _initializeVideoFuture = null;
      });
    }
  }

  Future<void> _initializeFlutterPlayer() async {
    _disposeControllers();

    // 确保底层已初始化（多平台安全）
    MediaKit.ensureInitialized();

    final player = Player(configuration: const PlayerConfiguration());
    final videoController = VideoController(player);

    _player = player;
    _videoController = videoController;
    // 暴露底层 Player，便于上层在退出前 await stop()
    widget.onPlayerCreated?.call(player);

    // 监听核心状态流并合成统一回调
    _bindStreams(player);

    _initializeVideoFuture = () async {
      // 打开媒体
      await player.open(
        Media(widget.url, httpHeaders: widget.httpHeaders),
        play: widget.autoPlay,
      );
      await _applySubtitleSelection(player: player);

      // 起始位置
      if (widget.initialPosition > Duration.zero) {
        await player.seek(widget.initialPosition);
      }

      // 循环逻辑：单源循环
      if (widget.looping) {
        try {
          player.setPlaylistMode(PlaylistMode.loop);
        } catch (_) {
          // 某些版本不支持，忽略
        }
      }

      if (!mounted) return;
      setState(() {});
    }();
  }

  Future<void> _reopenOnSamePlayer({
    required String url,
    Duration? seekTo,
  }) async {
    // 仅 Flutter 渲染下在同一实例上切源；其他渲染模式仍交给外层重配
    if (!_usesFlutterRenderer) {
      _configureRenderer();
      return;
    }
    final player = _player;
    if (player == null) {
      // 若尚未完成初始化，退回到常规初始化流程
      await _initializeFlutterPlayer();
      return;
    }
    if (_switchingSource) return;
    _switchingSource = true;
    try {
      try {
        await player.pause();
      } catch (_) {}
      try {
        await player.stop();
      } catch (_) {}
      await player.open(
        Media(url, httpHeaders: widget.httpHeaders),
        play: widget.autoPlay,
      );
      await _applySubtitleSelection(player: player);
      final pos =
          seekTo ??
          (widget.initialPosition > Duration.zero
              ? widget.initialPosition
              : Duration.zero);
      if (pos > Duration.zero) {
        try {
          await player.seek(pos);
        } catch (_) {}
      }
      if (widget.looping) {
        try {
          player.setPlaylistMode(PlaylistMode.loop);
        } catch (_) {}
      }
    } finally {
      _switchingSource = false;
    }
    if (!mounted) return;
    setState(() {});
  }

  final List<StreamSubscription> _subscriptions = [];

  Future<void> _applySubtitleSelection({Player? player}) async {
    final target = player ?? _player;
    if (target == null || !_usesFlutterRenderer) {
      return;
    }
    try {
      final subtitleUri = widget.subtitleUri?.trim();
      if (subtitleUri != null && subtitleUri.isNotEmpty) {
        await target.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitleUri,
            title: widget.subtitleTitle,
            language: widget.subtitleLanguage,
          ),
        );
        return;
      }
      if (widget.disableSubtitleTrack) {
        await target.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      await target.setSubtitleTrack(SubtitleTrack.auto());
    } catch (_) {}
  }

  void _bindStreams(Player player) {
    void emit() {
      final duration = _duration;
      final position = _position;
      final completionThreshold = duration > const Duration(milliseconds: 600)
          ? duration - const Duration(milliseconds: 600)
          : duration;
      final isCompleted =
          duration > Duration.zero &&
          position >= completionThreshold &&
          !_isPlaying;

      widget.onPlaybackStatusChanged?.call(
        MeowVideoPlaybackStatus(
          position: position,
          duration: duration,
          isInitialized: duration > Duration.zero,
          isPlaying: _isPlaying,
          isBuffering: _isBuffering,
          isCompleted: isCompleted,
        ),
      );
    }

    _subscriptions.addAll([
      player.stream.position.listen((p) {
        _position = p;
        emit();
      }),
      player.stream.duration.listen((d) {
        _duration = d;
        emit();
      }),
      player.stream.playing.listen((playing) {
        _isPlaying = playing;
        emit();
      }),
      player.stream.buffering.listen((b) {
        _isBuffering = b;
        emit();
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // 原生渲染模式分支保持不变
    if (!_usesFlutterRenderer) {
      return _NativeRendererShell(
        widget: widget,
        fallbackAspectRatio: _fallbackAspectRatio,
      );
    }

    final video = FutureBuilder<void>(
      future: _initializeVideoFuture,
      builder: (context, snapshot) {
        final aspectRatio = widget.aspectRatio ?? _fallbackAspectRatio;
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              color: Colors.black,
              child: _videoController != null
                  ? Video(
                      controller: _videoController!,
                      // 交给 media_kit 内部根据帧率/时钟同步渲染，通常能改善音画同步
                      fit: BoxFit.contain,
                    )
                  : const _VideoLoadingState(),
            ),
          ),
        );
      },
    );
    if (!widget.overlayCcButton) return video;
    return Stack(
      children: [
        Positioned.fill(child: video),
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: widget.onTapCc,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.closed_caption_outlined, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- 辅助组件：保留你之前精美的加载和错误态 ---

class _VideoLoadingState extends StatelessWidget {
  const _VideoLoadingState();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFF101010),
      highlightColor: const Color(0xFF1C1C1C),
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 48,
            color: Colors.white24,
          ),
        ),
      ),
    );
  }
}

// 移除专用错误组件（media_kit 内部会抛出异常，可在上层捕获并渲染）

// 保留原有的 NativeShell 逻辑
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
    final builder = widget.renderMode == MeowVideoRenderMode.androidNative
        ? widget.androidNativeBuilder
        : widget.harmonyNativeBuilder;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: fallbackAspectRatio,
        child:
            builder?.call(context, config) ??
            const Center(child: Text('不支持的原生渲染')),
      ),
    );
  }
}
