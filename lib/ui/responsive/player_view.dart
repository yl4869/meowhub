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
  late final Duration _initialPosition;
  // Child widget handles persistence; keep for potential UI reactions.
  // ignore: unused_field
  MeowVideoPlaybackStatus? _latestStatus;
  PlaybackPlan? _plan;
  String? _currentUrl; // url with track parameters applied
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  bool _openSelectorPending = false;

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
  }) async {
    final repo = _buildPlaybackRepository();
    final usecase = GetPlaybackPlanUseCase(repo);
    return usecase(
      widget.mediaItem,
      maxStreamingBitrate: 10 * 1000 * 1000,
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
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择音轨', style: Theme.of(ctx).textTheme.titleMedium),
                ...plan.audioStreams.map(
                  (s) => RadioListTile<int>(
                    title: Text(s.title),
                    subtitle: Text(
                      (s.language ?? '') +
                          (s.codec != null ? ' · ${s.codec}' : ''),
                    ),
                    value: s.index,
                    groupValue: tempAudio,
                    onChanged: (v) => setState(() => tempAudio = v),
                  ),
                ),
                const SizedBox(height: 8),
                Text('选择字幕', style: Theme.of(ctx).textTheme.titleMedium),
                RadioListTile<int>(
                  title: const Text('无字幕'),
                  value: -1,
                  groupValue: tempSub ?? -1,
                  onChanged: (v) => setState(() => tempSub = v),
                ),
                ...plan.subtitleStreams.map(
                  (s) => RadioListTile<int>(
                    title: Text(s.title),
                    value: s.index,
                    groupValue: tempSub ?? -1,
                    onChanged: (v) => setState(() => tempSub = v),
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
          initialPosition: _initialPosition,
          onPlaybackStatusChanged: _handlePlaybackStatusChanged,
          playUrlOverride: _currentUrl ?? _plan?.url,
          onShowTrackSelector: null,
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
        );
      },
    );
  }
}
