import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
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
    // 轻量注入：直接从 MediaServiceManager 构建 apiClient
    final manager = context.read<MediaServiceManager>();
    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      setState(() => _plan = null);
      return;
    }
    final api = EmbyApiClient(
      config: config,
      securityService: manager.securityService,
      sessionExpiredNotifier: manager.sessionExpiredNotifier,
    );
    final repo = EmbyPlaybackRepositoryImpl(
      apiClient: api,
      securityService: manager.securityService,
    );
    final usecase = GetPlaybackPlanUseCase(repo);
    final plan = await usecase(
      widget.mediaItem,
      maxStreamingBitrate: 10 * 1000 * 1000,
      requireAvc: true,
    );
    if (!mounted) return;
    setState(() {
      _plan = plan;
      // 先读取用户上次的选择；没有的话不主动指定（跟随服务器默认）。
      final saved = context.read<UserDataProvider>().trackSelectionForItem(
        widget.mediaItem,
      );
      _selectedAudioIndex = saved?.audioIndex;
      _selectedSubtitleIndex = saved?.subtitleIndex;
      _currentUrl = _buildUrlWithIndices(
        plan.url,
        _selectedAudioIndex,
        _selectedSubtitleIndex,
      );

      // 初始化本地字幕选择描述（用于混合模式下指示是否本地渲染）
    });

    if (_openSelectorPending && mounted) {
      _openSelectorPending = false;
      await _openTrackSelector();
    }
  }

  String _buildUrlWithIndices(String base, int? audio, int? subtitle) {
    final uri = Uri.parse(base);
    final qp = Map<String, String>.from(uri.queryParameters);

    // 音轨始终可直连附带
    if (audio != null && audio >= 0) {
      qp['AudioStreamIndex'] = audio.toString();
    } else {
      qp.remove('AudioStreamIndex');
    }
    // 移除所有字幕相关参数，保持直连
    qp['Static'] = 'true';
    qp.remove('SubtitleStreamIndex');
    qp.remove('MediaSourceId');

    final url = uri.replace(queryParameters: qp).toString();
    assert(() {
      debugPrint('[MeowHub][URL][PlayerView] $url');
      return true;
    }());
    return url;
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
                      setState(() {
                        _selectedAudioIndex = tempAudio;
                        _selectedSubtitleIndex = tempSub;
                        // 保存用户选择，供后续进入同一媒体时复用
                        context
                            .read<UserDataProvider>()
                            .setTrackSelectionForItem(
                              widget.mediaItem,
                              audioIndex: _selectedAudioIndex,
                              subtitleIndex: _selectedSubtitleIndex,
                            );
                        final base = plan.url;
                        _currentUrl = _buildUrlWithIndices(
                          base,
                          _selectedAudioIndex,
                          _selectedSubtitleIndex,
                        );
                      });
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
