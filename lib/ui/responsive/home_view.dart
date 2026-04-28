import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_library_info.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/media_library_provider.dart';
import '../../providers/media_with_user_data_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../theme/app_theme.dart';
import '../atoms/app_surface_card.dart';
import '../atoms/section_header.dart';
import '../file_source/add_file_source_sheet.dart';
import '../file_source/file_source_tile.dart';
import '../mobile/home/mobile_home_screen.dart';
import '../mobile/sample/mobile_ui_sample_view.dart';
import '../tablet/home/tablet_home_screen.dart';
import 'media_detail_view.dart';
import 'media_library_collection_view.dart';
import 'responsive_layout_builder.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  static const String routePath = '/';

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appProvider = context.read<AppProvider>();
    final mediaWithUserData = context.watch<MediaWithUserDataProvider>();
    final mediaLibraryProvider = context.read<MediaLibraryProvider>();

    final selectedServer = context.select<AppProvider, MediaServerInfo>(
      (provider) => provider.selectedServer,
    );
    final hasSelectedServer = context.select<AppProvider, bool>(
      (provider) => provider.hasSelectedServer,
    );
    final availableServers = appProvider.availableServers.toList(
      growable: false,
    );
    final favoriteCount = mediaWithUserData.allItems
        .where((item) => item.isFavorite)
        .length;
    final inProgressCount = mediaWithUserData.continueWatching.length;

    final tabs = <Widget>[
      _MediaLibraryTab(
        libraries: mediaWithUserData.libraries,
        continueWatching: mediaWithUserData.continueWatching,
        recentlyAdded: mediaWithUserData.recentlyAdded,
        libraryItems: mediaWithUserData.libraryItems,
        isLoading: mediaWithUserData.isLoading,
        errorMessage: mediaWithUserData.errorMessage,
        selectedServer: selectedServer,
        hasSelectedServer: hasSelectedServer,
        availableServers: availableServers,
        favoriteCount: favoriteCount,
        inProgressCount: inProgressCount,
        onRefresh: mediaLibraryProvider.refreshMedia,
        onRetry: mediaLibraryProvider.loadInitialMedia,
        onMovieTap: (mediaItem) => _openMovie(context, mediaItem),
        onOpenLibraryCollection: (libraryInfo) =>
            _openLibraryCollection(context, libraryInfo),
        onServerSelected: appProvider.selectServer,
        onClearServerSelection: appProvider.clearSelectedServer,
        onOpenFileSources: () {
          setState(() {
            _currentIndex = 1;
          });
        },
        onOpenMobileSample: () => _openMobileSample(context),
      ),
      _FileSourceTab(
        selectedServer: selectedServer,
        hasSelectedServer: hasSelectedServer,
        availableServers: availableServers,
        onServerSelected: appProvider.selectServer,
        onClearServerSelection: appProvider.clearSelectedServer,
      ),
      _MyTab(
        favoriteItems: mediaWithUserData.allItems
            .where((item) => item.isFavorite)
            .toList(),
        watchHistory: context.read<UserDataProvider>().watchHistory,
        selectedServer: selectedServer,
        hasSelectedServer: hasSelectedServer,
        libraryCount: mediaWithUserData.libraries.length,
        onMovieTap: (mediaItem) => _openMovie(context, mediaItem),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: AppTheme.backgroundColor,
        indicatorColor: AppTheme.accentColor.withValues(alpha: 0.18),
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library_rounded),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: '文件源',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }

  void _openMovie(BuildContext context, MediaItem mediaItem) {
    context.push(MediaDetailView.locationFor(mediaItem.id), extra: mediaItem);
  }

  void _openMobileSample(BuildContext context) {
    context.push(MobileUiSampleView.routePath);
  }

  void _openLibraryCollection(
    BuildContext context,
    MediaLibraryInfo libraryInfo,
  ) {
    context.push(
      MediaLibraryCollectionView.locationFor(libraryInfo.id),
      extra: libraryInfo,
    );
  }
}

