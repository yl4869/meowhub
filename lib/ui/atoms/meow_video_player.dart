import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shimmer/shimmer.dart';
import '../../domain/entities/playback_plan.dart';

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
    this.fit = BoxFit.contain,
    this.expandToFill = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.httpHeaders = const {},
    this.androidNativeBuilder,
    this.harmonyNativeBuilder,
    this.initialPosition = Duration.zero,
    this.onPlaybackStatusChanged,
    this.onPlaybackStarted,
    this.onPlayerCreated,
    this.overlayCcButton = false,
    this.onTapCc,
    this.subtitleUri,
    this.subtitleTitle,
    this.subtitleLanguage,
    this.disableSubtitleTrack = false,
    this.subtitleStreamIndex,
    this.subtitleStreams = const [],
    this.audioStreamIndex,
    this.audioStreams = const [],
  });

  final String url;
  final double? aspectRatio;
  final bool autoPlay;
  final bool looping;
  final MeowVideoRenderMode renderMode;
  final BoxFit fit;
  final bool expandToFill;
  final BorderRadius borderRadius;
  final Map<String, String> httpHeaders;
  final MeowVideoNativeRendererBuilder? androidNativeBuilder;
  final MeowVideoNativeRendererBuilder? harmonyNativeBuilder;
  final Duration initialPosition;
  final MeowVideoPlaybackStatusChanged? onPlaybackStatusChanged;
  final MeowVideoPlaybackStatusChanged? onPlaybackStarted;
  final ValueChanged<Player>? onPlayerCreated;
  final bool overlayCcButton;
  final VoidCallback? onTapCc;
  final String? subtitleUri;
  final String? subtitleTitle;
  final String? subtitleLanguage;
  final bool disableSubtitleTrack;
  final int? subtitleStreamIndex;
  final List<PlaybackStream> subtitleStreams;
  final int? audioStreamIndex;
  final List<PlaybackStream> audioStreams;

  @override
  State<MeowVideoPlayer> createState() => _MeowVideoPlayerState();
}

class _MeowVideoPlayerState extends State<MeowVideoPlayer> {
  static const Duration _seekCompensationDelay = Duration(milliseconds: 500);

  Player? _player;
  VideoController? _videoController;
  Future<void>? _initializeVideoFuture;
  bool _switchingSource = false; // 串行化切源，避免双音轨窗口
  int _sourceTicket = 0;

