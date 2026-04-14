import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/media_library_provider.dart';
import '../../providers/media_with_user_data_provider.dart';
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
    final availableServers = appProvider.availableServers.toList(
      growable: false,
    );
    final favoriteCount = mediaWithUserData.allItems
        .where((item) => item.isFavorite)
        .length;
    final inProgressCount = mediaWithUserData.recentWatching.length;

    final tabs = <Widget>[
      _MediaLibraryTab(
        movies: mediaWithUserData.enrichedMovies,
        series: mediaWithUserData.enrichedSeries,
        recentWatching: mediaWithUserData.recentWatching,
        isLoading: mediaWithUserData.isLoading,
        errorMessage: mediaWithUserData.errorMessage,
        selectedServer: selectedServer,
        availableServers: availableServers,
        favoriteCount: favoriteCount,
        inProgressCount: inProgressCount,
        onRefresh: mediaLibraryProvider.refreshMovies,
        onRetry: mediaLibraryProvider.loadInitialMovies,
        onMovieTap: (mediaItem) => _openMovie(context, mediaItem),
        onOpenLibraryCollection: (mediaType) =>
            _openLibraryCollection(context, mediaType),
        onServerSelected: appProvider.selectServer,
        onOpenMobileSample: () => _openMobileSample(context),
      ),
      _FileSourceTab(
        selectedServer: selectedServer,
        availableServers: availableServers,
        onServerSelected: appProvider.selectServer,
      ),
      _MyTab(
        favoriteItems: mediaWithUserData.allItems
            .where((item) => item.isFavorite)
            .toList(),
        favoriteCount: favoriteCount,
        inProgressCount: inProgressCount,
        recentWatchingCount: mediaWithUserData.recentWatching.length,
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

  void _openLibraryCollection(BuildContext context, MediaType mediaType) {
    context.push(MediaLibraryCollectionView.locationFor(mediaType));
  }
}

class _MediaLibraryTab extends StatelessWidget {
  const _MediaLibraryTab({
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
    required this.onOpenMobileSample,
  });

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
  final VoidCallback onOpenMobileSample;

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayoutBuilder(
      mobileBuilder: (context, maxWidth) {
        return MobileHomeScreen(
          maxWidth: maxWidth,
          movies: movies,
          series: series,
          recentWatching: recentWatching,
          isLoading: isLoading,
          errorMessage: errorMessage,
          selectedServer: selectedServer,
          availableServers: availableServers,
          favoriteCount: favoriteCount,
          inProgressCount: inProgressCount,
          onRefresh: onRefresh,
          onRetry: onRetry,
          onMovieTap: onMovieTap,
          onOpenLibraryCollection: onOpenLibraryCollection,
          onServerSelected: onServerSelected,
        );
      },
      tabletBuilder: (context, maxWidth) {
        return TabletHomeScreen(
          maxWidth: maxWidth,
          movies: movies,
          isLoading: isLoading,
          errorMessage: errorMessage,
          selectedServer: selectedServer,
          availableServers: availableServers,
          favoriteCount: favoriteCount,
          inProgressCount: inProgressCount,
          onRefresh: onRefresh,
          onRetry: onRetry,
          onMovieTap: onMovieTap,
          onServerSelected: onServerSelected,
          onOpenMobileSample: onOpenMobileSample,
        );
      },
    );
  }
}

class _FileSourceTab extends StatelessWidget {
  const _FileSourceTab({
    required this.selectedServer,
    required this.availableServers,
    required this.onServerSelected,
  });

  final MediaServerInfo selectedServer;
  final List<MediaServerInfo> availableServers;
  final ValueChanged<MediaServerInfo> onServerSelected;

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
            child: Text(
              '当前支持添加 Emby 服务器，配置项拆分为名称、协议、地址、端口、用户名和密码，方便后续单独复用或修改其中一个组件。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          for (final server in availableServers) ...[
            FileSourceTile(
              server: server,
              isSelected: server.id == selectedServer.id,
              onTap: () => onServerSelected(server),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Future<void> _openAddSourceSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardColor,
      builder: (_) {
        return AddFileSourceSheet(
          onSubmitted: (draft) {
            context.read<AppProvider>().addConfiguredServer(
              customName: draft.name,
              config: draft.config,
            );
          },
        );
      },
    );
  }
}

class _MyTab extends StatelessWidget {
  const _MyTab({
    required this.favoriteItems,
    required this.favoriteCount,
    required this.inProgressCount,
    required this.recentWatchingCount,
    required this.onMovieTap,
  });

  final List<MediaItem> favoriteItems;
  final int favoriteCount;
  final int inProgressCount;
  final int recentWatchingCount;
  final ValueChanged<MediaItem> onMovieTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
        physics: const BouncingScrollPhysics(),
        children: [
          Text('我的', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            '收藏、续播和个人常用内容入口。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MetricCard(label: '收藏', value: '$favoriteCount 部'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(label: '续播', value: '$inProgressCount 部'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MetricCard(
                  label: '最近观看',
                  value: '$recentWatchingCount 部',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (favoriteItems.isEmpty)
            const AppSurfaceCard(child: Text('还没有收藏内容，去媒体库挑几部喜欢的作品吧。'))
          else
            for (final mediaItem in favoriteItems) ...[
              _FavoriteListTile(
                mediaItem: mediaItem,
                onTap: () => onMovieTap(mediaItem),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _FavoriteListTile extends StatelessWidget {
  const _FavoriteListTile({required this.mediaItem, required this.onTap});

  final MediaItem mediaItem;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaItem.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mediaItem.overview.isEmpty ? '还没有简介' : mediaItem.overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
