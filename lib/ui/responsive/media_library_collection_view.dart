import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_library_info.dart';
import '../../providers/media_library_provider.dart';
import '../../providers/media_with_user_data_provider.dart';
import '../../theme/app_theme.dart';
import '../atoms/app_surface_card.dart';
import '../atoms/poster_card.dart';
import '../atoms/poster_card_skeleton.dart';
import 'media_detail_view.dart';

class MediaLibraryCollectionView extends StatelessWidget {
  const MediaLibraryCollectionView({
    super.key,
    required this.libraryInfo,
  });

  static const String routePath = '/library/:libraryId';

  static String locationFor(String libraryId) =>
      '/library/${Uri.encodeComponent(libraryId)}';

  final MediaLibraryInfo libraryInfo;

  @override
  Widget build(BuildContext context) {
    final mediaWithUserData = context.watch<MediaWithUserDataProvider>();
    final mediaLibraryProvider = context.read<MediaLibraryProvider>();
    final items =
        mediaWithUserData.libraryItems[libraryInfo.id] ?? const [];
    final isLoadingMore = mediaLibraryProvider.state.isLoadingMore;
    final continueWatchingMediaKeys = mediaWithUserData.continueWatching
        .map((item) => item.mediaKey)
        .toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(libraryInfo.name),
        backgroundColor: AppTheme.backgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final gridMetrics = _GridMetrics.fromWidth(constraints.maxWidth);

          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 300) {
                mediaLibraryProvider.fetchMoreItems(libraryInfo.id);
              }
              return false;
            },
            child: RefreshIndicator(
              color: AppTheme.accentColor,
              backgroundColor: AppTheme.cardColor,
              onRefresh: mediaLibraryProvider.refreshMedia,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: AppSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              libraryInfo.name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '共 ${items.length} 部内容，卡片布局会根据屏幕宽度自动调整。',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (mediaWithUserData.isLoading && items.isEmpty)
                    _CollectionLoadingSliver(metrics: gridMetrics)
                  else if (mediaWithUserData.errorMessage != null &&
                      items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _CollectionStateCard(
                        icon: Icons.error_outline_rounded,
                        message: mediaWithUserData.errorMessage!,
                        buttonLabel: '重新加载',
                        onPressed: mediaLibraryProvider.loadInitialMedia,
                      ),
                    )
                  else if (items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _CollectionStateCard(
                        icon: Icons.video_library_outlined,
                        message: '这个媒体库暂时还没有内容。',
                      ),
                    )
                  else ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                      sliver: SliverGrid.builder(
                        itemCount: items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridMetrics.crossAxisCount,
                          mainAxisSpacing: gridMetrics.spacing,
                          crossAxisSpacing: gridMetrics.spacing,
                          childAspectRatio: gridMetrics.childAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          final mediaItem = items[index];
                          return PosterCard(
                            mediaItem: mediaItem,
                            isFavorite: mediaItem.isFavorite,
                            isContinueWatching: continueWatchingMediaKeys
                                .contains(mediaItem.mediaKey),
                            progress:
                                mediaItem.playbackProgress?.fraction ?? 0,
                            onTap: () {
                              context.push(
                                MediaDetailView.locationFor(mediaItem.id),
                                extra: mediaItem,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollectionStateCard extends StatelessWidget {
  const _CollectionStateCard({
    required this.icon,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String message;
  final String? buttonLabel;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: AppSurfaceCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: Colors.white70),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (buttonLabel != null && onPressed != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () {
                      onPressed!.call();
                    },
                    child: Text(buttonLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CollectionLoadingSliver extends StatelessWidget {
  const _CollectionLoadingSliver({required this.metrics});

  final _GridMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      sliver: SliverGrid.builder(
        itemCount: metrics.crossAxisCount * 3,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: metrics.crossAxisCount,
          mainAxisSpacing: metrics.spacing,
          crossAxisSpacing: metrics.spacing,
          childAspectRatio: metrics.childAspectRatio,
        ),
        itemBuilder: (_, _) => const PosterCardSkeleton(),
      ),
    );
  }
}

class _GridMetrics {
  const _GridMetrics({
    required this.crossAxisCount,
    required this.spacing,
    required this.childAspectRatio,
  });

  final int crossAxisCount;
  final double spacing;
  final double childAspectRatio;

  factory _GridMetrics.fromWidth(double maxWidth) {
    const horizontalPadding = 32.0;
    final spacing = maxWidth >= 720 ? 18.0 : 12.0;
    final minCardWidth = maxWidth >= 720 ? 168.0 : 144.0;
    final availableWidth = math.max(0.0, maxWidth - horizontalPadding);
    final estimatedCount =
        ((availableWidth + spacing) / (minCardWidth + spacing)).floor();
    final crossAxisCount = estimatedCount.clamp(1, 6);

    return _GridMetrics(
      crossAxisCount: crossAxisCount,
      spacing: spacing,
      childAspectRatio: 2 / 3,
    );
  }
}