class _MediaLibraryTab extends StatelessWidget {
  const _MediaLibraryTab({
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
    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) {
        return MobileHomeScreen(
          maxWidth: maxWidth,
          libraries: libraries,
          continueWatching: continueWatching,
          recentlyAdded: recentlyAdded,
          libraryItems: libraryItems,
          isLoading: isLoading,
          errorMessage: errorMessage,
          selectedServer: selectedServer,
          hasSelectedServer: hasSelectedServer,
          availableServers: availableServers,
          favoriteCount: favoriteCount,
          inProgressCount: inProgressCount,
          onRefresh: onRefresh,
          onRetry: onRetry,
          onMovieTap: onMovieTap,
          onOpenLibraryCollection: onOpenLibraryCollection,
          onServerSelected: onServerSelected,
          onClearServerSelection: onClearServerSelection,
          onOpenFileSources: onOpenFileSources,
        );
      },
      tabletBuilder: (context, maxWidth) {
        return TabletHomeScreen(
          maxWidth: maxWidth,
          libraries: libraries,
          continueWatching: continueWatching,
          recentlyAdded: recentlyAdded,
          libraryItems: libraryItems,
          isLoading: isLoading,
          errorMessage: errorMessage,
          selectedServer: selectedServer,
          hasSelectedServer: hasSelectedServer,
          availableServers: availableServers,
          favoriteCount: favoriteCount,
          inProgressCount: inProgressCount,
          onRefresh: onRefresh,
          onRetry: onRetry,
          onMovieTap: onMovieTap,
          onOpenLibraryCollection: onOpenLibraryCollection,
          onServerSelected: onServerSelected,
          onClearServerSelection: onClearServerSelection,
          onOpenFileSources: onOpenFileSources,
          onOpenMobileSample: onOpenMobileSample,
        );
      },
    );
  }
}

