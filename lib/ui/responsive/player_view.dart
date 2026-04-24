import 'package:flutter/material.dart';
// debugPrint is available via material.dart import
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/usecases/get_playback_plan.dart';
// ✅ 确保导入了 Repository 接口
import '../../domain/repositories/i_media_service_manager.dart';
import '../../domain/repositories/playback_repository.dart';
import '../../domain/entities/media_service_config.dart';
import '../atoms/meow_video_player.dart';
// subtitles selection removed on player page
import '../mobile/player/mobile_player_screen.dart';
import '../tablet/player/tablet_player_screen.dart';
import 'responsive_layout_builder.dart';

class PlayerView extends StatefulWidget {
  const PlayerView({
    super.key,
    required this.mediaItem,
    this.openTrackSelectorOnStart = false,
  });

  static const String routePath = '/player/:id';

  static String locationFor(int id) => '/player/$id';

  final MediaItem mediaItem;
  final bool openTrackSelectorOnStart;

  @override
  State<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<PlayerView> {
  static const List<PlayerResolutionOption> _resolutionOptions = [
    PlayerResolutionOption(
      label: 'Auto',
      maxStreamingBitrate: 1000 * 1000 * 1000,
    ),
    PlayerResolutionOption(
      label: '1080P',
      maxStreamingBitrate: 8 * 1000 * 1000,
    ),
    PlayerResolutionOption(label: '720P', maxStreamingBitrate: 4 * 1000 * 1000),
    PlayerResolutionOption(label: '480P', maxStreamingBitrate: 2 * 1000 * 1000),
  ];

  late final Duration _initialPosition;
  // Child widget handles persistence; keep for potential UI reactions.
  // ignore: unused_field
  MeowVideoPlaybackStatus? _latestStatus;
  PlaybackPlan? _plan;
  String? _currentUrl; // url with track parameters applied
  Duration? _resumePositionOverride;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  String? _selectedSubtitleUri;
  String? _selectedSubtitleTitle;
  String? _selectedSubtitleLanguage;
  PlayerResolutionOption _selectedResolution = _resolutionOptions.first;
  bool _openSelectorPending = false;
  int _serverSeekRequestToken = 0;
  bool _isPreparingPlan = true;
  String? _planErrorMessage;

  bool get _hasStrictPlaybackPlan {
    final plan = _plan;
    final url = _currentUrl ?? plan?.url;
    final playSessionId = plan?.playSessionId;
    return plan != null &&
        url != null &&
        url.isNotEmpty &&
        playSessionId != null &&
        playSessionId.isNotEmpty;
  }

  PlaybackStream? get _selectedSubtitleStream {
    final plan = _plan;
    final subtitleIndex = _selectedSubtitleIndex;
    if (plan == null || subtitleIndex == null || subtitleIndex < 0) {
      return null;
    }
    for (final stream in plan.subtitleStreams) {
      if (stream.index == subtitleIndex) {
        return stream;
      }
    }
    return null;
  }

  bool get _shouldDisablePlayerSubtitleTrack {
    final subtitleIndex = _selectedSubtitleIndex;
    if (subtitleIndex != null && subtitleIndex < 0) {
      return true;
    }
    if ((_selectedSubtitleUri ?? '').trim().isNotEmpty) {
      return false;
    }
    final stream = _selectedSubtitleStream;
    if (stream != null && !_isTextSubtitle(stream)) {
      return true;
    }
    return false;
  }

  String? get _selectedExternalSubtitleUri {
    final savedUri = _selectedSubtitleUri?.trim();
    if (savedUri != null && savedUri.isNotEmpty) {
      return savedUri;
    }
    final stream = _selectedSubtitleStream;
    if (stream == null || !_isTextSubtitle(stream)) {
      return null;
    }
    final uri = stream.deliveryUrl?.trim();
    if (uri == null || uri.isEmpty) {
      return null;
    }
    return uri;
  }

  bool _isTextSubtitle(PlaybackStream stream) {
    if (stream.isTextSubtitleStream) {
      return true;
    }
    final codec = stream.codec?.toLowerCase();
    return codec != null &&
        const ['srt', 'subrip', 'ass', 'ssa', 'webvtt', 'vtt'].contains(codec);
  }

  String? _audioStreamDetail(PlaybackStream stream) {
    final segments = <String>[
      if (stream.language?.isNotEmpty == true) stream.language!,
      if (stream.codec?.isNotEmpty == true) stream.codec!.toUpperCase(),
      if (stream.channels != null) '${stream.channels} 声道',
      if (stream.bitrate != null) '${(stream.bitrate! / 1000).round()} kbps',
      if (stream.isDefault) '默认',
    ];
    return segments.isEmpty ? null : segments.join(' · ');
  }

  String? _subtitleStreamDetail(PlaybackStream stream) {
    final segments = <String>[
      if (stream.language?.isNotEmpty == true) stream.language!,
      if (stream.codec?.isNotEmpty == true) stream.codec!.toUpperCase(),
      if (stream.isExternal) '外挂',
      if (stream.isDefault) '默认',
    ];
    return segments.isEmpty ? null : segments.join(' · ');
  }

  @override
  void initState() {
    super.initState();
    final savedProgress = context
        .read<UserDataProvider>()
        .playbackProgressForItem(widget.mediaItem);
    _initialPosition = savedProgress?.position ?? Duration.zero;
    debugPrint(
      '[Resume][PlayerView][Init] item=${widget.mediaItem.dataSourceId} '
      'initialPosition=${_initialPosition.inMilliseconds}ms '
      'savedDuration=${savedProgress?.duration.inMilliseconds ?? 0}ms',
    );
    _openSelectorPending = widget.openTrackSelectorOnStart;
    _preparePlaybackPlan();
  }

  Future<void> _preparePlaybackPlan() async {
    if (mounted) {
      setState(() {
        _isPreparingPlan = true;
        _planErrorMessage = null;
      });
    }
    final manager = context.read<IMediaServiceManager>();
    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _currentUrl = null;
        _isPreparingPlan = false;
        _planErrorMessage = 'Emby 播放配置不可用';
      });
      return;
    }
    try {
      final saved = context.read<UserDataProvider>().trackSelectionForItem(
        widget.mediaItem,
      );
      // 在 _preparePlaybackPlan 中
final plan = await _fetchPlaybackPlan(
  audioIndex: saved?.audioIndex,
  subtitleIndex: saved?.subtitleIndex, // 👈 确保这个也传进去了
);
      _assertStrictPlan(plan);
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _selectedAudioIndex = saved?.audioIndex;
        _selectedSubtitleIndex = saved?.subtitleIndex;
        _selectedSubtitleUri = saved?.subtitleUri;
        _selectedSubtitleTitle = saved?.subtitleTitle;
        _selectedSubtitleLanguage = saved?.subtitleLanguage;
        _currentUrl = plan.url;
        _isPreparingPlan = false;
        _planErrorMessage = null;

        // 播放页不再处理字幕/音轨选择
      });

      if (_openSelectorPending && mounted) {
        _openSelectorPending = false;
        await _openTrackSelector();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _plan = null;
        _currentUrl = null;
        _isPreparingPlan = false;
        _planErrorMessage = error.toString();
      });
    }
  }

  void _assertStrictPlan(PlaybackPlan plan) {
    if (plan.url.trim().isEmpty) {
      throw StateError('PlaybackInfo 未返回可用播放地址');
    }
    final playSessionId = plan.playSessionId?.trim();
    if (playSessionId == null || playSessionId.isEmpty) {
      throw StateError('PlaybackInfo 未返回有效 PlaySessionId');
    }
  }

  Future<PlaybackPlan> _fetchPlaybackPlan({
    int? audioIndex,
    int? subtitleIndex,
    int? maxStreamingBitrate,
    String? playSessionIdOverride,
    Duration? startPositionOverride,
  }) async {
    // ✅ 关键：直接从 context 读取注入好的抽象接口
    // 这将自动获取 main.dart 中配置的 EmbyPlaybackRepositoryImpl
    final repo = context.read<PlaybackRepository>();
    final usecase = GetPlaybackPlanUseCase(repo);
    return usecase(
      widget.mediaItem,
      maxStreamingBitrate:
          maxStreamingBitrate ?? _selectedResolution.maxStreamingBitrate,
      subtitleStreamIndex: subtitleIndex,
      playSessionId: playSessionIdOverride ?? _plan?.playSessionId,
      startPosition:
          startPositionOverride ?? _resumePositionOverride ?? _initialPosition,
    );
  }

  Future<void> _openTrackSelector() async {
    final plan = _plan;
    if (plan == null) return;
    int? tempAudio = _selectedAudioIndex ??
        (plan.audioStreams.isNotEmpty ? plan.audioStreams.first.index : null);
    int? tempSub = _selectedSubtitleIndex;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择音轨', style: Theme.of(ctx).textTheme.titleMedium),
                    ...plan.audioStreams.map(
                      (s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        minLeadingWidth: 24,
                        horizontalTitleGap: 12,
                        leading: Icon(
                          tempAudio == s.index
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(s.title),
                        subtitle: _audioStreamDetail(s) == null
                            ? null
                            : Text(_audioStreamDetail(s)!),
                        onTap: () => modalSetState(() => tempAudio = s.index),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('选择字幕', style: Theme.of(ctx).textTheme.titleMedium),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      minLeadingWidth: 24,
                      horizontalTitleGap: 12,
                      leading: Icon(
                        (tempSub ?? -1) == -1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: const Text('无字幕'),
                      onTap: () => modalSetState(() => tempSub = -1),
                    ),
                    ...plan.subtitleStreams.map(
                      (s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        minLeadingWidth: 24,
                        horizontalTitleGap: 12,
                        leading: Icon(
                          (tempSub ?? -1) == s.index
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(s.title),
                        subtitle: _subtitleStreamDetail(s) == null
                            ? null
                            : Text(_subtitleStreamDetail(s)!),
                        onTap: () => modalSetState(() => tempSub = s.index),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _applyTrackSelection(
                            audioIndex: tempAudio,
                            subtitleIndex: tempSub,
                          );
                        },
                        child: const Text('应用'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handlePlaybackStatusChanged(MeowVideoPlaybackStatus status) {
    _latestStatus = status;
  }

  Future<void> _applyTrackSelection({
    int? audioIndex,
    int? subtitleIndex,
  }) async {
    final effectiveAudioIndex = audioIndex ??
        (_plan != null && _plan!.audioStreams.isNotEmpty
            ? _plan!.audioStreams.first.index
            : null);
    PlaybackStream? selectedAudioStream;
    if (effectiveAudioIndex != null) {
      for (final stream in _plan?.audioStreams ?? const <PlaybackStream>[]) {
        if (stream.index == effectiveAudioIndex) {
          selectedAudioStream = stream;
          break;
        }
      }
    }
    PlaybackStream? selectedSubtitleStream;
    if (subtitleIndex != null && subtitleIndex >= 0) {
      for (final stream in _plan?.subtitleStreams ?? const <PlaybackStream>[]) {
        if (stream.index == subtitleIndex) {
          selectedSubtitleStream = stream;
          break;
        }
      }
    }
    context.read<UserDataProvider>().setTrackSelectionForItem(
      widget.mediaItem,
      audioIndex: effectiveAudioIndex,
      subtitleIndex: subtitleIndex,
      audioTitle: selectedAudioStream?.title,
      subtitleTitle: selectedSubtitleStream?.title,
      subtitleLanguage: selectedSubtitleStream?.language,
      subtitleUri: selectedSubtitleStream?.deliveryUrl,
    );
    setState(() {
      _selectedAudioIndex = effectiveAudioIndex;
      _selectedSubtitleIndex = subtitleIndex;
      _selectedSubtitleUri = selectedSubtitleStream?.deliveryUrl;
      _selectedSubtitleTitle = selectedSubtitleStream?.title;
      _selectedSubtitleLanguage = selectedSubtitleStream?.language;
    });
  }

  Future<void> _applyResolutionSelection(PlayerResolutionOption option) async {
    _resumePositionOverride =
        _latestStatus?.position ?? _resumePositionOverride;
    final nextPlan = await _fetchPlaybackPlan(
      audioIndex: _selectedAudioIndex,
      subtitleIndex: _selectedSubtitleIndex,
      maxStreamingBitrate: option.maxStreamingBitrate,
    );
    _assertStrictPlan(nextPlan);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedResolution = option;
      _plan = nextPlan;
      _currentUrl = nextPlan.url;
    });
  }

  Future<void> _handleServerSeek(Duration target) async {
    _resumePositionOverride = target;
    final currentPlan = _plan;
    if (currentPlan == null || !currentPlan.isTranscoding) {
      return;
    }

    final requestToken = ++_serverSeekRequestToken;
    final nextPlan = await _fetchPlaybackPlan(
      audioIndex: _selectedAudioIndex,
      subtitleIndex: _selectedSubtitleIndex,
      maxStreamingBitrate: _selectedResolution.maxStreamingBitrate,
      startPositionOverride: target,
    );
    _assertStrictPlan(nextPlan);
    if (!mounted || requestToken != _serverSeekRequestToken) {
      return;
    }

    setState(() {
      _plan = nextPlan;
      _currentUrl = nextPlan.url;
    });
  }

  @override
  Widget build(BuildContext context) {
    // If query contains tracks=1, open selector on start
    final uri = Uri
        .base; // GoRouter uses browser-style routing in Flutter web; on mobile this is inert
    final shouldOpenSelector =
        uri.queryParameters['tracks'] == '1' || widget.openTrackSelectorOnStart;
    if (shouldOpenSelector && !_openSelectorPending) {
      _openSelectorPending =
          true; // will trigger after plan ready in _preparePlaybackPlan
    }
    final selectedServer = context.select<AppProvider, MediaServerInfo>(
      (provider) => provider.selectedServer,
    );
    final savedProgress = context
        .select<UserDataProvider, MediaPlaybackProgress?>(
          (provider) => provider.playbackProgressForItem(widget.mediaItem),
        );

    if (_isPreparingPlan) {
      return const _StrictPlaybackLoadingView();
    }
    if (!_hasStrictPlaybackPlan) {
      return _StrictPlaybackErrorView(
        message: _planErrorMessage ?? '未获取到有效的播放会话',
        onRetry: _preparePlaybackPlan,
      );
    }

    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) {
        return MobilePlayerScreen(
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _resumePositionOverride ?? _initialPosition,
          isTranscoding: _plan!.isTranscoding,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
          onServerSeekRequested: _handleServerSeek,
          playUrlOverride: _currentUrl ?? _plan!.url,
          onShowTrackSelector: null,
          resolutionOptions: _resolutionOptions,
          selectedResolution: _selectedResolution,
          onResolutionSelected: _applyResolutionSelection,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle:
              _selectedSubtitleTitle ?? _selectedSubtitleStream?.title,
          subtitleLanguage:
              _selectedSubtitleLanguage ?? _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
          playSessionId: _plan!.playSessionId,
          mediaSourceId: _plan!.mediaSourceId,
          audioStreamIndex: _selectedAudioIndex,
          subtitleStreamIndex: _selectedSubtitleIndex,
          audioStreams: _plan!.audioStreams,
        );
      },
      tabletBuilder: (context, maxWidth) {
        return TabletPlayerScreen(
          maxWidth: maxWidth,
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _resumePositionOverride ?? _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
          playUrlOverride: _currentUrl ?? _plan!.url,
          onShowTrackSelector: null,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle:
              _selectedSubtitleTitle ?? _selectedSubtitleStream?.title,
          subtitleLanguage:
              _selectedSubtitleLanguage ?? _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
          playSessionId: _plan!.playSessionId,
          mediaSourceId: _plan!.mediaSourceId,
          audioStreamIndex: _selectedAudioIndex,
          subtitleStreamIndex: _selectedSubtitleIndex,
          audioStreams: _plan!.audioStreams,
        );
      },
    );
  }
}

class _StrictPlaybackLoadingView extends StatelessWidget {
  const _StrictPlaybackLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在建立播放会话...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _StrictPlaybackErrorView extends StatelessWidget {
  const _StrictPlaybackErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                '播放会话创建失败',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  // ignore: discarded_futures
                  onRetry();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
