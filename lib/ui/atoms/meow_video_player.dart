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
    this.onPlayerError,
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
  final ValueChanged<String>? onPlayerError;

  @override
  State<MeowVideoPlayer> createState() => _MeowVideoPlayerState();
}

class _MeowVideoPlayerState extends State<MeowVideoPlayer> {
  Player? _player;
  VideoController? _videoController;
  Future<void>? _initializeVideoFuture;
  bool _switchingSource = false; // 串行化切源，避免双音轨窗口
  String? _pendingUrl; // 切源过程中又收到新 URL，等当前完成后再切

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

  static const _subtitleViewConfig = SubtitleViewConfiguration(
    style: TextStyle(
      fontSize: 30.0,
      height: 1.4,
      letterSpacing: 0.5,
      wordSpacing: 1.0,
      color: Color(0xFFFFFFFF),
      fontWeight: FontWeight.w600,
      shadows: [
        // 三层阴影实现清晰描边效果，确保在任何背景上可读
        Shadow(blurRadius: 6.0, color: Color(0xE6000000)),
        Shadow(blurRadius: 2.0, color: Color(0xFF000000)),
        Shadow(offset: Offset(0, 1), blurRadius: 0, color: Color(0xFF000000)),
      ],
      backgroundColor: Color(0x73000000),
    ),
    textAlign: TextAlign.center,
    padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 40.0),
  );

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
    if (_needsNativeSubtitleRendering(oldWidget) !=
        _needsNativeSubtitleRendering(widget)) {
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
        !_sameSubtitleStreams(
          oldWidget.subtitleStreams,
          widget.subtitleStreams,
        )) {
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
    _availableAudioTracks = const [];
    _availableSubtitleTracks = const [];
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

    final needsNativeSubtitleRendering = _needsNativeSubtitleRendering(widget);
    final player = Player(
      configuration: PlayerConfiguration(libass: needsNativeSubtitleRendering),
    );
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
        play: false,
      );
      // 1. 预热解码器（仅唤醒，不 seek）
      await _warmDecoder(player);
      // 2. 设置音轨/字幕（可能在内部重置解码器状态）
      _debugSubtitleState('after_open_before_apply', player);
      await _applyAudioSelection(player: player);
      await _applySubtitleSelection(player: player);
      // 3. 所有轨道设置完毕后，最终执行 seek 并验证位置
      await _seekWithVerify(player, widget.initialPosition, autoPlay: false);

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
    if (_switchingSource) {
      // 当前正在切源，暂存新 URL 等当前操作完成后再切
      _pendingUrl = url;
      return;
    }
    _switchingSource = true;
    try {
      await _doReopen(player, url, seekTo: seekTo);
    } finally {
      _switchingSource = false;
    }
    // 处理切源过程中积压的新请求
    final pending = _pendingUrl;
    _pendingUrl = null;
    if (pending != null && pending != url && mounted) {
      // 使用最新的积压 URL 再次执行切源
      await _reopenOnSamePlayer(url: pending, seekTo: seekTo);
      return;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _doReopen(
    Player player,
    String url, {
    Duration? seekTo,
  }) async {
    _resetPlaybackLifecycleState();
    try {
      // stop() 确保前一媒体源完全释放（Web 平台 WASM 解码器需此步骤），
      // 等待一小段时间让播放器内部状态机完成转换，避免 stop/ open 竞态
      try {
        await player.stop();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 150));
      await player.open(
        Media(url, httpHeaders: widget.httpHeaders),
        play: false,
      );
    } catch (e) {
      // open() 失败，通知上层；不在此重建播放器，避免用同一 URL 死循环
      // 播放器保持前一源的停止状态，上层通过 onPlayerError 展示错误并提供恢复路径
      if (mounted && widget.onPlayerError != null) {
        widget.onPlayerError!(e.toString());
      }
      // 清掉积压 URL，避免在异常状态下继续切源
      _pendingUrl = null;
      return;
    }
    final startPosition =
        seekTo ??
        (widget.initialPosition > Duration.zero
            ? widget.initialPosition
            : Duration.zero);
    // 1. 预热解码器（仅唤醒，不 seek）
    await _warmDecoder(player);
    // 2. 设置音轨/字幕（可能在内部重置解码器状态）
    _debugSubtitleState('after_reopen_before_apply', player);
    await _applyAudioSelection(player: player);
    await _applySubtitleSelection(player: player);
    // 3. 所有轨道设置完毕后，最终执行 seek 并验证位置
    await _seekWithVerify(player, startPosition, autoPlay: false);

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
  }

  final List<StreamSubscription> _subscriptions = [];

  void _resetPlaybackLifecycleState() {
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isBuffering = false;
    _hasDispatchedPlaybackStarted = false;
  }

  /// 仅预热解码器（不 seek），确保后续 seek 不会因解码器未就绪被无声丢弃。
  /// play() → 等待 position > 0 → pause()
  Future<void> _warmDecoder(Player player) async {
    try {
      await player.play();
    } catch (_) {}
    try {
      await player.stream.position
          .firstWhere((p) => p > Duration.zero)
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    try {
      await player.pause();
    } catch (_) {}
  }

  /// 在解码器已预热、所有轨道已设置完毕后执行 seek，并通过 player.state.position
  /// 验证实际位置。若位置偏差超过 2 秒则重试（最多 3 次）。
  Future<void> _seekWithVerify(
    Player player,
    Duration target, {
    required bool autoPlay,
  }) async {
    if (target <= Duration.zero) {
      if (autoPlay) {
        try { await player.play(); } catch (_) {}
      }
      return;
    }

    const retryCount = 3;
    const retryDelay = Duration(milliseconds: 200);
    const tolerance = Duration(seconds: 2);

    for (var attempt = 1; attempt <= retryCount; attempt++) {
      try {
        await player.seek(target);
      } catch (_) {}

      // 短暂等待解码器处理 seek
      await Future.delayed(retryDelay);

      final actual = player.state.position;
      // 位置已在容差范围内，seek 成功
      if ((actual - target).abs() <= tolerance) break;

      if (attempt < retryCount) {
        // 位置偏差大，再次启动播放保持解码器活跃后重试
        try { await player.play(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!autoPlay) {
      try { await player.pause(); } catch (_) {}
    }
  }

  /// 字幕选择核心逻辑。
  ///
  /// 策略分两类：
  /// - **图形字幕 (PGS)**：由服务端转码烧录或 libass 内部渲染，绝不走外部 URI 加载。
  /// - **文本字幕 (SRT/ASS/WebVTT)**：如果有外挂 URL 则通过 SubtitleTrack.uri 加载；
  ///   否则在内部轨道列表中按 index 匹配。
  Future<void> _applySubtitleSelection({Player? player}) async {
    final target = player ?? _player;
    if (target == null || !_usesFlutterRenderer) return;
    if (_applyingSubtitleSelection) return;
    _applyingSubtitleSelection = true;
    try {
      if (widget.disableSubtitleTrack) {
        await target.setSubtitleTrack(SubtitleTrack.no());
        return;
      }
      _debugSubtitleState('apply_before', target);

      // 判断当前选中字幕的类型
      final selectedStream = _findSubtitleStreamForWidget(widget);
      final isImageSub =
          selectedStream != null && _isImageSubtitleCodec(selectedStream.codec);

      if (isImageSub) {
        // 图形字幕 (PGS)：服务端转码烧录 或 libass 渲染，让 media_kit 自动选择内部轨道
        await target.setSubtitleTrack(SubtitleTrack.auto());
        _debugSubtitleState('apply_after_image_sub_auto', target);
        return;
      }

      // --- 文本字幕 ---

      // 有外部 URL → 加载外挂字幕文件
      final externalUri = widget.subtitleUri?.trim();
      if (externalUri != null && externalUri.isNotEmpty) {
        await target.setSubtitleTrack(
          SubtitleTrack.uri(
            externalUri,
            title: widget.subtitleTitle,
            language: widget.subtitleLanguage,
          ),
        );
        _debugSubtitleState('apply_after_external_uri', target);
        return;
      }

      // 内部文本字幕 → 按 index 匹配
      final desiredIndex = widget.subtitleStreamIndex;
      if (desiredIndex != null) {
        final selectable = _extractSelectableSubtitleTracks(
          target.state.tracks.subtitle,
        );
        final matched = _findSubtitleTrackByIndex(selectable, desiredIndex);
        if (matched != null) {
          await target.setSubtitleTrack(matched);
          _debugSubtitleState('apply_after_matched_index_$desiredIndex', target);
          return;
        }
        await target.setSubtitleTrack(SubtitleTrack.auto());
        _debugSubtitleState(
          'apply_after_no_match_index_${desiredIndex}_auto',
          target,
        );
        return;
      }

      // 无显式选择 → auto
      await target.setSubtitleTrack(SubtitleTrack.auto());
      _debugSubtitleState('apply_after_auto', target);
    } catch (_) {
    } finally {
      _applyingSubtitleSelection = false;
    }
  }

  /// 在本地轨道列表中按 index 查找匹配的 SubtitleTrack
  SubtitleTrack? _findSubtitleTrackByIndex(
    List<SubtitleTrack> tracks,
    int index,
  ) {
    final indexStr = index.toString();
    // 精确匹配: id == "2"
    for (final track in tracks) {
      if (track.id == indexStr) return track;
    }
    // 带前缀匹配: id == "s:2" / "sid:2"
    for (final track in tracks) {
      if (track.id.endsWith(':$indexStr') || track.id.endsWith(' $indexStr')) {
        return track;
      }
    }
    // 按位置匹配（tracks 列表顺序与 stream index 一致）
    final position = tracks.indexWhere((t) {
      final parsed = int.tryParse(t.id);
      return parsed == index;
    });
    if (position >= 0) return tracks[position];
    return null;
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
      final available = _extractSelectableAudioTracks(
        player.state.tracks.audio,
      );
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

  void _debugSubtitleState(String reason, Player player) {
    if (!kDebugMode) {
      return;
    }
    final tracks = player.state.tracks.subtitle;
    final selectable = _extractSelectableSubtitleTracks(tracks);
    debugPrint(
      '[Diag][MeowVideoPlayer] subtitle:$reason | '
      'selected=${_describeSubtitleTrack(player.state.track.subtitle)}, '
      'all=${_describeSubtitleTracks(tracks)}, '
      'selectable=${_describeSubtitleTracks(selectable)}',
    );
  }

  String _describeSubtitleTracks(List<SubtitleTrack> tracks) {
    return [
      for (var index = 0; index < tracks.length; index++)
        _describeSubtitleTrack(tracks[index], position: index),
    ].join(', ');
  }

  String _describeSubtitleTrack(SubtitleTrack track, {int? position}) {
    final parts = <String>[
      if (position != null) 'pos=$position',
      'id=${track.id}',
      'title=${track.title ?? ''}',
      'lang=${track.language ?? ''}',
      'codec=${track.codec ?? ''}',
      'default=${track.isDefault ?? false}',
      'uri=${track.uri}',
      'data=${track.data}',
    ];
    return '{${parts.join(', ')}}';
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
          targetLanguage.isNotEmpty &&
          normalize(track.language) == targetLanguage;
      final codecMatches =
          targetCodec.isNotEmpty && normalize(track.codec) == targetCodec;
      final bitrateMatches =
          targetStream.bitrate != null &&
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

  String _normalizeSubtitleCodec(String? codec) {
    return switch ((codec ?? '').trim().toLowerCase()) {
      'pgs' || 'pgssub' || 'sup' || 'hdmv_pgs_subtitle' => 'pgs',
      'subrip' || 'srt' => 'srt',
      'webvtt' || 'vtt' => 'vtt',
      final String value => value,
    };
  }

  bool _isImageSubtitleCodec(String? codec) {
    return _normalizeSubtitleCodec(codec) == 'pgs';
  }

  bool _needsNativeSubtitleRendering(MeowVideoPlayer widget) {
    if (widget.disableSubtitleTrack) {
      return false;
    }
    final subtitleUri = widget.subtitleUri?.trim();
    if (subtitleUri != null && subtitleUri.isNotEmpty) {
      return false;
    }
    final stream = _findSubtitleStreamForWidget(widget);
    if (stream == null) {
      return false;
    }
    return _isImageSubtitleCodec(stream.codec);
  }

  PlaybackStream? _findSubtitleStreamForWidget(MeowVideoPlayer widget) {
    final desiredIndex = widget.subtitleStreamIndex;
    final subtitleUri = widget.subtitleUri?.trim();
    for (final stream in widget.subtitleStreams) {
      if (desiredIndex != null && stream.index == desiredIndex) {
        return stream;
      }
      final deliveryUrl = stream.deliveryUrl?.trim();
      if (subtitleUri != null &&
          subtitleUri.isNotEmpty &&
          deliveryUrl != null &&
          deliveryUrl == subtitleUri) {
        return stream;
      }
    }
    final normalizedTitle = widget.subtitleTitle?.trim().toLowerCase() ?? '';
    final normalizedLanguage =
        widget.subtitleLanguage?.trim().toLowerCase() ?? '';
    if (normalizedTitle.isEmpty && normalizedLanguage.isEmpty) {
      return null;
    }
    PlaybackStream? languageOnlyMatch;
    for (final stream in widget.subtitleStreams) {
      final streamTitle = stream.title.trim().toLowerCase();
      final streamLanguage = (stream.language ?? '').trim().toLowerCase();
      final titleMatches =
          normalizedTitle.isNotEmpty && streamTitle == normalizedTitle;
      final languageMatches =
          normalizedLanguage.isNotEmpty && streamLanguage == normalizedLanguage;
      if (titleMatches && languageMatches) {
        return stream;
      }
      if (titleMatches) {
        return stream;
      }
      if (languageOnlyMatch == null && languageMatches) {
        languageOnlyMatch = stream;
      }
    }
    return languageOnlyMatch;
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
          l.deliveryMethod != r.deliveryMethod ||
          l.subtitleLocationType != r.subtitleLocationType ||
          l.supportsExternalStream != r.supportsExternalStream ||
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
      player.stream.track.listen((track) {
        if (kDebugMode) {
          debugPrint(
            '[Diag][MeowVideoPlayer] subtitle:selected_update | '
            'selected=${_describeSubtitleTrack(track.subtitle)}',
          );
        }
      }),
      player.stream.error.listen((error) {
        if (mounted && widget.onPlayerError != null) {
          widget.onPlayerError!(error.toString());
        }
      }),
      player.stream.tracks.listen((tracks) {
        final previousAudioCount = _availableAudioTracks.length;
        final previousSubtitleCount = _availableSubtitleTracks.length;
        _availableAudioTracks = _extractSelectableAudioTracks(tracks.audio);
        _availableSubtitleTracks = _extractSelectableSubtitleTracks(
          tracks.subtitle,
        );
        if (kDebugMode) {
          debugPrint(
            '[Diag][MeowVideoPlayer] subtitle:tracks_update | '
            'selected=${_describeSubtitleTrack(player.state.track.subtitle)}, '
            'all=${_describeSubtitleTracks(tracks.subtitle)}, '
            'selectable=${_describeSubtitleTracks(_availableSubtitleTracks)}',
          );
        }
        if (previousAudioCount == 0 &&
            _availableAudioTracks.isNotEmpty &&
            widget.audioStreamIndex != null) {
          // ignore: discarded_futures
          _applyAudioSelection(player: player);
        }
        if (previousSubtitleCount == 0 &&
            _availableSubtitleTracks.length >= 2) {
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
                  fit: widget.fit,
                  subtitleViewConfiguration: _subtitleViewConfig,
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
