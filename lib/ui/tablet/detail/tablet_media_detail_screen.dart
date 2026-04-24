import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../domain/entities/media_service_config.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/cast_list_section.dart';
import '../../atoms/expandable_overview_section.dart';
import '../../atoms/info_chip.dart';
import '../../atoms/info_row.dart';
import '../../../domain/entities/playback_plan.dart';
import '../../../domain/repositories/i_media_service_manager.dart';
import '../../../domain/repositories/playback_repository.dart';
import '../../../domain/usecases/get_playback_plan.dart';
import '../../../providers/media_with_user_data_provider.dart';
import '../../../providers/user_data_provider.dart';

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
  static const int _playbackPlanBitrate = 10 * 1000 * 1000;

  late int _selectedEpisode;
  final Map<String, List<PlaybackStream>> _audioOptionsByItem = {};
  final Map<String, List<PlaybackStream>> _subtitleOptionsByItem = {};
  bool _loadingTrackOptions = false;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex;

  @override
  void initState() {
    super.initState();
    _selectedEpisode = widget.initialEpisodeIndex;
    _syncSelectedTrackSelectionsForCurrentItem(notify: false);
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
    if (playableItemsChanged) {
      _audioOptionsByItem.clear();
      _subtitleOptionsByItem.clear();
    }

    if (playableItemsChanged || episodeChanged) {
      _syncSelectedTrackSelectionsForCurrentItem();
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
    final mediaWithUserDataProvider = context
        .watch<MediaWithUserDataProvider>();
    final userDataProvider = context.watch<UserDataProvider>();
    final mediaItem = _resolveLiveMediaItem(
      mediaWithUserDataProvider: mediaWithUserDataProvider,
      userDataProvider: userDataProvider,
    );
    final episodes = _buildLiveEpisodes(userDataProvider);
    final cast = mediaItem.cast;
    final clampedEpisode = _selectedEpisode.clamp(0, episodes.length - 1);
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
                      loading: _loadingTrackOptions,
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
                                  episodes[_selectedEpisode];
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
                                    : () =>
                                          _handlePlayPressed(_selectedEpisode),
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
                                final isSelected = index == _selectedEpisode;
                                return InkWell(
                                  onTap: () {
                                    _inheritTrackSelectionIfNeeded(
                                      fromItem: _currentPlayableItem,
                                      toItem: episodes[index],
                                    );
                                    setState(() {
                                      _selectedEpisode = index;
                                      _syncSelectedTrackSelectionsForCurrentItem(
                                        notify: false,
                                      );
                                    });
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

  List<MediaItem> _buildLiveEpisodes(UserDataProvider userDataProvider) {
    return widget.playableItems
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
                      final isSelected = index == _selectedEpisode;
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
                            setState(() {
                              _selectedEpisode = index;
                              _syncSelectedTrackSelectionsForCurrentItem(
                                notify: false,
                              );
                            });
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
    final episodes = _buildLiveEpisodes(context.read<UserDataProvider>());
    return episodes[_selectedEpisode.clamp(0, episodes.length - 1)];
  }

  String get _audioButtonLabel {
    if (_loadingTrackOptions) {
      return '加载中';
    }
    final selectedIndex = _selectedAudioIndex;
    final options = _audioOptionsByItem[_currentPlayableItem.mediaKey];
    final matched = selectedIndex == null
        ? _firstAudioStream(options)
        : options?.where((stream) => stream.index == selectedIndex);
    final title = matched?.isNotEmpty == true
        ? matched!.first.title
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

  Iterable<PlaybackStream>? _firstAudioStream(List<PlaybackStream>? streams) {
    if (streams == null || streams.isEmpty) {
      return null;
    }
    return [streams.first];
  }

  String get _subtitleButtonLabel {
    if (_loadingTrackOptions) {
      return '加载中';
    }
    final selectedIndex = _selectedSubtitleIndex ?? -1;
    if (selectedIndex < 0) {
      return '无字幕';
    }
    final options = _subtitleOptionsByItem[_currentPlayableItem.mediaKey];
    final matched = options?.where((stream) => stream.index == selectedIndex);
    final title = matched?.isNotEmpty == true
        ? matched!.first.title
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
    final manager = context.read<IMediaServiceManager>();
    final playbackRepository = context.read<PlaybackRepository>();
    final udp = context.read<UserDataProvider>();
    if (!_supportsPlaybackInfo(item)) {
      if (mounted) {
        setState(() {
          _selectedAudioIndex = udp.trackSelectionForItem(item)?.audioIndex;
          _selectedSubtitleIndex =
              udp.trackSelectionForItem(item)?.subtitleIndex ?? -1;
        });
      }
      return;
    }

    final cachedAudio = _audioOptionsByItem[item.mediaKey];
    final cachedSubtitle = _subtitleOptionsByItem[item.mediaKey];
    if (cachedAudio != null && cachedSubtitle != null) {
      final saved = udp.trackSelectionForItem(item);
      if (mounted) {
        setState(() {
          _selectedAudioIndex = saved?.audioIndex;
          _selectedSubtitleIndex = saved?.subtitleIndex ?? -1;
        });
      }
      return;
    }

    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      if (mounted) {
        setState(() {
          _selectedAudioIndex = udp.trackSelectionForItem(item)?.audioIndex;
          _selectedSubtitleIndex =
              udp.trackSelectionForItem(item)?.subtitleIndex ?? -1;
        });
      }
      return;
    }
    setState(() => _loadingTrackOptions = true);
    try {
      final saved = udp.trackSelectionForItem(item);
      final plan = await GetPlaybackPlanUseCase(playbackRepository).call(
        item,
        maxStreamingBitrate: _playbackPlanBitrate,
        audioStreamIndex: saved?.audioIndex,
        subtitleStreamIndex: saved?.subtitleIndex,
      );
      _audioOptionsByItem[item.mediaKey] = plan.audioStreams;
      _subtitleOptionsByItem[item.mediaKey] = plan.subtitleStreams;
      if (mounted) {
        setState(() {
          _selectedAudioIndex = saved?.audioIndex;
          _selectedSubtitleIndex = saved?.subtitleIndex ?? -1;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingTrackOptions = false);
    }
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择字幕', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ListTile(
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
    await _ensureTrackOptionsLoaded();
    return _audioOptionsByItem[_currentPlayableItem.mediaKey] ?? const [];
  }

  Future<List<PlaybackStream>> _ensureSubtitleOptions() async {
    await _ensureTrackOptionsLoaded();
    return _subtitleOptionsByItem[_currentPlayableItem.mediaKey] ?? const [];
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
    final udp = context.read<UserDataProvider>();
    final saved = udp.trackSelectionForItem(item);
    if ((saved?.subtitleIndex ?? -1) >= 0 &&
        (saved?.subtitleUri?.isEmpty ?? true)) {
      final options = await _ensureSubtitleOptions();
      if (!mounted) {
        return;
      }
      PlaybackStream? stream;
      for (final candidate in options) {
        if (candidate.index == saved?.subtitleIndex) {
          stream = candidate;
          break;
        }
      }
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

  bool _supportsPlaybackInfo(MediaItem item) {
    if (item.type == MediaType.movie) {
      return true;
    }

    return item.parentTitle != null || item.indexNumber != null;
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