  // Cached state for callback synthesis
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasDispatchedPlaybackStarted = false;
  List<AudioTrack> _availableAudioTracks = const [];
  List<SubtitleTrack> _availableSubtitleTracks = const [];
  bool _applyingAudioSelection = false;
  bool _applyingSubtitleSelection = false;

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
    if (oldWidget.audioStreamIndex != widget.audioStreamIndex ||
        !_sameAudioStreams(oldWidget.audioStreams, widget.audioStreams)) {
      // ignore: discarded_futures
      _applyAudioSelection();
    }
    if (oldWidget.subtitleUri != widget.subtitleUri ||
        oldWidget.subtitleTitle != widget.subtitleTitle ||
        oldWidget.subtitleLanguage != widget.subtitleLanguage ||
        oldWidget.disableSubtitleTrack != widget.disableSubtitleTrack ||
        oldWidget.subtitleStreamIndex != widget.subtitleStreamIndex ||
        !_sameSubtitleStreams(oldWidget.subtitleStreams, widget.subtitleStreams)) {
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
    _sourceTicket += 1;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _videoController = null;
    final p = _player;
    _player = null;
    if (p != null) {
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
    _resetPlaybackLifecycleState();

    // 确保底层已初始化（多平台安全）
    MediaKit.ensureInitialized();

    final player = Player(configuration: const PlayerConfiguration());
    final videoController = VideoController(player);

    _player = player;
    _videoController = videoController;
    final sourceTicket = ++_sourceTicket;
    // 暴露底层 Player，便于上层在退出前 await stop()
    widget.onPlayerCreated?.call(player);

    // 监听核心状态流并合成统一回调
    _bindStreams(player);

    _initializeVideoFuture = () async {
      // 打开媒体
      await player.open(
        Media(widget.url, httpHeaders: widget.httpHeaders),
        play: false,
      );
      await _applyAudioSelection(player: player);
      await _applySubtitleSelection(player: player);

      await _seekWithCompensation(
        player,
        widget.initialPosition,
        sourceTicket: sourceTicket,
      );

      // 循环逻辑：单源循环
      if (widget.looping) {
        try {
          player.setPlaylistMode(PlaylistMode.loop);
        } catch (_) {
          // 某些版本不支持，忽略
        }
      }

      if (widget.autoPlay) {
        try {
          await player.play();
        } catch (_) {}
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
    final sourceTicket = ++_sourceTicket;
    try {
      try {
        await player.pause();
      } catch (_) {}
      try {
        await player.stop();
      } catch (_) {}
      _resetPlaybackLifecycleState();
      await player.open(
        Media(url, httpHeaders: widget.httpHeaders),
        play: false,
      );
      await _applyAudioSelection(player: player);
      await _applySubtitleSelection(player: player);
      final pos =
          seekTo ??
          (widget.initialPosition > Duration.zero
              ? widget.initialPosition
              : Duration.zero);
      await _seekWithCompensation(player, pos, sourceTicket: sourceTicket);
      if (widget.looping) {
        try {
          player.setPlaylistMode(PlaylistMode.loop);
        } catch (_) {}
      }
      if (widget.autoPlay) {
        try {
          await player.play();
        } catch (_) {}
      }
    } finally {
      _switchingSource = false;
    }
    if (!mounted) return;
    setState(() {});
  }

  final List<StreamSubscription> _subscriptions = [];

  void _resetPlaybackLifecycleState() {
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isBuffering = false;
    _hasDispatchedPlaybackStarted = false;
  }

  Future<void> _seekWithCompensation(
    Player player,
    Duration target, {
    required int sourceTicket,
  }) async {
    if (target <= Duration.zero) {
      return;
    }
    await _seekIfStillActive(player, target, sourceTicket: sourceTicket);
    // ignore: discarded_futures
    _runCompensationSeek(player, target, sourceTicket: sourceTicket);
  }

  Future<void> _runCompensationSeek(
    Player player,
    Duration target, {
    required int sourceTicket,
  }) async {
    await Future.delayed(_seekCompensationDelay);
    await _seekIfStillActive(player, target, sourceTicket: sourceTicket);
  }

  Future<void> _seekIfStillActive(
    Player player,
    Duration target, {
    required int sourceTicket,
  }) async {
    if (!mounted || _player != player || _sourceTicket != sourceTicket) {
      return;
    }
    try {
      await player.seek(target);
    } catch (_) {}
  }

  Future<void> _applySubtitleSelection({Player? player}) async {
    final target = player ?? _player;
    if (target == null || !_usesFlutterRenderer) {
      return;
    }
    if (_applyingSubtitleSelection) {
      return;
    }
    _applyingSubtitleSelection = true;
    try {
      final subtitleUri = widget.subtitleUri?.trim();
      final desiredIndex = widget.subtitleStreamIndex;
      if (kDebugMode) {
        debugPrint(
          '[Diag][MeowVideoPlayer] subtitle:apply | '
          'uri=${subtitleUri ?? ''}, title=${widget.subtitleTitle ?? ''}, '
          'language=${widget.subtitleLanguage ?? ''}, '
          'disable=${widget.disableSubtitleTrack}, '
          'streamIndex=${desiredIndex ?? -1}',
        );
      }
      if (subtitleUri != null && subtitleUri.isNotEmpty) {
        await target.setSubtitleTrack(
          SubtitleTrack.uri(
            subtitleUri,
            title: widget.subtitleTitle,
            language: widget.subtitleLanguage,
          ),
        );
        if (kDebugMode) {
          debugPrint(
            '[Diag][MeowVideoPlayer] subtitle:external_loaded | '
            'uri=$subtitleUri',
          );
        }
        return;
      }
      if (widget.disableSubtitleTrack) {
        await target.setSubtitleTrack(SubtitleTrack.no());
        if (kDebugMode) {
          debugPrint(
            '[Diag][MeowVideoPlayer] subtitle:disabled_explicit',
          );
        }
        return;
      }
      if (desiredIndex != null && desiredIndex >= 0) {
        final desiredPosition = widget.subtitleStreams.indexWhere(
          (stream) => stream.index == desiredIndex,
        );
        if (desiredPosition >= 0) {
          final localTracks = await _waitForSelectableSubtitleTracks(target);
          final matchedTrack = _matchLocalSubtitleTrack(
            targetStream: widget.subtitleStreams[desiredPosition],
            desiredPosition: desiredPosition,
            localTracks: localTracks,
          );
          if (matchedTrack != null) {
            await target.setSubtitleTrack(matchedTrack);
            if (kDebugMode) {
              debugPrint(
                '[Diag][MeowVideoPlayer] subtitle:internal_selected | '
                'streamIndex=$desiredIndex, trackId=${matchedTrack.id}, '
                'title=${matchedTrack.title}, codec=${matchedTrack.codec}',
              );
            }
            return;
          }
          if (kDebugMode) {
            final tracksSummary = localTracks
                .map(
                  (track) =>
                      '{id=${track.id}, title=${track.title ?? ''}, '
                      'lang=${track.language ?? ''}, codec=${track.codec ?? ''}}',
                )
                .join(', ');
            debugPrint(
              '[Diag][MeowVideoPlayer] subtitle:internal_not_found | '
              'streamIndex=$desiredIndex, localCount=${localTracks.length}, '
              'targetTitle=${widget.subtitleStreams[desiredPosition].title}, '
              'targetLang=${widget.subtitleStreams[desiredPosition].language ?? ''}, '
              'targetCodec=${widget.subtitleStreams[desiredPosition].codec ?? ''}, '
              'tracks=[$tracksSummary]',
            );
          }
          await target.setSubtitleTrack(SubtitleTrack.no());
          if (kDebugMode) {
            debugPrint(
              '[Diag][MeowVideoPlayer] subtitle:disabled_no_match | '
              'streamIndex=$desiredIndex',
            );
          }
          return;
        }
      }
      await target.setSubtitleTrack(SubtitleTrack.no());
      if (kDebugMode) {
        debugPrint(
          '[Diag][MeowVideoPlayer] subtitle:disabled_fallback',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[Diag][MeowVideoPlayer] subtitle:failed | error=$error',
        );
      }
    } finally {
      _applyingSubtitleSelection = false;
    }
  }

  Future<void> _applyAudioSelection({Player? player}) async {
    final target = player ?? _player;
    if (target == null || !_usesFlutterRenderer) {
      return;
    }
    if (_applyingAudioSelection) {
      return;
    }
    _applyingAudioSelection = true;

    try {
      final desiredIndex = widget.audioStreamIndex;
      if (desiredIndex == null) {
        try {
          await target.setAudioTrack(AudioTrack.auto());
        } catch (_) {}
        return;
      }

      final desiredPosition = widget.audioStreams.indexWhere(
        (stream) => stream.index == desiredIndex,
      );
      if (desiredPosition < 0) {
        return;
      }

      final localTracks = await _waitForSelectableAudioTracks(target);
      if (localTracks.isEmpty) {
        return;
      }

      final matchedTrack = _matchLocalAudioTrack(
        targetStream: widget.audioStreams[desiredPosition],
        desiredPosition: desiredPosition,
        localTracks: localTracks,
      );
      if (matchedTrack == null) {
        return;
      }

      try {
        await target.setAudioTrack(matchedTrack);
      } catch (_) {}
    } finally {
      _applyingAudioSelection = false;
    }
  }

  Future<List<AudioTrack>> _waitForSelectableAudioTracks(Player player) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final available = _extractSelectableAudioTracks(player.state.tracks.audio);
      if (available.isNotEmpty) {
        _availableAudioTracks = available;
        return available;
      }
      if (_availableAudioTracks.isNotEmpty) {
        return _availableAudioTracks;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return _availableAudioTracks;
  }

  List<AudioTrack> _extractSelectableAudioTracks(List<AudioTrack> tracks) {
    return tracks
        .where((track) => track.id != 'auto' && track.id != 'no' && !track.uri)
        .toList(growable: false);
  }

  Future<List<SubtitleTrack>> _waitForSelectableSubtitleTracks(
    Player player,
  ) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final available = _extractSelectableSubtitleTracks(
        player.state.tracks.subtitle,
      );
      if (available.isNotEmpty) {
        _availableSubtitleTracks = available;
        return available;
      }
      if (_availableSubtitleTracks.isNotEmpty) {
        return _availableSubtitleTracks;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return _availableSubtitleTracks;
  }

  List<SubtitleTrack> _extractSelectableSubtitleTracks(
    List<SubtitleTrack> tracks,
  ) {
    return tracks
        .where(
          (track) =>
              track.id != 'auto' &&
              track.id != 'no' &&
              !track.uri &&
              !track.data,
        )
        .toList(growable: false);
  }

  AudioTrack? _matchLocalAudioTrack({
    required PlaybackStream targetStream,
    required int desiredPosition,
    required List<AudioTrack> localTracks,
  }) {
    String normalize(String? value) => (value ?? '').trim().toLowerCase();

    final targetTitle = normalize(targetStream.title);
    final targetLanguage = normalize(targetStream.language);
    final targetCodec = normalize(targetStream.codec);

    for (final track in localTracks) {
      if (targetTitle.isNotEmpty &&
          normalize(track.title).isNotEmpty &&
          normalize(track.title) == targetTitle) {
        return track;
      }
    }

    for (final track in localTracks) {
      final languageMatches =
          targetLanguage.isNotEmpty && normalize(track.language) == targetLanguage;
      final codecMatches =
          targetCodec.isNotEmpty && normalize(track.codec) == targetCodec;
      final bitrateMatches = targetStream.bitrate != null &&
          track.bitrate != null &&
          (track.bitrate! - targetStream.bitrate!).abs() <= 32000;
      if ((languageMatches && codecMatches) ||
          (languageMatches && bitrateMatches) ||
          (codecMatches && bitrateMatches)) {
        return track;
      }
    }

    if (desiredPosition >= 0 && desiredPosition < localTracks.length) {
      return localTracks[desiredPosition];
    }
    return null;
  }

  SubtitleTrack? _matchLocalSubtitleTrack({
    required PlaybackStream targetStream,
    required int desiredPosition,
    required List<SubtitleTrack> localTracks,
  }) {
    String normalize(String? value) => (value ?? '').trim().toLowerCase();

    final targetTitle = normalize(targetStream.title);
    final targetLanguage = normalize(targetStream.language);
    final targetCodec = normalize(targetStream.codec);

    for (final track in localTracks) {
      if (targetTitle.isNotEmpty &&
          normalize(track.title).isNotEmpty &&
          normalize(track.title) == targetTitle) {
        return track;
      }
    }

    for (final track in localTracks) {
      final languageMatches =
          targetLanguage.isNotEmpty && normalize(track.language) == targetLanguage;
      final codecMatches =
          targetCodec.isNotEmpty && normalize(track.codec) == targetCodec;
      if ((languageMatches && codecMatches) || languageMatches || codecMatches) {
        return track;
      }
    }

    if (desiredPosition >= 0 && desiredPosition < localTracks.length) {
      return localTracks[desiredPosition];
    }
    return null;
  }

  bool _sameAudioStreams(
    List<PlaybackStream> left,
    List<PlaybackStream> right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      final l = left[index];
      final r = right[index];
      if (l.index != r.index ||
          l.title != r.title ||
          l.language != r.language ||
          l.codec != r.codec ||
          l.bitrate != r.bitrate) {
        return false;
      }
    }
    return true;
  }

  bool _sameSubtitleStreams(
    List<PlaybackStream> left,
    List<PlaybackStream> right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      final l = left[index];
      final r = right[index];
      if (l.index != r.index ||
          l.title != r.title ||
          l.language != r.language ||
          l.codec != r.codec ||
          l.deliveryUrl != r.deliveryUrl ||
          l.isTextSubtitleStream != r.isTextSubtitleStream) {
        return false;
      }
    }
    return true;
  }

  void _bindStreams(Player player) {
    void emit() {
      final duration = _duration;
      final position = _position;
      final completionThreshold = duration > const Duration(milliseconds: 600)
          ? duration - const Duration(milliseconds: 600)
          : duration;
      final status = MeowVideoPlaybackStatus(
        position: position,
        duration: duration,
        isInitialized: duration > Duration.zero,
        isPlaying: _isPlaying,
        isBuffering: _isBuffering,
        isCompleted:
            duration > Duration.zero &&
            position >= completionThreshold &&
            !_isPlaying,
      );
      _maybeDispatchPlaybackStarted(status);
      widget.onPlaybackStatusChanged?.call(status);
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
      player.stream.tracks.listen((tracks) {
        final previousAudioCount = _availableAudioTracks.length;
        final previousSubtitleCount = _availableSubtitleTracks.length;
        _availableAudioTracks = _extractSelectableAudioTracks(tracks.audio);
        _availableSubtitleTracks = _extractSelectableSubtitleTracks(
          tracks.subtitle,
        );
        if (kDebugMode) {
          final subtitleTracksSummary = _availableSubtitleTracks
              .map(
                (track) =>
                    '{id=${track.id}, title=${track.title ?? ''}, '
                    'lang=${track.language ?? ''}, codec=${track.codec ?? ''}}',
              )
              .join(', ');
          debugPrint(
            '[Diag][MeowVideoPlayer] tracks:update | '
            'audio=${_availableAudioTracks.length}, '
            'subtitle=${_availableSubtitleTracks.length}, '
            'subtitleTracks=[$subtitleTracksSummary]',
          );
        }
        if (previousAudioCount == 0 &&
            _availableAudioTracks.isNotEmpty &&
            widget.audioStreamIndex != null) {
          // ignore: discarded_futures
          _applyAudioSelection(player: player);
        }
        if (previousSubtitleCount == 0 &&
            _availableSubtitleTracks.isNotEmpty &&
            (widget.subtitleStreamIndex ?? -1) >= 0 &&
            (widget.subtitleUri?.trim().isEmpty ?? true)) {
          // ignore: discarded_futures
          _applySubtitleSelection(player: player);
        }
      }),
    ]);
  }

  void _maybeDispatchPlaybackStarted(MeowVideoPlaybackStatus status) {
    if (_hasDispatchedPlaybackStarted) {
      return;
    }
    if (!status.isInitialized || !status.isPlaying) {
      return;
    }
    _hasDispatchedPlaybackStarted = true;
    widget.onPlaybackStarted?.call(status);
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
        final playerContent = Container(
          color: Colors.black,
          child: _videoController != null
              ? Video(
                  controller: _videoController!,
                  // 交给 media_kit 内部根据帧率/时钟同步渲染，通常能改善音画同步
                  fit: widget.fit,
                )
              : const _VideoLoadingState(),
        );

        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: widget.expandToFill
              ? SizedBox.expand(child: playerContent)
              : AspectRatio(aspectRatio: aspectRatio, child: playerContent),
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
