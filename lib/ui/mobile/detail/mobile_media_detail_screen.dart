import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/playback_plan.dart';
import '../../../domain/entities/season_info.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/cast_list_section.dart';
import '../../atoms/expandable_overview_section.dart';
import '../../atoms/info_chip.dart';
import '../../atoms/info_row.dart';
import '../../../providers/media_detail_provider.dart';
import '../../../providers/media_with_user_data_provider.dart';
import '../../../providers/user_data_provider.dart';

class MobileMediaDetailScreen extends StatefulWidget {
  const MobileMediaDetailScreen({
    super.key,
    required this.mediaItem,
    required this.selectedServer,
    required this.isFavorite,
    required this.playableItems,
    required this.onPlayPressed,
    required this.onOpenTrackSelector,
    required this.onToggleFavorite,
  });

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final bool isFavorite;
  final List<MediaItem> playableItems;
  final ValueChanged<int>? onPlayPressed;
  final ValueChanged<int> onOpenTrackSelector;
  final VoidCallback onToggleFavorite;

  @override
  State<MobileMediaDetailScreen> createState() =>
      _MobileMediaDetailScreenState();
}

class _MobileMediaDetailScreenState extends State<MobileMediaDetailScreen> {
  static const double _episodeListHorizontalPadding = 18;
  static const double _episodeChipHorizontalPadding = 18;
  static const double _episodeChipGap = 10;

