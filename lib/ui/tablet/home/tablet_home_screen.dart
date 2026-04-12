import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/media_item.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/poster_card.dart';
import '../../atoms/poster_card_skeleton.dart';
import '../../atoms/section_header.dart';
import '../../atoms/status_pill.dart';

class TabletHomeScreen extends StatelessWidget {
  const TabletHomeScreen({
    super.key,
    required this.maxWidth,
    required this.movies,
    required this.isLoading,
    required this.errorMessage,
    required this.selectedServer,
    required this.availableServers,
    required this.favoriteCount,
    required this.inProgressCount,
    required this.onRefresh,
    required this.onRetry,
    required this.onMovieTap,
    required this.onServerSelected,
    required this.onOpenMobileSample,
  });

  final double maxWidth;
  final List<MediaItem> movies;
  final bool isLoading;
  final String? errorMessage;
  final MediaServerInfo selectedServer;
  final List<MediaServerInfo> availableServers;
  final int favoriteCount;
  final int inProgressCount;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final ValueChanged<MediaItem> onMovieTap;
  final ValueChanged<MediaServerInfo> onServerSelected;
  final VoidCallback onOpenMobileSample;

  @override
  Widget build(BuildContext context) {
    final featured = movies.isNotEmpty ? movies.first : null;
    final sidebarWidth = maxWidth >= 1200 ? 340.0 : 300.0;
    final contentWidth = maxWidth - sidebarWidth - 56;

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
                    Text(
                      'MeowHub',
                      style: Theme.of(context).textTheme.headlineLarge,
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
                            availableServers: availableServers,
                            onSelected: onServerSelected,
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
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: SectionHeader(
                            title: '海报墙',
                            subtitle: '针对平板端放大海报密度和状态信息',
                            action: TextButton.icon(
                              onPressed: onOpenMobileSample,
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('手机样例'),
                            ),
                          ),
                        ),
                      ),
                      if (isLoading && movies.isEmpty)
                        _TabletLoadingSliver(
                          crossAxisCount: _crossAxisCount(contentWidth),
                        )
                      else if (errorMessage != null && movies.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _TabletErrorState(
                            message: errorMessage!,
                            onRetry: onRetry,
                          ),
                        )
                      else
                        SliverGrid.builder(
                          itemCount: movies.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: _crossAxisCount(contentWidth),
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 18,
                                childAspectRatio: 0.66,
                              ),
                          itemBuilder: (context, index) {
                            final mediaItem = movies[index];
                            return Builder(
                              builder: (context) {
                                final isFavorite = context
                                    .select<AppProvider, bool>(
                                      (provider) =>
                                          provider.isFavorite(mediaItem.id),
                                    );
                                final progress = context
                                    .select<AppProvider, double>(
                                      (provider) => provider
                                          .progressFractionFor(mediaItem.id),
                                    );
                                final isRecent = context
                                    .select<AppProvider, bool>(
                                      (provider) => provider
                                          .latestRecentMediaId ==
                                              mediaItem.id,
                                    );

                                return PosterCard(
                                  mediaItem: mediaItem,
                                  isFavorite: isFavorite,
                                  isRecent: isRecent,
                                  progress: progress,
                                  onTap: () => onMovieTap(mediaItem),
                                );
                              },
                            );
                          },
                        ),
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

class _ServerSwitcherTile extends StatelessWidget {
  const _ServerSwitcherTile({
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
