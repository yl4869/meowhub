import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/cast.dart';
import '../../../models/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/cast_list_section.dart';
import '../../atoms/info_chip.dart';
import '../../atoms/info_row.dart';

class TabletMediaDetailScreen extends StatefulWidget {
  const TabletMediaDetailScreen({
    super.key,
    required this.maxWidth,
    required this.mediaItem,
    required this.selectedServer,
    required this.isFavorite,
    required this.hasRecentWatchRecord,
    required this.initialEpisodeIndex,
    required this.playbackProgress,
    required this.onPlayPressed,
    required this.onToggleFavorite,
  });

  final double maxWidth;
  final MediaItem mediaItem;
  final MediaServerInfo selectedServer;
  final bool isFavorite;
  final bool hasRecentWatchRecord;
  final int initialEpisodeIndex;
  final MediaPlaybackProgress? playbackProgress;
  final ValueChanged<int>? onPlayPressed;
  final VoidCallback onToggleFavorite;

  @override
  State<TabletMediaDetailScreen> createState() =>
      _TabletMediaDetailScreenState();
}

class _TabletMediaDetailScreenState extends State<TabletMediaDetailScreen> {
  late int _selectedEpisode;

  @override
  void initState() {
    super.initState();
    _selectedEpisode = widget.initialEpisodeIndex;
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _buildEpisodes(widget.mediaItem);
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
            expandedHeight: 280,
            backgroundColor: AppTheme.backgroundColor,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.mediaItem.title),
              centerTitle: true,
              background: _TabletHeader(mediaItem: widget.mediaItem),
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
                            widget.mediaItem.title,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 16),
                          _TabletMetaRow(mediaItem: widget.mediaItem),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: widget.onPlayPressed == null
                                      ? null
                                      : () =>
                                            widget.onPlayPressed!(
                                              _selectedEpisode,
                                            ),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54),
                                  ),
                                  child: Text(
                                    widget.hasRecentWatchRecord
                                        ? '继续播放'
                                        : '立即播放',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              _TabletIconButton(
                                icon: widget.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                onTap: widget.onToggleFavorite,
                                active: widget.isFavorite,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                  ),
                                  child: Text(
                                    '选集列表',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
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
                                      final isSelected =
                                          index == _selectedEpisode;
                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedEpisode = index;
                                          });
                                        },
                                        borderRadius: BorderRadius.circular(14),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? Colors.blue
                                                : AppTheme.backgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Text(
                                            episodes[index],
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '剧情简介',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.mediaItem.overview.isNotEmpty
                                      ? widget.mediaItem.overview
                                      : '暂时还没有这部作品的简介。',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              ],
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
                            mediaItem: widget.mediaItem,
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

  List<String> _buildEpisodes(MediaItem mediaItem) {
    if (mediaItem.type == MediaType.movie) {
      return List.generate(4, (index) => '片段 ${index + 1}');
    }
    return List.generate(12, (index) => '第 ${index + 1} 集');
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