  final Map<int, GlobalKey> _episodeItemKeys = {};
  final GlobalKey _episodeListViewportKey = GlobalKey();
  final ScrollController _episodeScrollController = ScrollController();
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;
  String? _lastCenteredEpisodeSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _loadDetailContent();
      if (!mounted) {
        return;
      }
      _syncSelectedTrackSelectionsForCurrentItem(notify: false);
    });
  }

  @override
  void didUpdateWidget(covariant MobileMediaDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final playableItemsChanged = !_hasSamePlayableEntries(
      oldWidget.playableItems,
      widget.playableItems,
    );
    if (playableItemsChanged) {
      _episodeItemKeys.clear();
      _lastCenteredEpisodeSignature = null;
    }

    if (oldWidget.mediaItem.mediaKey != widget.mediaItem.mediaKey ||
        playableItemsChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        await _loadDetailContent();
        if (!mounted) {
          return;
        }
        _syncSelectedTrackSelectionsForCurrentItem(notify: false);
      });
    }
  }

  Future<void> _loadDetailContent() async {
    final provider = context.read<MediaDetailProvider>();
    final isEpisode = widget.mediaItem.parentTitle != null ||
        (widget.mediaItem.seriesId != null &&
            widget.mediaItem.seriesId!.isNotEmpty);
    if (widget.mediaItem.type == MediaType.series && !isEpisode) {
      await provider.loadSeasons(widget.mediaItem);
    } else {
      await provider.loadEpisodes(
        widget.mediaItem.copyWith(playableItems: widget.playableItems),
      );
    }
  }

  bool _hasSamePlayableEntries(List<MediaItem> left, List<MediaItem> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].mediaKey != right[index].mediaKey) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailProvider = context.watch<MediaDetailProvider>();
    context.watch<MediaWithUserDataProvider>();
    final userDataProvider = context.watch<UserDataProvider>();
    final mediaItem = _resolveLiveMediaItem(
      userDataProvider: userDataProvider,
    );
    final isLoading =
        detailProvider.isLoading ||
        detailProvider.loadedSeriesKey != widget.mediaItem.mediaKey;
    final episodes = _buildLiveEpisodes(
      detailProvider.episodes,
      userDataProvider,
    );
    final cast = mediaItem.cast;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final selectedEpisode = detailProvider.selectedIndex.clamp(
      0,
      episodes.length - 1,
    );
    _scheduleCenterSelectedEpisode(
      seriesKey: detailProvider.loadedSeriesKey ?? widget.mediaItem.mediaKey,
      selectedIndex: selectedEpisode,
      episodes: episodes,
      screenWidth: MediaQuery.sizeOf(context).width,
      episodesLength: episodes.length,
    );

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 248,
            backgroundColor: AppTheme.backgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Text(mediaItem.title),
              background: _PosterHeader(mediaItem: mediaItem),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),
                    _MetaChipRow(mediaItem: mediaItem),
                    const SizedBox(height: 14),
                    _PlaybackConfigSection(
                      audioLabel: _audioButtonLabel,
                      subtitleLabel: _subtitleButtonLabel,
                      loading: detailProvider.isLoadingPlaybackConfig,
                      onAudioTap: _openAudioSelector,
                      onSubtitleTap: _openSubtitleSelector,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final currentPlayableItem =
                                  episodes[selectedEpisode];
                              final hasResume =
                                  currentPlayableItem.playbackProgress !=
                                      null &&
                                  currentPlayableItem
                                          .playbackProgress!
                                          .position >
                                      Duration.zero;
                              return FilledButton(
                                onPressed: widget.onPlayPressed == null
                                    ? null
                                    : () => _handlePlayPressed(selectedEpisode),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                ),
                                child: Text(hasResume ? '继续播放' : '立即播放'),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ActionIconButton(
                          icon: mediaItem.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          onTap: widget.onToggleFavorite,
                          active: mediaItem.isFavorite,
                        ),
                        const SizedBox(width: 10),
                        _ActionIconButton(
                          icon: Icons.download_rounded,
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (detailProvider.seasons.length > 1)
                      _SeasonPicker(
                        seasons: detailProvider.seasons,
                        selectedIndex: detailProvider.selectedSeasonIndex,
                        onSeasonSelected: (index) {
                          detailProvider.selectSeason(index);
                        },
                      ),
                    AppSurfaceCard(
                      padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '选集列表',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.titleColor,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: episodes.isEmpty
                                      ? null
                                      : () => _showAllEpisodes(
                                          context,
                                          episodes: episodes,
                                          selectedIndex: selectedEpisode,
                                          detailProvider: detailProvider,
                                        ),
                                  icon: const Icon(Icons.grid_view_rounded),
                                  label: const Text('查看全部'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            key: _episodeListViewportKey,
                            height: 50,
                            child: ListView.separated(
                              controller: _episodeScrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: episodes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final isSelected = index == selectedEpisode;
                                return InkWell(
                                  key: _episodeItemKeyFor(index),
                                  onTap: () {
                                    _inheritTrackSelectionIfNeeded(
                                      fromItem: _currentPlayableItem,
                                      toItem: episodes[index],
                                    );
                                    detailProvider.selectEpisode(index);
                                    _syncSelectedTrackSelectionsForCurrentItem(
                                      notify: false,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.blue
                                          : AppTheme.backgroundColor,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      episodes[index].playbackLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    AppSurfaceCard(
                      child: ExpandableOverviewSection(
                        overview: mediaItem.overview,
                        collapsedMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AppSurfaceCard(
                      child: CastListSection(
                        cast: cast,
                        onViewAll: () => _showAllCast(context, cast),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _InfoSection(
                      mediaItem: mediaItem,
                      selectedServer: widget.selectedServer,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  GlobalKey _episodeItemKeyFor(int index) {
    return _episodeItemKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _scheduleCenterSelectedEpisode({
    required String seriesKey,
    required int selectedIndex,
    required List<MediaItem> episodes,
    required double screenWidth,
    required int episodesLength,
  }) {
    if (episodesLength <= 0) {
      return;
    }

    final signature =
        '$seriesKey|$selectedIndex|$episodesLength|${screenWidth.round()}';
    if (_lastCenteredEpisodeSignature == signature) {
      return;
    }
    _lastCenteredEpisodeSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _centerEpisodeChip(index: selectedIndex, episodes: episodes);
    });
  }

  Future<void> _centerEpisodeChip({
    required int index,
    required List<MediaItem> episodes,
  }) async {
    final viewportContext = _episodeListViewportKey.currentContext;
    if (viewportContext == null || !_episodeScrollController.hasClients) {
      return;
    }

    final viewportBox = viewportContext.findRenderObject() as RenderBox?;
    if (viewportBox == null) {
      return;
    }

    final targetCenterX = _estimatedEpisodeCenterX(
      context: viewportContext,
      episodes: episodes,
      index: index,
    );
    final viewportCenterX = viewportBox.size.width / 2;
    final desiredOffset = targetCenterX - viewportCenterX;
    final position = _episodeScrollController.position;
    final clampedOffset = desiredOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if ((_episodeScrollController.offset - clampedOffset).abs() < 1) {
      return;
    }

    await _episodeScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  double _estimatedEpisodeCenterX({
    required BuildContext context,
    required List<MediaItem> episodes,
    required int index,
  }) {
    var offset = _episodeListHorizontalPadding;
    for (var itemIndex = 0; itemIndex < index; itemIndex++) {
      offset += _estimatedEpisodeChipWidth(
        context,
        episodes[itemIndex].playbackLabel,
      );
      offset += _episodeChipGap;
    }

    final currentWidth = _estimatedEpisodeChipWidth(
      context,
      episodes[index].playbackLabel,
    );
    return offset + currentWidth / 2;
  }

  double _estimatedEpisodeChipWidth(BuildContext context, String label) {
    final style =
        Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white) ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
    final textPainter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();

    return textPainter.width + (_episodeChipHorizontalPadding * 2);
  }

  MediaItem _resolveLiveMediaItem({
    required UserDataProvider userDataProvider,
  }) {
    return widget.mediaItem.copyWith(
      isFavorite: userDataProvider.isFavorite(widget.mediaItem.id) ||
          widget.isFavorite,
      playbackProgress:
          userDataProvider.playbackProgressForItem(widget.mediaItem) ??
          widget.mediaItem.playbackProgress,
    );
  }

  List<MediaItem> _buildLiveEpisodes(
    List<MediaItem> episodes,
    UserDataProvider userDataProvider,
  ) {
    return episodes
        .map(
          (episode) => episode.copyWith(
            playbackProgress:
                userDataProvider.playbackProgressForItem(episode) ??
                episode.playbackProgress,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _showAllEpisodes(
    BuildContext context, {
    required List<MediaItem> episodes,
    required int selectedIndex,
    required MediaDetailProvider detailProvider,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Text(
                        '全部剧集',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      Text(
                        '${episodes.length} 集',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: episodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isSelected = index == selectedIndex;
                      final progress = episode.playbackProgress;
                      final hasProgress =
                          progress != null && progress.position > Duration.zero;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            _inheritTrackSelectionIfNeeded(
                              fromItem: _currentPlayableItem,
                              toItem: episode,
                            );
                            detailProvider.selectEpisode(index);
                            _syncSelectedTrackSelectionsForCurrentItem(
                              notify: false,
                            );
                            Navigator.of(context).pop();
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.18)
                                  : AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue.withValues(alpha: 0.7)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        episode.playbackLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        episode.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      if (hasProgress) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '已看到 ${_formatProgressText(progress)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.blue.shade200,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.chevron_right_rounded,
                                  color: isSelected
                                      ? Colors.blue.shade300
                                      : Colors.white54,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatProgressText(MediaPlaybackProgress progress) {
    final totalSeconds = progress.duration.inSeconds;
    if (totalSeconds <= 0) {
      return '${progress.position.inMinutes} 分钟';
    }
    final percent =
        ((progress.position.inMilliseconds / progress.duration.inMilliseconds) *
                100)
            .clamp(0, 100)
            .round();
    return '$percent%';
  }

  void _showAllCast(BuildContext context, List<Cast> cast) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final member = cast[index];
              return AppSurfaceCard(
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: member.avatarUrl.isEmpty
                            ? const ColoredBox(
                                color: AppTheme.backgroundColor,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: Colors.white38,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: member.avatarUrl,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            member.characterName,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  MediaItem get _currentPlayableItem {
    final detailProvider = context.read<MediaDetailProvider>();
    final episodes = _buildLiveEpisodes(
      detailProvider.episodes,
      context.read<UserDataProvider>(),
    );
    final selectedIndex = detailProvider.selectedIndex.clamp(
      0,
      episodes.length - 1,
    );
    return episodes[selectedIndex];
  }

  String get _audioButtonLabel {
    final detailProvider = context.read<MediaDetailProvider>();
    if (detailProvider.isLoadingPlaybackConfig) {
      return '加载中';
    }
    final selectedIndex = _selectedAudioIndex;
    final matched = selectedIndex == null
        ? _firstAudioStream(detailProvider.selectedAudioStreams)
        : detailProvider.selectedAudioStreamByIndex(selectedIndex);
    final title = matched != null
        ? matched.title
        : context
              .read<UserDataProvider>()
              .trackSelectionForItem(_currentPlayableItem)
              ?.audioTitle;
    return title ?? '默认音轨';
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

  PlaybackStream? _firstAudioStream(List<PlaybackStream> streams) {
    if (streams.isEmpty) {
      return null;
    }
    return streams.first;
  }

  String get _subtitleButtonLabel {
    final detailProvider = context.read<MediaDetailProvider>();
    if (detailProvider.isLoadingPlaybackConfig) {
      return '加载中';
    }
    final selectedIndex = _selectedSubtitleIndex ?? -1;
    if (selectedIndex < 0) {
      return '无字幕';
    }
    final matched = detailProvider.selectedSubtitleStreamByIndex(selectedIndex);
    final title = matched != null
        ? matched.title
        : context
              .read<UserDataProvider>()
              .trackSelectionForItem(_currentPlayableItem)
              ?.subtitleTitle;
    return title ?? '字幕';
  }

  void _inheritTrackSelectionIfNeeded({
    required MediaItem fromItem,
    required MediaItem toItem,
  }) {
    if (fromItem.mediaKey == toItem.mediaKey) {
      return;
    }
    final udp = context.read<UserDataProvider>();
    if (udp.trackSelectionForItem(toItem) != null) {
      return;
    }
    final current = udp.trackSelectionForItem(fromItem);
    if (current == null) {
      return;
    }
    udp.setTrackSelectionForItem(
      toItem,
      audioIndex: current.audioIndex,
      subtitleIndex: current.subtitleIndex,
    );
  }

  void _syncSelectedTrackSelectionsForCurrentItem({bool notify = true}) {
    final saved = context.read<UserDataProvider>().trackSelectionForItem(
      _currentPlayableItem,
    );
    final nextAudioValue = saved?.audioIndex;
    final nextSubtitleValue = saved?.subtitleIndex ?? -1;
    if (!notify || !mounted) {
      _selectedAudioIndex = nextAudioValue;
      _selectedSubtitleIndex = nextSubtitleValue;
      return;
    }
    setState(() {
      _selectedAudioIndex = nextAudioValue;
      _selectedSubtitleIndex = nextSubtitleValue;
    });
  }

  Future<void> _ensureTrackOptionsLoaded() async {
    final item = _currentPlayableItem;
    final detailProvider = context.read<MediaDetailProvider>();
    final udp = context.read<UserDataProvider>();
    final saved = udp.trackSelectionForItem(item);
    await detailProvider.ensurePlaybackInfoForSelectedEpisode();
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedAudioIndex = saved?.audioIndex;
      _selectedSubtitleIndex = saved?.subtitleIndex ?? -1;
    });
  }

  Future<List<PlaybackStream>> _ensureAudioOptions() async {
    final item = _currentPlayableItem;
    await _ensureTrackOptionsLoaded();
    if (!mounted) {
      return const [];
    }
    final detailProvider = context.read<MediaDetailProvider>();
    if (detailProvider.selectedPlaybackItemKey != item.mediaKey) {
      return const [];
    }
    return detailProvider.selectedAudioStreams;
  }

  Future<List<PlaybackStream>> _ensureSubtitleOptions() async {
    final item = _currentPlayableItem;
    await _ensureTrackOptionsLoaded();
    if (!mounted) {
      return const [];
    }
    final detailProvider = context.read<MediaDetailProvider>();
    if (detailProvider.selectedPlaybackItemKey != item.mediaKey) {
      return const [];
    }
    return detailProvider.selectedSubtitleStreams;
  }

  Future<void> _openAudioSelector() async {
    final item = _currentPlayableItem;
    final options = await _ensureAudioOptions();
    if (!mounted || options.isEmpty) {
      return;
    }
    final initialValue = _selectedAudioIndex ?? options.first.index;
    final selected = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择音轨', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...options.map(
                  (stream) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    minLeadingWidth: 24,
                    horizontalTitleGap: 12,
                    leading: Icon(
                      initialValue == stream.index
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(stream.title),
                    subtitle: _audioStreamDetail(stream) == null
                        ? null
                        : Text(_audioStreamDetail(stream)!),
                    onTap: () => Navigator.of(context).pop(stream.index),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    PlaybackStream? selectedStream;
    for (final stream in options) {
      if (stream.index == selected) {
        selectedStream = stream;
        break;
      }
    }
    final udp = context.read<UserDataProvider>();
    final previous = udp.trackSelectionForItem(item);
    udp.setTrackSelectionForItem(
      item,
      audioIndex: selected,
      subtitleIndex: previous?.subtitleIndex,
      audioTitle: selectedStream?.title,
      subtitleTitle: previous?.subtitleTitle,
      subtitleLanguage: previous?.subtitleLanguage,
      subtitleUri: previous?.subtitleUri,
    );
    setState(() {
      _selectedAudioIndex = selected;
    });
  }

  Future<void> _openSubtitleSelector() async {
    final item = _currentPlayableItem;
    final options = await _ensureSubtitleOptions();
    if (!mounted) {
      return;
    }
    final initialValue = _selectedSubtitleIndex ?? -1;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.72,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('选择字幕', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          minLeadingWidth: 24,
                          horizontalTitleGap: 12,
                          leading: Icon(
                            initialValue == -1
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          title: const Text('无字幕'),
                          onTap: () => Navigator.of(context).pop(-1),
                        ),
                        ...options.map(
                          (stream) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            minLeadingWidth: 24,
                            horizontalTitleGap: 12,
                            leading: Icon(
                              initialValue == stream.index
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(stream.title),
                            subtitle: _subtitleStreamDetail(stream) == null
                                ? null
                                : Text(_subtitleStreamDetail(stream)!),
                            onTap: () =>
                                Navigator.of(context).pop(stream.index),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    PlaybackStream? selectedStream;
    if (selected >= 0) {
      for (final stream in options) {
        if (stream.index == selected) {
          selectedStream = stream;
          break;
        }
      }
    }
    final udp = context.read<UserDataProvider>();
    final previous = udp.trackSelectionForItem(item);
    udp.setTrackSelectionForItem(
      item,
      subtitleIndex: selected,
      audioIndex: previous?.audioIndex,
      audioTitle: previous?.audioTitle,
      subtitleTitle: selectedStream?.title,
      subtitleLanguage: selectedStream?.language,
      subtitleUri: selectedStream?.deliveryUrl,
    );
    setState(() {
      _selectedSubtitleIndex = selected;
    });
  }

  Future<void> _handlePlayPressed(int selectedEpisode) async {
    final item = _currentPlayableItem;
    final detailProvider = context.read<MediaDetailProvider>();
    final udp = context.read<UserDataProvider>();
    final saved = udp.trackSelectionForItem(item);
    if ((saved?.subtitleIndex ?? -1) >= 0 &&
        (saved?.subtitleUri?.isEmpty ?? true)) {
      await detailProvider.ensurePlaybackInfoForSelectedEpisode();
      if (!mounted) {
        return;
      }
      final stream = detailProvider.selectedSubtitleStreamByIndex(
        saved?.subtitleIndex,
      );
      udp.setTrackSelectionForItem(
        item,
        audioIndex: saved?.audioIndex,
        subtitleIndex: saved?.subtitleIndex,
        audioTitle: saved?.audioTitle,
        subtitleTitle: stream?.title ?? saved?.subtitleTitle,
        subtitleLanguage: stream?.language ?? saved?.subtitleLanguage,
        subtitleUri: stream?.deliveryUrl,
      );
    }
    widget.onPlayPressed?.call(selectedEpisode);
  }
}

class _PlaybackConfigSection extends StatelessWidget {
  const _PlaybackConfigSection({
    required this.audioLabel,
    required this.subtitleLabel,
    required this.loading,
    required this.onAudioTap,
    required this.onSubtitleTap,
  });

  final String audioLabel;
  final String subtitleLabel;
  final bool loading;
  final VoidCallback onAudioTap;
  final VoidCallback onSubtitleTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        children: [
          _PlaybackConfigTile(
            icon: Icons.graphic_eq_rounded,
            title: '音频',
            value: audioLabel,
            loading: loading,
            onTap: onAudioTap,
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          _PlaybackConfigTile(
            icon: Icons.closed_caption_outlined,
            title: '字幕',
            value: subtitleLabel,
            loading: loading,
            onTap: onSubtitleTap,
          ),
        ],
      ),
    );
  }
}

class _PlaybackConfigTile extends StatelessWidget {
  const _PlaybackConfigTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.loading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      fontWeight: FontWeight.w600,
    );
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: titleStyle)),
              const SizedBox(width: 12),
              Flexible(
                child: loading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: valueStyle,
                      ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.36),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterHeader extends StatelessWidget {
  const _PosterHeader({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final imageUrl = mediaItem.backdropUrl ?? mediaItem.posterUrl;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null && imageUrl.isNotEmpty)
          CachedNetworkImage(imageUrl: imageUrl, fit: BoxFit.cover)
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2A2A), Color(0xFF111111)],
              ),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.16),
                AppTheme.backgroundColor,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaChipRow extends StatelessWidget {
  const _MetaChipRow({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoChip(
                icon: Icons.star_rounded,
                label: mediaItem.rating > 0
                    ? mediaItem.rating.toStringAsFixed(1)
                    : '--',
                color: AppTheme.accentColor,
              ),
              if (mediaItem.year != null)
                InfoChip(
                  icon: Icons.calendar_today_rounded,
                  label: mediaItem.year.toString(),
                ),
              InfoChip(
                icon: mediaItem.type == MediaType.movie
                    ? Icons.movie_creation_outlined
                    : Icons.live_tv_rounded,
                label: mediaItem.type == MediaType.movie ? '电影' : '剧集',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            icon,
            color: active ? AppTheme.accentColor : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.mediaItem, required this.selectedServer});

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('作品信息', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          InfoRow(label: '标题', value: mediaItem.title),
          InfoRow(label: '原始标题', value: mediaItem.originalTitle),
          InfoRow(
            label: '类型',
            value: mediaItem.type == MediaType.movie ? '电影' : '剧集',
          ),
          InfoRow(label: '年份', value: mediaItem.year?.toString() ?? '未知'),
          InfoRow(label: '线路', value: selectedServer.name),
          InfoRow(
            label: '播放地址',
            value: mediaItem.playUrl ?? '暂未提供',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _SeasonPicker extends StatelessWidget {
  const _SeasonPicker({
    required this.seasons,
    required this.selectedIndex,
    required this.onSeasonSelected,
  });

  final List<SeasonInfo> seasons;
  final int selectedIndex;
  final ValueChanged<int> onSeasonSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 42,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: seasons.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final season = seasons[index];
            final isSelected = index == selectedIndex;
            return ChoiceChip(
              label: Text(
                season.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.black : Colors.white70,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => onSeasonSelected(index),
              selectedColor: AppTheme.accentColor,
              backgroundColor: AppTheme.cardColor,
              side: BorderSide(
                color: isSelected
                    ? AppTheme.accentColor
                    : Colors.white.withValues(alpha: 0.12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
  }
}
