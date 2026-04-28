import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/media_item.dart';
import '../../../providers/media_library_provider.dart';
import '../../../providers/user_data_provider.dart';
import '../../../theme/app_theme.dart';
import '../../atoms/app_surface_card.dart';
import '../../atoms/info_chip.dart';
import '../../atoms/poster_card.dart';
import '../../atoms/poster_card_skeleton.dart';
import '../../atoms/section_header.dart';

class MobileUiSampleView extends StatelessWidget {
  const MobileUiSampleView({super.key});

  static const String routePath = '/samples/mobile';

  @override
  Widget build(BuildContext context) {
    final mediaLibraryState = context
        .select<MediaLibraryProvider, MediaLibraryState>(
          (provider) => provider.state,
        );
    final mediaLibraryProvider = context.read<MediaLibraryProvider>();
    final allItems = mediaLibraryState.libraryItems.values
        .expand((items) => items)
        .toList();
    final featured = allItems.length > 1
        ? allItems[1]
        : (allItems.isNotEmpty ? allItems.first : null);
    final continueWatching = allItems.take(3).toList();
    final recommendations = allItems.length > 3
        ? allItems.skip(3).take(6).toList()
        : allItems;
    final isInitialLoading =
        mediaLibraryState.isLoading && allItems.isEmpty;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF121212), AppTheme.backgroundColor],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '手机端 UI 样例',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '由 MediaLibraryProvider 驱动的推荐、续播和双列海报瀑布',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (mediaLibraryState.errorMessage != null &&
                      allItems.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: AppSurfaceCard(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.cloud_off_rounded,
                                  size: 48,
                                  color: Colors.white54,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  mediaLibraryState.errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: () {
                                    mediaLibraryProvider.loadInitialMedia();
                                  },
                                  child: const Text('重新加载'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        child: _SampleHeroCard(
                          featured: featured,
                          isLoading: isInitialLoading,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                        child: const SectionHeader(
                          title: '继续播放',
                          subtitle: '更偏单手操作的横向卡片信息密度',
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 166,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            if (isInitialLoading) {
                              return const SizedBox(
                                width: 280,
                                child: PosterCardSkeleton(),
                              );
                            }

                            final mediaItem = continueWatching[index];
                            final progress = context
                                .select<UserDataProvider, double>(
                                  (provider) => provider.progressFractionFor(
                                    mediaItem.id,
                                  ),
                                );
                            return _ContinueWatchingCard(
                              mediaItem: mediaItem,
                              progress: progress,
                            );
                          },
                          separatorBuilder: (_, _) => const SizedBox(width: 14),
                          itemCount: isInitialLoading
                              ? 3
                              : continueWatching.length,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                        child: const SectionHeader(
                          title: '热门推荐',
                          subtitle: '这组海报卡就是手机首页栅格的基准样式',
                        ),
                      ),
                    ),
                    if (isInitialLoading)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                        sliver: SliverGrid.builder(
                          itemCount: 6,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.66,
                              ),
                          itemBuilder: (context, index) =>
                              const PosterCardSkeleton(),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                        sliver: SliverGrid.builder(
                          itemCount: recommendations.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.66,
                              ),
                          itemBuilder: (context, index) {
                            final mediaItem = recommendations[index];
                            final isFavorite = context
                                .select<UserDataProvider, bool>(
                                  (provider) =>
                                      provider.isFavorite(mediaItem.id),
                                );
                            final progress = context
                                .select<UserDataProvider, double>(
                                  (provider) => provider.progressFractionFor(
                                    mediaItem.id,
                                  ),
                                );

                            return PosterCard(
                              mediaItem: mediaItem,
                              isFavorite: isFavorite,
                              progress: progress,
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SampleHeroCard extends StatelessWidget {
  const _SampleHeroCard({required this.featured, required this.isLoading});

  final MediaItem? featured;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      borderRadius: const BorderRadius.all(Radius.circular(32)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: AspectRatio(
          aspectRatio: 0.92,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (featured?.backdropUrl case final backdropUrl?
                  when backdropUrl.isNotEmpty)
                CachedNetworkImage(imageUrl: backdropUrl, fit: BoxFit.cover)
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A1A14), Color(0xFF141414)],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        InfoChip(
                          icon: Icons.phone_android_rounded,
                          label: 'Mobile First',
                          color: AppTheme.accentColor,
                        ),
                        InfoChip(
                          icon: Icons.view_quilt_rounded,
                          label: '2-Column Grid',
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      isLoading ? '正在准备样例内容' : featured?.title ?? '手机首页推荐位',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLoading
                          ? '用一张大卡承载主推荐，把搜索、追更、续播信息压缩进可滑动内容区。'
                          : featured?.overview ?? '这里是移动端推荐位。',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {},
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('立即播放'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () {},
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            child: const Text('加入片单'),
                          ),
                        ),
                      ],
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

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.mediaItem,
    required this.progress,
  });

  final MediaItem mediaItem;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final normalized = progress.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: 280,
      child: AppSurfaceCard(
        child: Row(
          children: [
            SizedBox(
              width: 84,
              child: PosterCard(mediaItem: mediaItem, progress: normalized),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mediaItem.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mediaItem.overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  LinearProgressIndicator(
                    minHeight: 6,
                    value: normalized > 0 ? normalized : 0.05,
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
