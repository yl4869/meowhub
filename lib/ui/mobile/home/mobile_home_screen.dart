import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/poster_card.dart';
import '../../atoms/poster_card_skeleton.dart';
import '../../atoms/section_header.dart';
import '../../atoms/status_pill.dart';

class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({
    super.key,
    required this.maxWidth,
    required this.movies,
    required this.series,
    required this.recentWatching,
    required this.isLoading,
    required this.errorMessage,
    required this.selectedServer,
    required this.availableServers,
    required this.favoriteCount,
    required this.inProgressCount,
    required this.onRefresh,
    required this.onRetry,
    required this.onMovieTap,
    required this.onOpenLibraryCollection,
    required this.onServerSelected,
  });

  final double maxWidth;
  final List<MediaItem> movies;
  final List<MediaItem> series;
  final List<MediaItem> recentWatching;
  final bool isLoading;
  final String? errorMessage;
  final MediaServerInfo selectedServer;
  final List<MediaServerInfo> availableServers;
  final int favoriteCount;
  final int inProgressCount;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<MediaItem> onMovieTap;
  final ValueChanged<MediaType> onOpenLibraryCollection;
  final ValueChanged<MediaServerInfo> onServerSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.accentColor,
        backgroundColor: AppTheme.cardColor,
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _ServerSwitcherPill(
                          selectedServer: selectedServer,
                          availableServers: availableServers,
                          onSelected: onServerSelected,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TopActionButton(
                      icon: Icons.search_rounded,
                      tooltip: '搜索',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('搜索功能准备中')),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    _TopActionButton(
                      icon: Icons.refresh_rounded,
                      tooltip: '刷新',
                      onTap: () {
                        onRefresh();
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (isLoading && movies.isEmpty)
              const SliverToBoxAdapter(child: _HomeLoadingShelves())
            else if (errorMessage != null && movies.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _HomeErrorState(
                  message: errorMessage!,
                  onRetry: onRetry,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _ShelfSection(
                  title: '最近观看',
                  subtitle: recentWatching.isEmpty ? '还没有续播记录' : '从上次的位置继续',
                  child: SizedBox(
                    // Bump height to avoid rare bottom overflow when text scales
                    // push the progress bar and label beyond 184px.
                    height: 200,
                    child: recentWatching.isEmpty
                        ? const _EmptyShelfState(
                            icon: Icons.history_rounded,
                            message: '开始播放后，这里会出现宽卡片续播货架',
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < recentWatching.length;
                                  index++
                                ) ...[
                                  Builder(
                                    builder: (context) {
                                      final mediaItem = recentWatching[index];
                                      final localProgress = context
                                          .select<UserDataProvider, double>(
                                            (provider) => provider
                                                .progressFractionForItem(
                                                  mediaItem,
                                                ),
                                          );
                                      final progress = localProgress > 0
                                          ? localProgress
                                          : mediaItem
                                                    .playbackProgress
                                                    ?.fraction ??
                                                0;
                                      return _RecentWatchCard(
                                        mediaItem: mediaItem,
                                        progress: progress,
                                        onTap: () => onMovieTap(mediaItem),
                                      );
                                    },
                                  ),
                                  if (index != recentWatching.length - 1)
                                    const SizedBox(width: 14),
                                ],
                              ],
                            ),
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _ShelfSection(
                  title: '电视剧',
                  subtitle: '适合连刷的剧集推荐',
                  action: TextButton.icon(
                    onPressed: () => onOpenLibraryCollection(MediaType.series),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('查看全部'),
                  ),
                  child: _PosterShelf(items: series, onMovieTap: onMovieTap),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: _ShelfSection(
                    title: '电影',
                    subtitle: '适合今晚开的精选影片',
                    action: TextButton.icon(
                      onPressed: () => onOpenLibraryCollection(MediaType.movie),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('查看全部'),
                    ),
                    child: _PosterShelf(items: movies, onMovieTap: onMovieTap),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SectionHeader(
              title: title,
              subtitle: subtitle,
              action: action,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _PosterShelf extends StatelessWidget {
  const _PosterShelf({required this.items, required this.onMovieTap});

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onMovieTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox(
        height: 210,
        child: _EmptyShelfState(
          icon: Icons.video_library_outlined,
          message: '这里会展示可浏览的内容卡片',
        ),
      );
    }

    return SizedBox(
      height: 234,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final mediaItem = items[index];
          return SizedBox(
            width: 136,
            child: Builder(
              builder: (context) {
                final isFavorite = context.select<UserDataProvider, bool>(
                  (provider) => provider.isFavorite(mediaItem.id),
                );
                final progress = context.select<UserDataProvider, double>(
                  (provider) => provider.progressFractionForItem(mediaItem),
                );
                final isRecent = context.select<UserDataProvider, bool>(
                  (provider) =>
                      provider.latestRecentMediaKey == mediaItem.mediaKey,
                );

                return PosterCard(
                  mediaItem: mediaItem,
                  isFavorite: isFavorite,
                  isRecent: isRecent,
                  progress: progress,
                  onTap: () => onMovieTap(mediaItem),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RecentWatchCard extends StatelessWidget {
  const _RecentWatchCard({
    required this.mediaItem,
    required this.progress,
    required this.onTap,
  });

  final MediaItem mediaItem;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: 304,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mediaItem.backdropUrl case final backdropUrl?
                      when backdropUrl.isNotEmpty)
                    CachedNetworkImage(imageUrl: backdropUrl, fit: BoxFit.cover)
                  else
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF242424), Color(0xFF121212)],
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _RecentPosterPreview(mediaItem: mediaItem),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mediaItem.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mediaItem.type == MediaType.series
                                    ? '电视剧'
                                    : '电影',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                mediaItem.overview,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const Spacer(),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: normalizedProgress > 0
                                      ? normalizedProgress
                                      : 0.02,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.12,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        AppTheme.accentColor,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '继续观看',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentPosterPreview extends StatelessWidget {
  const _RecentPosterPreview({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final posterUrl = mediaItem.posterUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 84,
        height: 126,
        child: posterUrl != null && posterUrl.isNotEmpty
            ? CachedNetworkImage(imageUrl: posterUrl, fit: BoxFit.cover)
            : const ColoredBox(
                color: Color(0xFF181818),
                child: Icon(
                  Icons.movie_outlined,
                  color: Colors.white38,
                  size: 28,
                ),
              ),
      ),
    );
  }
}

class _ServerSwitcherPill extends StatelessWidget {
  const _ServerSwitcherPill({
    required this.selectedServer,
    required this.availableServers,
    required this.onSelected,
  });

  final MediaServerInfo selectedServer;
  final List<MediaServerInfo> availableServers;
  final ValueChanged<MediaServerInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MediaServerInfo>(
      tooltip: '切换媒体服务器',
      color: AppTheme.cardColor,
      onSelected: onSelected,
      itemBuilder: (context) {
        return availableServers.map((server) {
          final isSelected = server.id == selectedServer.id;
          return PopupMenuItem<MediaServerInfo>(
            value: server,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.dns_rounded,
                  size: 18,
                  color: isSelected ? AppTheme.accentColor : Colors.white70,
                ),
                const SizedBox(width: 10),
                Text('${server.name} · ${server.region}'),
              ],
            ),
          );
        }).toList();
      },
      child: StatusPill(
        icon: Icons.dns_rounded,
        label: '当前线路',
        value: selectedServer.name,
        accent: true,
        trailingIcon: Icons.unfold_more_rounded,
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _HomeLoadingShelves extends StatelessWidget {
  const _HomeLoadingShelves();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Match the real shelf height to keep skeleton sizes consistent.
        _LoadingShelf(title: '最近观看', height: 200, itemWidth: 304, count: 2),
        _LoadingShelf(title: '电视剧', height: 234, itemWidth: 136, count: 5),
        _LoadingShelf(title: '电影', height: 234, itemWidth: 136, count: 5),
      ],
    );
  }
}

class _LoadingShelf extends StatelessWidget {
  const _LoadingShelf({
    required this.title,
    required this.height,
    required this.itemWidth,
    required this.count,
  });

  final String title;
  final double height;
  final double itemWidth;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: AppSurfaceCard(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SectionHeader(title: title, subtitle: '加载中'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: height,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) => SizedBox(
                  width: itemWidth,
                  child: const PosterCardSkeleton(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyShelfState extends StatelessWidget {
  const _EmptyShelfState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 34, color: Colors.white38),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeErrorState extends StatelessWidget {
  const _HomeErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AppSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 52,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
                const SizedBox(height: 16),
                Text(
                  '暂时没拿到海报墙数据',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('重新加载')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
