import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/media_item.dart';
import '../../providers/app_provider.dart';
import '../../providers/user_data_provider.dart';
import '../mobile/detail/mobile_media_detail_screen.dart';
import '../tablet/detail/tablet_media_detail_screen.dart';
import 'player_view.dart';
import 'responsive_layout_builder.dart';

class MediaDetailView extends StatelessWidget {
  const MediaDetailView({super.key, required this.mediaItem});

  static const String routePath = '/media/:id';

  static String locationFor(int id) => '/media/$id';

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final hasPlayableUrl = mediaItem.playUrl?.isNotEmpty ?? false;
    final selectedServer = context.select<AppProvider, MediaServerInfo>(
      (provider) => provider.selectedServer,
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

    void handlePlayPressed(int episodeIndex) {
      userDataProvider.markRecentlyWatchedItem(
        mediaItem,
        episodeIndex: episodeIndex,
      );
      context.push(PlayerView.locationFor(mediaItem.id), extra: mediaItem);
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
          playbackProgress: playbackProgress,
          onPlayPressed: resolvePlayPressed(),
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
          playbackProgress: playbackProgress,
          onPlayPressed: resolvePlayPressed(),
          onToggleFavorite: handleToggleFavorite,
        );
      },
    );
  }
}