class _FileSourceTab extends StatelessWidget {
  const _FileSourceTab({
    required this.selectedServer,
    required this.hasSelectedServer,
    required this.availableServers,
    required this.onServerSelected,
    required this.onClearServerSelection,
  });

  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;
  final List<MediaServerInfo> availableServers;
  final ValueChanged<MediaServerInfo> onServerSelected;
  final VoidCallback onClearServerSelection;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        physics: const BouncingScrollPhysics(),
        children: [
          SectionHeader(
            title: '文件源',
            subtitle: '管理当前接入的媒体线路与文件源。',
            action: FilledButton.icon(
              onPressed: () => _openAddSourceSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加'),
            ),
          ),
          const SizedBox(height: 20),
          AppSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSelectedServer
                      ? '当前正在使用 ${selectedServer.name}，你可以继续切换其他服务器，或退出当前文件源。'
                      : '当前未选择任何文件源，媒体库会显示引导提示，直到你重新选择一个服务器。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (hasSelectedServer) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onClearServerSelection,
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('退出当前文件源'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (availableServers.isNotEmpty) ...[
            _NoSelectionTile(
              isSelected: !hasSelectedServer,
              onTap: onClearServerSelection,
            ),
            const SizedBox(height: 12),
          ],
          if (availableServers.isEmpty)
            const AppSurfaceCard(child: Text('还没有可用文件源，先添加一个 Emby 服务器吧。'))
          else
            for (final server in availableServers) ...[
              FileSourceTile(
                server: server,
                isSelected: hasSelectedServer && server.id == selectedServer.id,
                onTap: () => onServerSelected(server),
                onEdit: server.isPlaceholder
                    ? null
                    : () => _openAddSourceSheet(context, initialServer: server),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  Future<void> _openAddSourceSheet(
    BuildContext context, {
    MediaServerInfo? initialServer,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardColor,
      builder: (_) {
        return AddFileSourceSheet(initialServer: initialServer);
      },
    );
  }
}

class _NoSelectionTile extends StatelessWidget {
  const _NoSelectionTile({required this.isSelected, required this.onTap});

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AppSurfaceCard(
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off_rounded,
                color: isSelected ? AppTheme.accentColor : Colors.white70,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '未选择文件源',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '保持媒体库未连接状态，稍后再选择其他服务器。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyTab extends StatelessWidget {
  const _MyTab({
    required this.favoriteItems,
    required this.watchHistory,
    required this.selectedServer,
    required this.hasSelectedServer,
    required this.libraryCount,
    required this.onMovieTap,
  });

  final List<MediaItem> favoriteItems;
  final List<WatchHistoryItem> watchHistory;
  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;
  final int libraryCount;
  final ValueChanged<MediaItem> onMovieTap;

  @override
  Widget build(BuildContext context) {
    final recentHistory = watchHistory.take(20).toList(growable: false);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        physics: const BouncingScrollPhysics(),
        children: [
          _ServerProfileCard(
            selectedServer: selectedServer,
            hasSelectedServer: hasSelectedServer,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.favorite_rounded,
                  label: '收藏',
                  value: '${favoriteItems.length} 部',
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.history_rounded,
                  label: '观看历史',
                  value: '${watchHistory.length} 部',
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.folder_rounded,
                  label: '媒体库',
                  value: '$libraryCount 个',
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ServerInfoCard(
            selectedServer: selectedServer,
            hasSelectedServer: hasSelectedServer,
          ),
          const SizedBox(height: 20),
          if (recentHistory.isNotEmpty) ...[
            const SectionHeader(title: '观看历史', subtitle: '最近观看过的内容'),
            const SizedBox(height: 12),
            for (var i = 0; i < recentHistory.length; i++) ...[
              _WatchHistoryTile(
                history: recentHistory[i],
                onTap: () => onMovieTap(
                  _mediaItemFromHistory(recentHistory[i]),
                ),
              ),
              if (i < recentHistory.length - 1) const SizedBox(height: 8),
            ],
            const SizedBox(height: 20),
          ],
          const SectionHeader(title: '我的收藏', subtitle: '已收藏的作品'),
          const SizedBox(height: 12),
          if (favoriteItems.isEmpty)
            const AppSurfaceCard(child: Text('还没有收藏内容，去媒体库挑几部喜欢的作品吧。'))
          else
            SizedBox(
              height: 186,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: favoriteItems.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = favoriteItems[index];
                  return SizedBox(
                    width: 120,
                    child: _FavoritePosterCard(
                      mediaItem: item,
                      onTap: () => onMovieTap(item),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  MediaItem _mediaItemFromHistory(WatchHistoryItem history) {
    final isEpisode = history.seriesId != null && history.seriesId!.isNotEmpty;
    final type = isEpisode ? MediaType.series : MediaType.movie;
    return MediaItem(
      id: (isEpisode ? history.seriesId! : history.id).hashCode,
      sourceId: isEpisode ? history.seriesId! : history.id,
      title: isEpisode ? (history.parentTitle ?? history.title) : history.title,
      originalTitle: history.originalTitle ?? history.title,
      type: type,
      sourceType: history.sourceType,
      posterUrl: history.poster.isNotEmpty ? history.poster : null,
      backdropUrl: history.backdrop,
      overview: history.overview ?? '',
      year: history.year,
      parentTitle: null,
      seriesId: null,
      parentIndexNumber: history.parentIndexNumber,
      indexNumber: history.indexNumber,
      playbackProgress: history.duration > Duration.zero
          ? MediaPlaybackProgress(
              position: history.position,
              duration: history.duration,
            )
          : null,
      lastPlayedAt: history.updatedAt,
    );
  }
}

class _ServerProfileCard extends StatelessWidget {
  const _ServerProfileCard({
    required this.selectedServer,
    required this.hasSelectedServer,
  });

  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasSelectedServer
                    ? [AppTheme.accentColor.withValues(alpha: 0.6), AppTheme.accentColor]
                    : [Colors.white24, Colors.white12],
              ),
            ),
            child: Icon(
              hasSelectedServer ? Icons.dns_rounded : Icons.dns_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasSelectedServer ? selectedServer.name : '未连接服务器',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  hasSelectedServer
                      ? selectedServer.baseUrl
                      : '前往文件源页添加服务器',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ServerInfoCard extends StatelessWidget {
  const _ServerInfoCard({
    required this.selectedServer,
    required this.hasSelectedServer,
  });

  final MediaServerInfo selectedServer;
  final bool hasSelectedServer;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: '服务器信息', subtitle: '当前文件源连接详情'),
          const SizedBox(height: 16),
          if (!hasSelectedServer)
            const Text('暂无连接', style: TextStyle(color: Colors.white54))
          else ...[
            _InfoRow(label: '名称', value: selectedServer.name),
            _InfoRow(label: '地址', value: selectedServer.baseUrl),
            _InfoRow(label: '类型', value: selectedServer.type.displayName),
            _InfoRow(
              label: '状态',
              value: '已连接',
              valueColor: AppTheme.accentColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchHistoryTile extends StatelessWidget {
  const _WatchHistoryTile({required this.history, required this.onTap});

  final WatchHistoryItem history;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progressPercent = (history.progressFraction * 100).round();
    final timeAgo = _formatRelativeTime(history.updatedAt);
    final posterUrl = history.poster.isNotEmpty ? history.poster : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AppSurfaceCard(
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: posterUrl != null
                      ? Image.network(
                          posterUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => _fallbackIcon(),
                        )
                      : _fallbackIcon(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      history.parentTitle ?? history.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (history.parentTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        history.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '已看 $progressPercent%',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                timeAgo,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _fallbackIcon() {
    return const ColoredBox(
      color: Color(0xFF1A1A1A),
      child: Icon(Icons.movie_outlined, color: Colors.white24, size: 24),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dateTime.month}/${dateTime.day}';
  }
}

class _FavoritePosterCard extends StatelessWidget {
  const _FavoritePosterCard({required this.mediaItem, required this.onTap});

  final MediaItem mediaItem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ColoredBox(
                  color: AppTheme.cardColor,
                  child: mediaItem.posterUrl != null
                      ? Image.network(
                          mediaItem.posterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(
                            Icons.movie_outlined,
                            color: Colors.white24,
                            size: 32,
                          ),
                        )
                      : const Icon(
                          Icons.movie_outlined,
                          color: Colors.white24,
                          size: 32,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mediaItem.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              mediaItem.type == MediaType.movie ? '电影' : '剧集',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
