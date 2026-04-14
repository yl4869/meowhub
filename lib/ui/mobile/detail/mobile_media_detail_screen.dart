import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../../../domain/repositories/media_service_manager.dart';
import '../../../data/datasources/emby_api_client.dart';
import '../../../data/repositories/emby_playback_repository_impl.dart';
import '../../../domain/usecases/get_playback_plan.dart';
import '../../../providers/user_data_provider.dart';

class MobileMediaDetailScreen extends StatefulWidget {
  const MobileMediaDetailScreen({
    super.key,
    required this.mediaItem,
    required this.selectedServer,
    required this.isFavorite,
    required this.hasRecentWatchRecord,
    required this.initialEpisodeIndex,
    required this.playableItems,
    required this.playbackProgress,
    required this.onPlayPressed,
    required this.onOpenTrackSelector,
    required this.onToggleFavorite,
  });

  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final bool isFavorite;
  final bool hasRecentWatchRecord;
  final int initialEpisodeIndex;
  final List<MediaItem> playableItems;
  final MediaPlaybackProgress? playbackProgress;
  final ValueChanged<int>? onPlayPressed;
  final ValueChanged<int> onOpenTrackSelector;
  final VoidCallback onToggleFavorite;

  @override
  State<MobileMediaDetailScreen> createState() =>
      _MobileMediaDetailScreenState();
}

class _MobileMediaDetailScreenState extends State<MobileMediaDetailScreen> {
  static const int _playbackPlanBitrate = 10 * 1000 * 1000;

  late int _selectedEpisode;
  final Map<String, List<PlaybackStream>> _subtitleOptionsByItem = {};
  bool _loadingSubtitles = false;
  int? _selectedSubtitleIndex;

  @override
  void initState() {
    super.initState();
    _selectedEpisode = widget.initialEpisodeIndex;
    _syncSelectedSubtitleForCurrentItem(notify: false);
  }

