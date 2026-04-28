import 'package:flutter/material.dart';
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

class PlayerViewRoutePayload {
  const PlayerViewRoutePayload({
    required this.mediaItem,
    this.initialPlaybackPlan,
  });

  final MediaItem mediaItem;
  final PlaybackPlan? initialPlaybackPlan;
}

class PlayerView extends StatefulWidget {
  const PlayerView({
    super.key,
    required this.mediaItem,
    this.initialPlaybackPlan,
    this.openTrackSelectorOnStart = false,
  });

  static const String routePath = '/player/:id';

  static String locationFor(int id) => '/player/$id';

  final MediaItem mediaItem;
  final PlaybackPlan? initialPlaybackPlan;
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
    return _resolveSubtitleStream(
      plan: _plan,
      subtitleIndex: _selectedSubtitleIndex,
      subtitleUri: _selectedSubtitleUri,
      subtitleTitle: _selectedSubtitleTitle,
      subtitleLanguage: _selectedSubtitleLanguage,
    );
  }

  bool get _shouldDisablePlayerSubtitleTrack {
    final subtitleIndex = _selectedSubtitleIndex;
    if (subtitleIndex != null && subtitleIndex < 0) {
      return true;
    }
    if ((_selectedSubtitleUri ?? '').trim().isNotEmpty) {
      return false;
    }
    return false;
  }

  String? get _selectedExternalSubtitleUri {
    final stream = _selectedSubtitleStream;
    if (stream != null && !_shouldUseExternalSubtitleUri(stream)) {
      return null;
    }
    final savedUri = _selectedSubtitleUri?.trim();
    if (savedUri != null && savedUri.isNotEmpty) {
      return savedUri;
    }
    if (stream == null) {
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

  bool _isImageSubtitle(PlaybackStream stream) {
    final codec = stream.codec?.toLowerCase();
    return codec != null &&
        const ['pgs', 'pgssub', 'sup', 'hdmv_pgs_subtitle'].contains(codec);
  }

  bool _isInternalImageSubtitle(PlaybackStream? stream) {
    if (stream == null) {
      return false;
    }
    return _isImageSubtitle(stream) &&
        !stream.isExternal &&
        !stream.isTextSubtitleStream;
  }

  bool _shouldUseExternalSubtitleUri(PlaybackStream stream) {
    final deliveryUrl = stream.deliveryUrl?.trim();
    if (deliveryUrl != null && deliveryUrl.isNotEmpty) {
      return true;
    }
    if (stream.isExternal &&
        (stream.supportsExternalStream || _isTextSubtitle(stream))) {
      return true;
    }
    return false;
  }

  PlaybackStream? _resolveSubtitleStream({
    required PlaybackPlan? plan,
    required int? subtitleIndex,
    required String? subtitleUri,
    required String? subtitleTitle,
    required String? subtitleLanguage,
  }) {
    if (plan == null) {
      return null;
    }
    if (subtitleIndex != null && subtitleIndex >= 0) {
      for (final stream in plan.subtitleStreams) {
        if (stream.index == subtitleIndex) {
          return stream;
        }
      }
    }
    final normalizedUri = subtitleUri?.trim();
    if (normalizedUri != null && normalizedUri.isNotEmpty) {
      for (final stream in plan.subtitleStreams) {
        if (stream.deliveryUrl?.trim() == normalizedUri) {
          return stream;
        }
      }
    }
    final normalizedTitle = subtitleTitle?.trim().toLowerCase();
    final normalizedLanguage = subtitleLanguage?.trim().toLowerCase();
    if ((normalizedTitle?.isNotEmpty ?? false) ||
        (normalizedLanguage?.isNotEmpty ?? false)) {
      for (final stream in plan.subtitleStreams) {
        final titleMatches =
            normalizedTitle != null &&
            normalizedTitle.isNotEmpty &&
            stream.title.trim().toLowerCase() == normalizedTitle;
        final languageMatches =
            normalizedLanguage != null &&
            normalizedLanguage.isNotEmpty &&
            (stream.language ?? '').trim().toLowerCase() == normalizedLanguage;
        if ((titleMatches && languageMatches) ||
            titleMatches ||
            languageMatches) {
          return stream;
        }
      }
    }
    return null;
  }

  PlaybackStream? _matchSubtitleStreamByMetadata(
    PlaybackPlan plan, {
    String? subtitleTitle,
    String? subtitleLanguage,
  }) {
    final normalizedTitle = subtitleTitle?.trim().toLowerCase() ?? '';
    final normalizedLanguage = subtitleLanguage?.trim().toLowerCase() ?? '';
    if (normalizedTitle.isEmpty && normalizedLanguage.isEmpty) {
      return null;
    }

    PlaybackStream? languageOnlyMatch;
    for (final stream in plan.subtitleStreams) {
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

  _ResolvedSubtitleSelection _resolveSubtitleSelection(
    PlaybackPlan plan, {
    required TrackSelection? savedSelection,
  }) {
    final savedIndex = savedSelection?.subtitleIndex;
    if (savedIndex != null && savedIndex < 0) {
      return const _ResolvedSubtitleSelection(stream: null, subtitleIndex: -1);
    }

    PlaybackStream? defaultStream;
    for (final stream in plan.subtitleStreams) {
      if (stream.isDefault) {
        defaultStream = stream;
        break;
      }
    }

    final matchedStream =
        _resolveSubtitleStream(
          plan: plan,
          subtitleIndex: savedIndex,
          subtitleUri: savedSelection?.subtitleUri,
          subtitleTitle: savedSelection?.subtitleTitle,
          subtitleLanguage: savedSelection?.subtitleLanguage,
        ) ??
        _matchSubtitleStreamByMetadata(
          plan,
          subtitleTitle: savedSelection?.subtitleTitle,
          subtitleLanguage: savedSelection?.subtitleLanguage,
        ) ??
        defaultStream;

    return _ResolvedSubtitleSelection(
      stream: matchedStream,
      subtitleIndex: matchedStream?.index,
    );
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

  // Auto 显示的是视频源的原始最高分辨率，而非转码后的实际输出尺寸。
  // 切换过低分辨率再切回 Auto 时，width/height 可能还带有上次转码的 MaxWidth/MaxHeight 残留，
  // 因此使用 sourceWidth/sourceHeight 保证始终显示源的最高可用分辨率。
  String? get _autoResolutionLabel {
    final videoInfo = _plan?.videoInfo;
    if (videoInfo == null) return null;
    final w = videoInfo.sourceWidth ?? videoInfo.width;
    final h = videoInfo.sourceHeight ?? videoInfo.height;
    final resolution = _formatVideoResolution(w, h);
    if (resolution == null || resolution.isEmpty) return null;
    return 'Auto · $resolution';
  }

  String? _formatVideoResolution(int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final shortEdge = width < height ? width : height;
    if (shortEdge >= 2160) {
      return '4K';
    }
    if (shortEdge >= 1440) {
      return '1440P';
    }
    if (shortEdge >= 1080) {
      return '1080P';
    }
    if (shortEdge >= 720) {
      return '720P';
    }
    if (shortEdge >= 480) {
      return '480P';
    }
    return '${width}x$height';
  }

  @override
  void initState() {
    super.initState();
    final userDataProvider = context.read<UserDataProvider>();
    final savedProgress = userDataProvider.playbackProgressForItem(
      widget.mediaItem,
    );
    _initialPosition = savedProgress?.position ?? Duration.zero;
    _openSelectorPending = widget.openTrackSelectorOnStart;
    final initialPlaybackPlan = widget.initialPlaybackPlan;
    if (initialPlaybackPlan != null) {
      try {
        _applyResolvedPlan(
          initialPlaybackPlan,
          userDataProvider: userDataProvider,
        );
        if (_needsTranscodingForSubtitles()) {
          _preparePlaybackPlan(preferTranscoding: true);
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          _maybeOpenPendingTrackSelector();
        });
      } catch (_) {
        _preparePlaybackPlan();
      }
      return;
    }
    _preparePlaybackPlan();
  }

  Future<void> _preparePlaybackPlan({bool? preferTranscoding}) async {
    final userDataProvider = context.read<UserDataProvider>();
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
      final needsTranscoding =
          preferTranscoding ?? _needsTranscodingForSubtitles();
      final plan = await _fetchPlaybackPlan(
        audioIndex: userDataProvider
            .trackSelectionForItem(widget.mediaItem)
            ?.audioIndex,
        subtitleIndex: needsTranscoding
            ? userDataProvider
                  .trackSelectionForItem(widget.mediaItem)
                  ?.subtitleIndex
            : null,
        preferTranscoding: needsTranscoding,
      );
      if (!mounted) return;
      setState(() {
        _applyResolvedPlan(plan, userDataProvider: userDataProvider);
      });
      await _maybeOpenPendingTrackSelector();
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

  void _applyResolvedPlan(
    PlaybackPlan plan, {
    required UserDataProvider userDataProvider,
  }) {
    final saved = userDataProvider.trackSelectionForItem(widget.mediaItem);
    final resolvedSubtitle = _resolveSubtitleSelection(
      plan,
      savedSelection: saved,
    );
    final initialSubtitleStream = resolvedSubtitle.stream;
    final initialSubtitleUri = initialSubtitleStream?.deliveryUrl;
    final resolvedSubtitleIndex = resolvedSubtitle.subtitleIndex;
    _assertStrictPlan(plan);
    _plan = plan;
    // 音轨选择：当前有效 > 已保存偏好 > 第一条音轨（兜底默认）
    final currentAudioValid = _selectedAudioIndex != null &&
        plan.audioStreams.any((s) => s.index == _selectedAudioIndex);
    _selectedAudioIndex = currentAudioValid
        ? _selectedAudioIndex
        : (saved?.audioIndex ?? plan.audioStreams.firstOrNull?.index);
    _selectedSubtitleIndex = resolvedSubtitleIndex;
    _selectedSubtitleUri = initialSubtitleUri;
    _selectedSubtitleTitle =
        initialSubtitleStream?.title ?? saved?.subtitleTitle;
    _selectedSubtitleLanguage =
        initialSubtitleStream?.language ?? saved?.subtitleLanguage;
    _currentUrl = plan.url;
    _isPreparingPlan = false;
    _planErrorMessage = null;

    if (saved?.subtitleIndex != resolvedSubtitleIndex ||
        saved?.subtitleUri != initialSubtitleUri ||
        saved?.subtitleTitle !=
            (initialSubtitleStream?.title ?? saved?.subtitleTitle) ||
        saved?.subtitleLanguage !=
            (initialSubtitleStream?.language ?? saved?.subtitleLanguage)) {
      userDataProvider.setTrackSelectionForItem(
        widget.mediaItem,
        audioIndex: saved?.audioIndex,
        subtitleIndex: resolvedSubtitleIndex,
        audioTitle: saved?.audioTitle,
        subtitleTitle: initialSubtitleStream?.title ?? saved?.subtitleTitle,
        subtitleLanguage:
            initialSubtitleStream?.language ?? saved?.subtitleLanguage,
        subtitleUri: initialSubtitleUri,
      );
    }
  }

  Future<void> _maybeOpenPendingTrackSelector() async {
    if (!_openSelectorPending || !mounted) {
      return;
    }
    _openSelectorPending = false;
    await _openTrackSelector();
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
    bool preferTranscoding = false,
  }) async {
    final repo = context.read<PlaybackRepository>();
    final usecase = GetPlaybackPlanUseCase(repo);
    return usecase(
      widget.mediaItem,
      maxStreamingBitrate:
          maxStreamingBitrate ?? _selectedResolution.maxStreamingBitrate,
      audioStreamIndex: audioIndex,
      subtitleStreamIndex: subtitleIndex,
      playSessionId: playSessionIdOverride ?? _plan?.playSessionId,
      preferTranscoding: preferTranscoding,
    );
  }

  bool _needsTranscodingForSubtitles() {
    // 内嵌图像字幕（PGS 等）需要服务端烧录，必须走转码
    final stream = _selectedSubtitleStream;
    if (!_isInternalImageSubtitle(stream)) {
      return false;
    }
    final videoInfo = _plan?.videoInfo;
    if (videoInfo == null) {
      return true;
    }
    final currentWidth = videoInfo.width;
    final currentHeight = videoInfo.height;
    final sourceWidth = videoInfo.sourceWidth;
    final sourceHeight = videoInfo.sourceHeight;
    if (currentWidth == null ||
        currentHeight == null ||
        sourceWidth == null ||
        sourceHeight == null) {
      return true;
    }
    return currentWidth == sourceWidth && currentHeight == sourceHeight;
  }

  Future<void> _openTrackSelector() async {
    final plan = _plan;
    if (plan == null) return;
    int? tempAudio =
        _selectedAudioIndex ??
        (plan.audioStreams.isNotEmpty ? plan.audioStreams.first.index : null);
    int? tempSub = _selectedSubtitleIndex;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: FractionallySizedBox(
                heightFactor: 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ListView(
                          children: [
                            Text(
                              '选择音轨',
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
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
                                onTap: () =>
                                    modalSetState(() => tempAudio = s.index),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '选择字幕',
                              style: Theme.of(ctx).textTheme.titleMedium,
                            ),
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
                                onTap: () =>
                                    modalSetState(() => tempSub = s.index),
                              ),
                            ),
                          ],
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
    final userDataProvider = context.read<UserDataProvider>();
    final effectiveAudioIndex =
        audioIndex ??
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
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedAudioIndex = effectiveAudioIndex;
      _selectedSubtitleIndex = subtitleIndex;
      _selectedSubtitleUri = selectedSubtitleStream?.deliveryUrl;
      _selectedSubtitleTitle = selectedSubtitleStream?.title;
      _selectedSubtitleLanguage = selectedSubtitleStream?.language;
    });
    if (_isInternalImageSubtitle(selectedSubtitleStream)) {
      final nextPlan = await _fetchPlaybackPlan(
        audioIndex: effectiveAudioIndex,
        subtitleIndex: subtitleIndex,
        preferTranscoding: true,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _applyResolvedPlan(nextPlan, userDataProvider: userDataProvider);
      });
    }
  }

  Future<void> _applyResolutionSelection(PlayerResolutionOption option) async {
    final userDataProvider = context.read<UserDataProvider>();
    _resumePositionOverride =
        _latestStatus?.position ?? _resumePositionOverride;
    final needsTranscoding =
        _isInternalImageSubtitle(_selectedSubtitleStream);
    final nextPlan = await _fetchPlaybackPlan(
      audioIndex: _selectedAudioIndex,
      subtitleIndex: needsTranscoding ? _selectedSubtitleIndex : null,
      maxStreamingBitrate: option.maxStreamingBitrate,
      preferTranscoding: needsTranscoding,
    );
    _assertStrictPlan(nextPlan);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedResolution = option;
      _applyResolvedPlan(nextPlan, userDataProvider: userDataProvider);
    });
  }

  Future<void> _handleRetryWithTranscoding() async {
    // 转码重试：以当前分辨率/音轨/字幕重新获取播放计划，开放所有传输方式
    final userDataProvider = context.read<UserDataProvider>();
    _resumePositionOverride =
        _latestStatus?.position ?? _resumePositionOverride;
    try {
      final nextPlan = await _fetchPlaybackPlan(
        audioIndex: _selectedAudioIndex,
        subtitleIndex: _selectedSubtitleIndex,
        preferTranscoding: false,
      );
      _assertStrictPlan(nextPlan);
      if (!mounted) return;
      setState(() {
        _applyResolvedPlan(nextPlan, userDataProvider: userDataProvider);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _planErrorMessage = e.toString();
      });
    }
  }

  Future<void> _handleServerSeek(Duration target) async {
    _resumePositionOverride = target;
    if (!mounted) {
      return;
    }
    setState(() {});
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
          autoResolutionLabel: _autoResolutionLabel,
          onResolutionSelected: _applyResolutionSelection,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle:
              _selectedSubtitleTitle ?? _selectedSubtitleStream?.title,
          subtitleLanguage:
              _selectedSubtitleLanguage ?? _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
          subtitleStreamIndex: _selectedSubtitleIndex,
          subtitleStreams: _plan!.subtitleStreams,
          playSessionId: _plan!.playSessionId,
          mediaSourceId: _plan!.mediaSourceId,
          audioStreamIndex: _selectedAudioIndex,
          audioStreams: _plan!.audioStreams,
          onRetryWithTranscoding: _handleRetryWithTranscoding,
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
          onRetryWithTranscoding: _handleRetryWithTranscoding,
          subtitleUri: _selectedExternalSubtitleUri,
          subtitleTitle:
              _selectedSubtitleTitle ?? _selectedSubtitleStream?.title,
          subtitleLanguage:
              _selectedSubtitleLanguage ?? _selectedSubtitleStream?.language,
          disableSubtitleTrack: _shouldDisablePlayerSubtitleTrack,
          subtitleStreamIndex: _selectedSubtitleIndex,
          subtitleStreams: _plan!.subtitleStreams,
          playSessionId: _plan!.playSessionId,
          mediaSourceId: _plan!.mediaSourceId,
          audioStreamIndex: _selectedAudioIndex,
          audioStreams: _plan!.audioStreams,
        );
      },
    );
  }
}

class _ResolvedSubtitleSelection {
  const _ResolvedSubtitleSelection({
    required this.stream,
    required this.subtitleIndex,
  });

  final PlaybackStream? stream;
  final int? subtitleIndex;
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
