import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/repositories/i_media_repository.dart';
import '../../providers/app_provider.dart';
import '../../providers/user_data_provider.dart';
import '../mobile/detail/mobile_media_detail_screen.dart';
import '../tablet/detail/tablet_media_detail_screen.dart';
import 'player_view.dart';
import 'responsive_layout_builder.dart';

class MediaDetailView extends StatefulWidget {
  const MediaDetailView({super.key, required this.mediaItem});

  static const String routePath = '/media/:id';

  static String locationFor(int id) => '/media/$id';

  final MediaItem mediaItem;

  @override
  State<MediaDetailView> createState() => _MediaDetailViewState();
}

class _MediaDetailViewState extends State<MediaDetailView> {
  late Future<MediaItem> _mediaDetailFuture;

  @override
  void initState() {
    super.initState();
    _mediaDetailFuture = context.read<IMediaRepository>().getMediaDetail(
      widget.mediaItem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedServer = context.select<AppProvider, MediaServerInfo>(
      (provider) => provider.selectedServer,
    );
    return FutureBuilder<MediaItem>(
      future: _mediaDetailFuture,
      initialData: widget.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data ?? widget.mediaItem;
        final playableItems = mediaItem.playableItems.isEmpty
            ? [mediaItem]
            : mediaItem.playableItems;
        final hasPlayableUrl = playableItems.any(
          (item) => item.playUrl?.isNotEmpty ?? false,
        );
        final userDataProvider = context.read<UserDataProvider>();
        final isFavorite = context.select<UserDataProvider, bool>(
          (provider) => provider.isFavorite(mediaItem.id),
        );
        final playbackProgress = context
            .select<UserDataProvider, MediaPlaybackProgress?>(
              (provider) => provider.playbackProgressForItem(mediaItem),
            );
        final initialEpisodeIndex = context.select<UserDataProvider, int>(
          (provider) => provider.episodeIndexForItem(mediaItem),
        );
        final hasRecentWatchRecord = context.select<UserDataProvider, bool>(
          (provider) =>
              provider.recentPlaybackMediaKeys.contains(mediaItem.mediaKey),
        );

        void handlePlayPressed(int episodeIndex, {bool openTrackSelector = false}) {
          final targetIndex = episodeIndex.clamp(0, playableItems.length - 1);
          final selectedItem = playableItems[targetIndex];
          userDataProvider.markRecentlyWatchedItem(
            mediaItem,
            episodeIndex: targetIndex,
          );
          final path = PlayerView.locationFor(selectedItem.id) + (openTrackSelector ? '?tracks=1' : '');
          context.push(
            path,
            extra: selectedItem,
          );
        }

        void handleToggleFavorite() {
          userDataProvider.toggleFavorite(mediaItem);
        }

        ValueChanged<int>? resolvePlayPressed() {
          if (!hasPlayableUrl) {
            return null;
          }
          return handlePlayPressed;
        }

        return ResponsiveLayoutBuilder(
          mobileBuilder: (context, maxWidth) {
            return MobileMediaDetailScreen(
              mediaItem: mediaItem,
              selectedServer: selectedServer,
              isFavorite: isFavorite,
              hasRecentWatchRecord: hasRecentWatchRecord,
              initialEpisodeIndex: initialEpisodeIndex,
              playableItems: playableItems,
              playbackProgress: playbackProgress,
              onPlayPressed: resolvePlayPressed(),
              onOpenTrackSelector: (index) => handlePlayPressed(index, openTrackSelector: true),
              onToggleFavorite: handleToggleFavorite,
            );
          },
          tabletBuilder: (context, maxWidth) {
            return TabletMediaDetailScreen(
              maxWidth: maxWidth,
              mediaItem: mediaItem,
              selectedServer: selectedServer,
              isFavorite: isFavorite,
              hasRecentWatchRecord: hasRecentWatchRecord,
              initialEpisodeIndex: initialEpisodeIndex,
              playableItems: playableItems,
              playbackProgress: playbackProgress,
              onPlayPressed: resolvePlayPressed(),
              onOpenTrackSelector: (index) => handlePlayPressed(index, openTrackSelector: true),
              onToggleFavorite: handleToggleFavorite,
            );
          },
        );
      },
    );
  }
}