  @override
  void didUpdateWidget(covariant MobileMediaDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final episodeChanged =
        oldWidget.initialEpisodeIndex != widget.initialEpisodeIndex;

    if (episodeChanged) {
      _selectedEpisode = widget.initialEpisodeIndex;
    }

    if (oldWidget.playableItems != widget.playableItems) {
      _subtitleOptionsByItem.clear();
    }

    if (oldWidget.playableItems != widget.playableItems || episodeChanged) {
      _syncSelectedSubtitleForCurrentItem();
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.playableItems;
    final cast = widget.mediaItem.cast;
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
            expandedHeight: 248,
            backgroundColor: AppTheme.backgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: true,
              title: Text(widget.mediaItem.title),
              background: _PosterHeader(mediaItem: widget.mediaItem),
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
                    _MetaChipRow(
                      mediaItem: widget.mediaItem,
                      trailing: SizedBox(
                        width: 104,
                        child: _SubtitlePickerButton(
                          loading: _loadingSubtitles,
                          label: _subtitleButtonLabel,
                          onTap: _openSubtitleSelector,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.onPlayPressed == null
                                ? null
                                : () => widget.onPlayPressed!(_selectedEpisode),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            child: Text(
                              widget.hasRecentWatchRecord ? '继续播放' : '立即播放',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _ActionIconButton(
                          icon: widget.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          onTap: widget.onToggleFavorite,
                          active: widget.isFavorite,
                        ),
                        const SizedBox(width: 10),
                        _ActionIconButton(
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
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              '选集列表',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.titleColor,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 50,
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
                                    setState(() {
                                      _selectedEpisode = index;
                                      _syncSelectedSubtitleForCurrentItem(
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
                        overview: widget.mediaItem.overview,
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
                      mediaItem: widget.mediaItem,
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

  MediaItem get _currentPlayableItem => widget.playableItems[_selectedEpisode];

  String get _subtitleButtonLabel {
    if (_loadingSubtitles) {
      return '加载中';
    }
    final selectedIndex = _selectedSubtitleIndex ?? -1;
    if (selectedIndex < 0) {
      return '无字幕';
    }
    final options = _subtitleOptionsByItem[_currentPlayableItem.mediaKey];
    final matched = options?.where((stream) => stream.index == selectedIndex);
    final title = matched?.isNotEmpty == true ? matched!.first.title : null;
    return title ?? '字幕';
  }

  void _syncSelectedSubtitleForCurrentItem({bool notify = true}) {
    final saved = context.read<UserDataProvider>().trackSelectionForItem(
      _currentPlayableItem,
    );
    final nextValue = saved?.subtitleIndex ?? -1;
    if (!notify || !mounted) {
      _selectedSubtitleIndex = nextValue;
      return;
    }
    setState(() {
      _selectedSubtitleIndex = nextValue;
    });
  }

  Future<List<PlaybackStream>> _ensureSubtitleOptions() async {
    final item = _currentPlayableItem;
    final manager = context.read<MediaServiceManager>();
    final udp = context.read<UserDataProvider>();
    if (!_supportsPlaybackInfo(item)) {
      if (mounted) {
        setState(() {
          _selectedSubtitleIndex =
              udp.trackSelectionForItem(item)?.subtitleIndex ?? -1;
        });
      }
      return const [];
    }

    final cached = _subtitleOptionsByItem[item.mediaKey];
    if (cached != null) {
      return cached;
    }

    final config = manager.getSavedConfig();
    if (config == null || config.type != MediaServiceType.emby) {
      if (mounted) {
        setState(() {
          _selectedSubtitleIndex =
              udp.trackSelectionForItem(item)?.subtitleIndex ?? -1;
        });
      }
      return const [];
    }

    setState(() => _loadingSubtitles = true);
    try {
      final saved = udp.trackSelectionForItem(item);
      final api = EmbyApiClient(
        config: config,
        securityService: manager.securityService,
        sessionExpiredNotifier: manager.sessionExpiredNotifier,
      );
      final repo = EmbyPlaybackRepositoryImpl(
        apiClient: api,
        securityService: manager.securityService,
      );
      final plan = await GetPlaybackPlanUseCase(repo).call(
        item,
        maxStreamingBitrate: _playbackPlanBitrate,
        requireAvc: true,
        audioStreamIndex: saved?.audioIndex,
        subtitleStreamIndex: saved?.subtitleIndex,
      );
      if (kDebugMode) {
        debugPrint(
          '[Detail] subs fetched=${plan.subtitleStreams.length} item=${item.dataSourceId}',
        );
      }
      _subtitleOptionsByItem[item.mediaKey] = plan.subtitleStreams;
      if (mounted) {
        setState(() {
          _selectedSubtitleIndex = saved?.subtitleIndex ?? -1;
        });
      }
      return plan.subtitleStreams;
    } finally {
      if (mounted) setState(() => _loadingSubtitles = false);
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
                    leading: Icon(
                      initialValue == stream.index
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    title: Text(stream.title),
                    subtitle: stream.language == null
                        ? null
                        : Text(stream.language!),
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
    final udp = context.read<UserDataProvider>();
    udp.setTrackSelectionForItem(
      item,
      subtitleIndex: selected,
      audioIndex: udp.trackSelectionForItem(item)?.audioIndex,
    );
    setState(() {
      _selectedSubtitleIndex = selected;
    });
  }

  bool _supportsPlaybackInfo(MediaItem item) {
    if (item.type == MediaType.movie) {
      return true;
    }

    return item.parentTitle != null || item.indexNumber != null;
  }
}

class _SubtitlePickerButton extends StatelessWidget {
  const _SubtitlePickerButton({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool loading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        side: const BorderSide(color: Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        foregroundColor: Colors.white,
      ),
      child: loading
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
  const _MetaChipRow({required this.mediaItem, this.trailing});

  final MediaItem mediaItem;
  final Widget? trailing;

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
        if (trailing != null) ...[
          const SizedBox(width: 18),
          Align(alignment: Alignment.topRight, child: trailing!),
        ],
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
