import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/season_info.dart';
import '../../../domain/entities/playback_plan.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/media_detail_provider.dart';
import '../../../providers/media_with_user_data_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/cast_list_section.dart';
import '../../atoms/expandable_overview_section.dart';
import '../../atoms/info_chip.dart';
import '../../atoms/info_row.dart';

class TabletMediaDetailScreen extends StatefulWidget {
  const TabletMediaDetailScreen({
    super.key,
    required this.maxWidth,
    required this.mediaItem,
    required this.selectedServer,
    required this.isFavorite,
    required this.initialEpisodeIndex,
    required this.playableItems,
    required this.onPlayPressed,
    required this.onOpenTrackSelector,
    required this.onToggleFavorite,
  });

  final double maxWidth;
  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final bool isFavorite;
  final int initialEpisodeIndex;
  final List<MediaItem> playableItems;
  final ValueChanged<int>? onPlayPressed;
  final ValueChanged<int> onOpenTrackSelector;
  final VoidCallback onToggleFavorite;

  @override
  State<TabletMediaDetailScreen> createState() =>
      _TabletMediaDetailScreenState();
}

class _TabletMediaDetailScreenState extends State<TabletMediaDetailScreen> {
  late int _selectedEpisode;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;

  @override
  void initState() {
    super.initState();
    _selectedEpisode = widget.initialEpisodeIndex;
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
  void didUpdateWidget(covariant TabletMediaDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final episodeChanged =
        oldWidget.initialEpisodeIndex != widget.initialEpisodeIndex;

    if (episodeChanged) {
      _selectedEpisode = widget.initialEpisodeIndex;
    }

    final playableItemsChanged = !_hasSamePlayableEntries(
      oldWidget.playableItems,
      widget.playableItems,
    );
    if (playableItemsChanged || episodeChanged) {
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
        initialSelectedIndex: _selectedEpisode,
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
  Widget build(BuildContext context) {
    final detailProvider = context.watch<MediaDetailProvider>();
    final mediaWithUserDataProvider = context
        .watch<MediaWithUserDataProvider>();
    final userDataProvider = context.watch<UserDataProvider>();
    final mediaItem = _resolveLiveMediaItem(
      mediaWithUserDataProvider: mediaWithUserDataProvider,
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
    final clampedEpisode = detailProvider.selectedIndex.clamp(
      0,
      episodes.length - 1,
    );
    if (clampedEpisode != _selectedEpisode) {
      _selectedEpisode = clampedEpisode;
    }

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 280,
            backgroundColor: AppTheme.backgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(mediaItem.title),
              centerTitle: true,
              background: _TabletHeader(mediaItem: mediaItem),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      mediaItem.title,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    _TabletMetaRow(mediaItem: mediaItem),
                    const SizedBox(height: 14),
                    _TabletPlaybackConfigSection(
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
                                  episodes[clampedEpisode];
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
                                    : () => _handlePlayPressed(clampedEpisode),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54),
                                ),
                                child: Text(hasResume ? '继续播放' : '立即播放'),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        _TabletIconButton(
                          icon: mediaItem.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          onTap: widget.onToggleFavorite,
                          active: mediaItem.isFavorite,
                        ),
                        const SizedBox(width: 10),
                        _TabletIconButton(
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
                                Expanded(
                                  child: Text(
                                    '选集列表',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: episodes.isEmpty
                                      ? null
                                      : () => _showAllEpisodes(
                                          context,
                                          episodes: episodes,
                                          selectedIndex: clampedEpisode,
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
                            height: 52,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: episodes.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                final isSelected = index == clampedEpisode;
                                return InkWell(
                                  onTap: () {
                                    _inheritTrackSelectionIfNeeded(
                                      fromItem: _currentPlayableItem,
                                      toItem: episodes[index],
                                    );
                                    _selectedEpisode = index;
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
                        collapsedMaxLines: 5,
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
                    _TabletInfoSection(
                      mediaItem: mediaItem,
                      selectedServer: widget.selectedServer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  MediaItem _resolveLiveMediaItem({
    required MediaWithUserDataProvider mediaWithUserDataProvider,
    required UserDataProvider userDataProvider,
  }) {
    MediaItem? liveMediaItem;
    for (final item in mediaWithUserDataProvider.allItems) {
      if (item.mediaKey == widget.mediaItem.mediaKey) {
        liveMediaItem = item;
        break;
      }
    }

    return widget.mediaItem.copyWith(
      isFavorite: liveMediaItem?.isFavorite ?? widget.isFavorite,
      playbackProgress:
          userDataProvider.playbackProgressForItem(widget.mediaItem) ??
          liveMediaItem?.playbackProgress ??
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
            heightFactor: 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                  child: Row(
                    children: [
                      Text(
                        '全部剧集',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      Text(
                        '${episodes.length} 集',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            _inheritTrackSelectionIfNeeded(
                              fromItem: _currentPlayableItem,
                              toItem: episode,
                            );
                            _selectedEpisode = index;
                            detailProvider.selectEpisode(index);
                            _syncSelectedTrackSelectionsForCurrentItem(
                              notify: false,
                            );
                            Navigator.of(context).pop();
                          },
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.18)
                                  : AppTheme.cardColor,
                              borderRadius: BorderRadius.circular(18),
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
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      if (hasProgress) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          '已看到 ${_formatProgressText(progress)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Colors.blue.shade200,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
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

  Future<void> _handlePlayPressed(int episodeIndex) async {
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
    widget.onPlayPressed?.call(episodeIndex);
  }
}

class _TabletPlaybackConfigSection extends StatelessWidget {
  const _TabletPlaybackConfigSection({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          _TabletPlaybackConfigTile(
            icon: Icons.graphic_eq_rounded,
            title: '音频',
            value: audioLabel,
            loading: loading,
            onTap: onAudioTap,
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          _TabletPlaybackConfigTile(
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

class _TabletPlaybackConfigTile extends StatelessWidget {
  const _TabletPlaybackConfigTile({
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
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    );
    final valueStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      fontWeight: FontWeight.w600,
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: titleStyle)),
              const SizedBox(width: 16),
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

class _TabletHeader extends StatelessWidget {
  const _TabletHeader({required this.mediaItem});

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
                colors: [Color(0xFF252525), Color(0xFF101010)],
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
                Colors.black.withValues(alpha: 0.18),
                AppTheme.backgroundColor,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletMetaRow extends StatelessWidget {
  const _TabletMetaRow({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
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
    );
  }
}

class _TabletIconButton extends StatelessWidget {
  const _TabletIconButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          color: active ? AppTheme.accentColor : Colors.white70,
        ),
      ),
    );
  }
}

class _TabletInfoSection extends StatelessWidget {
  const _TabletInfoSection({
    required this.mediaItem,
    required this.selectedServer,
  });

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
