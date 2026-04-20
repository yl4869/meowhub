import 'package:flutter/material.dart';
// debugPrint is available via material.dart import
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/usecases/get_playback_plan.dart';
import '../../data/datasources/emby_api_client.dart';
import '../../data/repositories/emby_playback_repository_impl.dart';
import '../../domain/repositories/media_service_manager.dart';
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
      maxStreamingBitrate: 10 * 1000 * 1000,
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
  PlayerResolutionOption _selectedResolution = _resolutionOptions.first;
  bool _openSelectorPending = false;

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
    if (subtitleIndex != null) {
      if (subtitleIndex < 0) {
        return true;
      }
      final stream = _selectedSubtitleStream;
      if (stream != null && !_isTextSubtitle(stream)) {
        return true;
      }
    }
    return false;
  }

  String? get _selectedExternalSubtitleUri {
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

  EmbyPlaybackRepositoryImpl _buildPlaybackRepository() {
    final manager = context.read<MediaServiceManager>();
    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      throw StateError('Emby playback config is unavailable');
    }
    final api = EmbyApiClient(
      config: config,
      securityService: manager.securityService,
      sessionExpiredNotifier: manager.sessionExpiredNotifier,
    );
    return EmbyPlaybackRepositoryImpl(
      apiClient: api,
      securityService: manager.securityService,
    );
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
    final manager = context.read<MediaServiceManager>();
    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      setState(() => _plan = null);
      return;
    }
    final saved = context.read<UserDataProvider>().trackSelectionForItem(
      widget.mediaItem,
    );
    final plan = await _fetchPlaybackPlan(
      audioIndex: saved?.audioIndex,
      subtitleIndex: saved?.subtitleIndex,
    );
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _selectedAudioIndex = saved?.audioIndex;
      _selectedSubtitleIndex = saved?.subtitleIndex;
      _currentUrl = plan.url;

      // 播放页不再处理字幕/音轨选择
    });

    if (_openSelectorPending && mounted) {
      _openSelectorPending = false;
      await _openTrackSelector();
    }
  }

  Future<PlaybackPlan> _fetchPlaybackPlan({
    int? audioIndex,
    int? subtitleIndex,
    int? maxStreamingBitrate,
  }) async {
    final repo = _buildPlaybackRepository();
    final usecase = GetPlaybackPlanUseCase(repo);
    return usecase(
      widget.mediaItem,
      maxStreamingBitrate:
          maxStreamingBitrate ?? _selectedResolution.maxStreamingBitrate,
      requireAvc: true,
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: subtitleIndex,
    );
  }

  Future<void> _openTrackSelector() async {
    final plan = _plan;
    if (plan == null) return;
    int? tempAudio = _selectedAudioIndex;
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
                        leading: Icon(
                          tempAudio == s.index
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(s.title),
                        subtitle: Text(
                          (s.language ?? '') +
                              (s.codec != null ? ' · ${s.codec}' : ''),
                        ),
                        onTap: () => modalSetState(() => tempAudio = s.index),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('选择字幕', style: Theme.of(ctx).textTheme.titleMedium),
                    ListTile(
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
                        leading: Icon(
                          (tempSub ?? -1) == s.index
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(s.title),
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
    _resumePositionOverride =
        _latestStatus?.position ?? _resumePositionOverride;
    final nextPlan = await _fetchPlaybackPlan(
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
    );
    if (!mounted) {
      return;
    }
    context.read<UserDataProvider>().setTrackSelectionForItem(
      widget.mediaItem,
      audioIndex: audioIndex,
      subtitleIndex: subtitleIndex,
    );
    setState(() {
      _plan = nextPlan;
      _selectedAudioIndex = audioIndex;
      _selectedSubtitleIndex = subtitleIndex;
      _currentUrl = nextPlan.url;
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
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedResolution = option;
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

    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) {
        return MobilePlayerScreen(
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _resumePositionOverride ?? _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
          playUrlOverride: _currentUrl ?? _plan?.url,
          onShowTrackSelector: null,
          resolutionOptions: _resolutionOptions,
          selectedResolution: _selectedResolution,
          onResolutionSelected: _applyResolutionSelection,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle: _selectedSubtitleStream?.title,
          subtitleLanguage: _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
        );
      },
      tabletBuilder: (context, maxWidth) {
        return TabletPlayerScreen(
          maxWidth: maxWidth,
          mediaItem: widget.mediaItem,
          selectedServer: selectedServer,
          savedProgress: savedProgress,
          initialPosition: _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
          playUrlOverride: _currentUrl ?? _plan?.url,
          onShowTrackSelector: null,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle: _selectedSubtitleStream?.title,
          subtitleLanguage: _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
        );
      },
    );
  }
}
