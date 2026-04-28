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

class TabletHomeScreen extends StatelessWidget {
  const TabletHomeScreen({
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
    required this.onOpenMobileSample,
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
  final VoidCallback onOpenMobileSample;

  @override
  Widget build(BuildContext context) {
    final allItems = libraryItems.values.expand((items) => items).toList();
    final featured = allItems.isNotEmpty ? allItems.first : null;
    final sidebarWidth = maxWidth >= 1200 ? 340.0 : 300.0;
    final contentWidth = maxWidth - sidebarWidth - 56;
    final hasContent = libraryItems.values.any((items) => items.isNotEmpty);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: sidebarWidth,
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'MeowHub',
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                        ),
                        _TabletSearchButton(
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '平板端使用左侧信息面板 + 右侧内容海报墙，更适合高频浏览。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    AppSurfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionHeader(
                            title: '布局样例',
                            subtitle: '保留响应式壳，单独强化手机端展示',
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: onOpenMobileSample,
                              icon: const Icon(Icons.phone_iphone_rounded),
                              label: const Text('打开手机样例'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppSurfaceCard(
                      child: Column(
                        children: [
                          _ServerSwitcherTile(
                            selectedServer: selectedServer,
                            hasSelectedServer: hasSelectedServer,
                            availableServers: availableServers,
                            onSelected: onServerSelected,
                            onClearSelection: onClearServerSelection,
                          ),
                          const SizedBox(height: 12),
                          StatusPill(
                            icon: Icons.favorite_rounded,
                            label: '收藏',
                            value: '$favoriteCount 部',
                          ),
                          const SizedBox(height: 12),
                          StatusPill(
                            icon: Icons.play_circle_rounded,
                            label: '续播',
                            value: '$inProgressCount 部',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppSurfaceCard(
                      padding: EdgeInsets.zero,
                      child: _FeaturedPanel(
                        featured: featured,
                        onTap: featured == null
                            ? onOpenMobileSample
                            : () => onMovieTap(featured),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: RefreshIndicator(
                  color: AppTheme.accentColor,
                  backgroundColor: AppTheme.cardColor,
                  onRefresh: onRefresh,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      if (!hasSelectedServer)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoFileSourceSelectedPanel(
                            onOpenFileSources: onOpenFileSources,
                          ),
                        )
                      else if (isLoading && !hasContent)
                        _TabletLoadingSliver(
                          crossAxisCount: _crossAxisCount(contentWidth),
                        )
                      else if (errorMessage != null && !hasContent)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _TabletErrorState(
                            message: errorMessage!,
                            onRetry: onRetry,
                          ),
                        )
                      else ...[
                        if (continueWatching.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: SectionHeader(
                                title: '继续播放',
                                subtitle: '从上次的位置继续',
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 200,
                              child: ListView.separated(
                                padding: const EdgeInsets.only(bottom: 18),
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: continueWatching.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 14),
                                itemBuilder: (context, index) {
                                  final mediaItem = continueWatching[index];
                                  return SizedBox(
                                    width: 304,
                                    child: _TabletContinueWatchingCard(
                                      mediaItem: mediaItem,
                                      onTap: () => onMovieTap(mediaItem),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: SectionHeader(
                              title: '最近添加',
                              subtitle: '最新入库的作品',
                            ),
                          ),
                        ),
                        if (recentlyAdded.isNotEmpty)
                          _TabletPosterGrid(
                            items: recentlyAdded,
                            crossAxisCount: _crossAxisCount(contentWidth),
                            onMovieTap: onMovieTap,
                          )
                        else
                          const SliverToBoxAdapter(child: SizedBox.shrink()),
                        for (final library in libraries)
                          if (libraryItems[library.id]?.isNotEmpty == true) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 18,
                                  bottom: 18,
                                ),
                                child: SectionHeader(
                                  title: library.name,
                                  subtitle:
                                      '共 ${libraryItems[library.id]?.length ?? 0} 部',
                                  action: TextButton.icon(
                                    onPressed: () =>
                                        onOpenLibraryCollection(library),
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('查看全部'),
                                  ),
                                ),
                              ),
                            ),
                            _TabletPosterGrid(
                              items:
                                  libraryItems[library.id] ?? const [],
                              crossAxisCount: _crossAxisCount(contentWidth),
                              onMovieTap: onMovieTap,
                            ),
                          ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _crossAxisCount(double width) {
    if (width >= 1100) {
      return 5;
    }
    if (width >= 860) {
      return 4;
    }
    return 3;
  }
}

class _TabletPosterGrid extends StatelessWidget {
  const _TabletPosterGrid({
    required this.items,
    required this.crossAxisCount,
    required this.onMovieTap,
  });

  final List<MediaItem> items;
  final int crossAxisCount;
  final ValueChanged<MediaItem> onMovieTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (context, index) {
        final mediaItem = items[index];
        return Builder(
          builder: (context) {
            final isFavorite = context.select<UserDataProvider, bool>(
              (provider) => provider.isFavorite(mediaItem.id),
            );
            final progress = context.select<UserDataProvider, double>(
              (provider) => provider.progressFractionForItem(mediaItem),
            );
            final isContinueWatching = context.select<UserDataProvider, bool>(
              (provider) =>
                  provider.latestContinueWatchingMediaKey == mediaItem.mediaKey,
            );

            return PosterCard(
              mediaItem: mediaItem,
              isFavorite: isFavorite,
              isContinueWatching: isContinueWatching,
              progress: progress,
              onTap: () => onMovieTap(mediaItem),
            );
          },
        );
      },
    );
  }
}

class _TabletContinueWatchingCard extends StatelessWidget {
  const _TabletContinueWatchingCard({
    required this.mediaItem,
    required this.onTap,
  });

  final MediaItem mediaItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<UserDataProvider, double>(
      (provider) => provider.progressFractionForItem(mediaItem),
    );
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();

    return Material(
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
                DecoratedBox(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mediaItem.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        mediaItem.type == MediaType.series ? '电视剧' : '电影',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value:
                              normalizedProgress > 0 ? normalizedProgress : 0.02,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
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
        ),
      ),
    );
  }
}

class _ServerSwitcherTile extends StatelessWidget {
  const _ServerSwitcherTile({
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

class _NoFileSourceSelectedPanel extends StatelessWidget {
  const _NoFileSourceSelectedPanel({required this.onOpenFileSources});

  final VoidCallback onOpenFileSources;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.dns_outlined,
                size: 48,
                color: AppTheme.accentColor,
              ),
              const SizedBox(height: 18),
              Text(
                '媒体库暂未连接文件源',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '你可以先去文件源页选择一个服务器，或稍后再回来。连接建立后，海报墙和续播状态会按当前服务器重新刷新。',
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
    );
  }
}

class _FeaturedPanel extends StatelessWidget {
  const _FeaturedPanel({required this.featured, required this.onTap});

  final MediaItem? featured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本周主推', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            AspectRatio(
              aspectRatio: 1.25,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accentColor.withValues(alpha: 0.28),
                        const Color(0xFF161616),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Text(
                          featured?.title ?? '等待主推内容',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          featured?.overview ?? '加载成功后，这里会展示一张更适合大屏的主推卡片。',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletLoadingSliver extends StatelessWidget {
  const _TabletLoadingSliver({required this.crossAxisCount});

  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      itemCount: 12,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (context, index) => const PosterCardSkeleton(),
    );
  }
}

class _TabletErrorState extends StatelessWidget {
  const _TabletErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppSurfaceCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Colors.white.withValues(alpha: 0.72),
              ),
              const SizedBox(height: 14),
              Text(
                '海报墙加载失败',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('重新加载')),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabletSearchButton extends StatelessWidget {
  const _TabletSearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '搜索',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.search_rounded, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}
