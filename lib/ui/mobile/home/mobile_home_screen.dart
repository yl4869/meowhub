import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_library_info.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/poster_card.dart';
import '../../atoms/poster_card_skeleton.dart';
import '../../atoms/section_header.dart';
import '../../atoms/status_pill.dart';
import '../../screens/search_screen.dart';

class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({
    super.key,
    required this.maxWidth,
    required this.libraries,
    required this.continueWatching,
    required this.recentlyAdded,
    required this.libraryItems,
    required this.isLoading,
    required this.errorMessage,
    required this.selectedServer,
    required this.hasSelectedServer,
    required this.availableServers,
    required this.favoriteCount,
    required this.inProgressCount,
    required this.onRefresh,
    required this.onRetry,
    required this.onMovieTap,
    required this.onOpenLibraryCollection,
    required this.onServerSelected,
    required this.onClearServerSelection,
    required this.onOpenFileSources,
  });

  final double maxWidth;
  final List<MediaLibraryInfo> libraries;
  final List<MediaItem> continueWatching;
  final List<MediaItem> recentlyAdded;
  final Map<String, List<MediaItem>> libraryItems;
  final bool isLoading;
  final String? errorMessage;
  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;
  final List<MediaServerInfo> availableServers;
  final int favoriteCount;
  final int inProgressCount;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<MediaItem> onMovieTap;
  final ValueChanged<MediaLibraryInfo> onOpenLibraryCollection;
  final ValueChanged<MediaServerInfo> onServerSelected;
  final VoidCallback onClearServerSelection;
  final VoidCallback onOpenFileSources;

  @override
  Widget build(BuildContext context) {
    final hasContent = libraryItems.values.any((items) => items.isNotEmpty);

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
                          hasSelectedServer: hasSelectedServer,
                          availableServers: availableServers,
                          onSelected: onServerSelected,
                          onClearSelection: onClearServerSelection,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _TopActionButton(
                      icon: Icons.search_rounded,
                      tooltip: '搜索',
                      onTap: () async {
                        final result = await showSearch<MediaItem?>(
                          context: context,
                          delegate: MeowSearchDelegate(),
                        );
                        if (result != null && context.mounted) {
                          onMovieTap(result);
                        }
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
            if (!hasSelectedServer)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NoFileSourceSelectedCard(
                  onOpenFileSources: onOpenFileSources,
                ),
              )
            else if (isLoading && !hasContent)
              const SliverToBoxAdapter(child: _HomeLoadingShelves())
            else if (errorMessage != null && !hasContent)
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
                  title: '继续播放',
                  subtitle: continueWatching.isEmpty
                      ? '还没有可继续播放的内容'
                      : '从上次的位置继续',
                  child: SizedBox(
                    height: 200,
                    child: continueWatching.isEmpty
                        ? const _EmptyShelfState(
                            icon: Icons.play_circle_outline_rounded,
                            message: '开始播放后，这里会出现可继续播放的内容',
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < continueWatching.length;
                                  index++
                                ) ...[
                                  Builder(
                                    builder: (context) {
                                      final mediaItem = continueWatching[index];
                                      final progress = context
                                          .select<UserDataProvider, double>(
                                            (provider) => provider
                                                .progressFractionForItem(
                                                  mediaItem,
                                                ),
                                          );
                                      return _ContinueWatchingCard(
                                        mediaItem: mediaItem,
                                        progress: progress,
                                        onTap: () => onMovieTap(mediaItem),
                                      );
                                    },
                                  ),
                                  if (index != continueWatching.length - 1)
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
                  title: '最近添加',
                  subtitle: recentlyAdded.isEmpty
                      ? '还没有最近添加的内容'
                      : '最新入库的作品',
                  child: _PosterShelf(
                    items: recentlyAdded,
                    onMovieTap: onMovieTap,
                  ),
                ),
              ),
              for (final library in libraries)
                if (libraryItems[library.id]?.isNotEmpty == true)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: library == libraries.lastWhere(
                          (l) => libraryItems[l.id]?.isNotEmpty == true,
                          orElse: () => library,
                        )
                            ? 28
                            : 0,
                      ),
                      child: _ShelfSection(
                        title: library.name,
                        subtitle: '共 ${libraryItems[library.id]?.length ?? 0} 部',
                        action: TextButton.icon(
                          onPressed: () =>
                              onOpenLibraryCollection(library),
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                          label: const Text('查看全部'),
                        ),
                        child: _PosterShelf(
                          items:
                              libraryItems[library.id] ?? const [],
                          onMovieTap: onMovieTap,
                        ),
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
                final isContinueWatching = context
                    .select<UserDataProvider, bool>(
                      (provider) =>
                          provider.latestContinueWatchingMediaKey ==
                          mediaItem.mediaKey,
                    );

                return PosterCard(
                  mediaItem: mediaItem,
                  isFavorite: isFavorite,
                  isContinueWatching: isContinueWatching,
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

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
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
                        _ContinueWatchingPosterPreview(mediaItem: mediaItem),
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
                                '继续播放',
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

class _ContinueWatchingPosterPreview extends StatelessWidget {
  const _ContinueWatchingPosterPreview({required this.mediaItem});

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
    required this.hasSelectedServer,
    required this.availableServers,
    required this.onSelected,
    required this.onClearSelection,
  });

  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;
  final List<MediaServerInfo> availableServers;
  final ValueChanged<MediaServerInfo> onSelected;
  final VoidCallback onClearSelection;

  static const String _noneSelectedValue = '__none__';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '切换媒体服务器',
      color: AppTheme.cardColor,
      onSelected: (value) {
        if (value == _noneSelectedValue) {
          onClearSelection();
          return;
        }
        for (final server in availableServers) {
          if (server.id == value) {
            onSelected(server);
            return;
          }
        }
      },
      itemBuilder: (context) {
        final entries = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: _noneSelectedValue,
            child: Row(
              children: [
                Icon(
                  hasSelectedServer
                      ? Icons.radio_button_off_rounded
                      : Icons.radio_button_checked,
                  size: 18,
                  color: !hasSelectedServer
                      ? AppTheme.accentColor
                      : Colors.white70,
                ),
                const SizedBox(width: 10),
                const Text('未选择文件源'),
              ],
            ),
          ),
        ];
        entries.addAll(
          availableServers.map((server) {
            final isSelected =
                hasSelectedServer && server.id == selectedServer.id;
            return PopupMenuItem<String>(
              value: server.id,
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
          }),
        );
        return entries;
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

class _NoFileSourceSelectedCard extends StatelessWidget {
  const _NoFileSourceSelectedCard({required this.onOpenFileSources});

  final VoidCallback onOpenFileSources;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AppSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.dns_outlined,
                  size: 42,
                  color: AppTheme.accentColor,
                ),
                const SizedBox(height: 16),
                Text(
                  '先选择一个文件源',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  '当前媒体库没有连接到任何服务器。选择文件源后，我们会重新拉取电影、电视剧和继续播放内容。',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onOpenFileSources,
                  icon: const Icon(Icons.dns_rounded),
                  label: const Text('去选择文件源'),
                ),
              ],
            ),
          ),
        ),
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
        _LoadingShelf(title: '继续播放', height: 200, itemWidth: 304, count: 2),
        _LoadingShelf(title: '最近添加', height: 234, itemWidth: 136, count: 5),
        _LoadingShelf(title: '媒体库', height: 234, itemWidth: 136, count: 5),
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
