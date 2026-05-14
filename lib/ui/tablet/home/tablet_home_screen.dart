import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/media_library_info.dart';
import '../../../domain/entities/scan_progress.dart';
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
    required this.scanProgress,
    required this.onRefresh,
    required this.onRescan,
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
  final ScanProgress scanProgress;
  final Future<void> Function() onRefresh;
  final VoidCallback onRescan;
  final VoidCallback onRetry;
  final ValueChanged<MediaItem> onMovieTap;
  final ValueChanged<MediaLibraryInfo> onOpenLibraryCollection;
  final ValueChanged<MediaServerInfo> onServerSelected;
  final VoidCallback onClearServerSelection;
  final VoidCallback onOpenFileSources;

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 18),
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
                    if (continueWatching.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      AppSurfaceCard(
                        padding: EdgeInsets.zero,
                        child: _NowWatchingCard(
                          item: continueWatching.first,
                          onTap: () => onMovieTap(continueWatching.first),
                        ),
                      ),
                    ],
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
                      if (scanProgress.isScanning)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _TabletScanStatusBanner(
                              icon: Icons.refresh_rounded,
                              message: scanProgress.message ?? '正在扫描文件夹...',
                            ),
                          ),
                        )
                      else if (scanProgress.isError)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _TabletScanStatusBanner(
                              icon: Icons.error_outline_rounded,
                              message: scanProgress.message ?? '扫描失败',
                              errors: scanProgress.errors,
                            ),
                          ),
                        )
                      else if (scanProgress.isCompleted && scanProgress.errors.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _TabletScanStatusBanner(
                              icon: Icons.warning_amber_rounded,
                              message: scanProgress.message ?? '扫描完成，但有部分错误',
                              errors: scanProgress.errors,
                            ),
                          ),
                        ),
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
                '未连接文件源',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '请先添加文件源以浏览媒体内容',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onOpenFileSources,
                icon: const Icon(Icons.dns_rounded),
                label: const Text('添加文件源'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowWatchingCard extends StatelessWidget {
  const _NowWatchingCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = context.select<UserDataProvider, double>(
      (provider) => provider.progressFractionForItem(item),
    );
    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.play_circle_filled_rounded,
                    size: 18, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Text('继续播放', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
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
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (item.overview.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.overview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: normalizedProgress > 0
                              ? normalizedProgress
                              : 0.02,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppTheme.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        normalizedProgress > 0
                            ? '已看 ${(normalizedProgress * 100).toInt()}%'
                            : '开始观看',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
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

class _TabletScanStatusBanner extends StatelessWidget {
  const _TabletScanStatusBanner({
    required this.icon,
    required this.message,
    this.errors = const [],
  });

  final IconData icon;
  final String message;
  final List<String> errors;

  bool get _isScanning => icon == Icons.refresh_rounded;

  @override
  Widget build(BuildContext context) {
    final accentColor = _isScanning
        ? AppTheme.accentColor
        : const Color(0xFFFF8A65);

    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: _isScanning
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accentColor,
                      )
                    : Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...errors.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  e,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
