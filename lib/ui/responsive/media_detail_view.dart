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
  String? _lastResumeLogSignature;

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
        final rawPlayableItems = mediaItem.playableItems.isEmpty
            ? [mediaItem]
            : mediaItem.playableItems;
        final userDataProvider = context.watch<UserDataProvider>();
        final isFavorite = userDataProvider.isFavorite(mediaItem.id);
        final playableItems = rawPlayableItems
            .map(
              (item) => item.copyWith(
                playbackProgress:
                    userDataProvider.playbackProgressForItem(item) ??
                    item.playbackProgress,
              ),
            )
            .toList(growable: false);
        final hasPlayableUrl = playableItems.any(
          (item) => item.playUrl?.isNotEmpty ?? false,
        );
        final resumePlayableItemId = userDataProvider.resumePlayableItemIdForItem(
          mediaItem,
        );
        final fallbackEpisodeIndex = userDataProvider.episodeIndexForItem(
          mediaItem,
        );
        final initialEpisodeIndex = _resolveInitialEpisodeIndex(
          mediaItem: mediaItem,
          playableItems: playableItems,
          resumePlayableItemId: resumePlayableItemId,
          fallbackEpisodeIndex: fallbackEpisodeIndex,
        );
        _logResumeState(
          mediaItem: mediaItem,
          playableItems: playableItems,
          initialEpisodeIndex: initialEpisodeIndex,
          resumePlayableItemId: resumePlayableItemId,
        );
        void handlePlayPressed(
          int episodeIndex, {
          bool openTrackSelector = false,
        }) {
          final targetIndex = episodeIndex.clamp(0, playableItems.length - 1);
          final selectedItem = playableItems[targetIndex];
          final latestProgress =
              userDataProvider.playbackProgressForItem(selectedItem) ??
              selectedItem.playbackProgress;
          final liveSelectedItem = selectedItem.copyWith(
            playbackProgress: latestProgress,
          );
          final progress = liveSelectedItem.playbackProgress;
          debugPrint(
            '[Resume][Detail][Play] media=${mediaItem.dataSourceId} '
            'selectedItem=${liveSelectedItem.dataSourceId} '
            'position=${progress?.position.inMilliseconds ?? 0}ms '
            'duration=${progress?.duration.inMilliseconds ?? 0}ms',
          );
          userDataProvider.markRecentlyWatchedItemMemoryOnly(
            liveSelectedItem,
            episodeIndex: targetIndex,
          );
          final path =
              PlayerView.locationFor(liveSelectedItem.id) +
              (openTrackSelector ? '?tracks=1' : '');
          context.push(path, extra: liveSelectedItem);
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
              initialEpisodeIndex: initialEpisodeIndex,
              playableItems: playableItems,
              onPlayPressed: resolvePlayPressed(),
              onOpenTrackSelector: (index) =>
                  handlePlayPressed(index, openTrackSelector: true),
              onToggleFavorite: handleToggleFavorite,
            );
          },
          tabletBuilder: (context, maxWidth) {
            return TabletMediaDetailScreen(
              maxWidth: maxWidth,
              mediaItem: mediaItem,
              selectedServer: selectedServer,
              isFavorite: isFavorite,
              initialEpisodeIndex: initialEpisodeIndex,
              playableItems: playableItems,
              onPlayPressed: resolvePlayPressed(),
              onOpenTrackSelector: (index) =>
                  handlePlayPressed(index, openTrackSelector: true),
              onToggleFavorite: handleToggleFavorite,
            );
          },
        );
      },
    );
  }

  void _logResumeState({
    required MediaItem mediaItem,
    required List<MediaItem> playableItems,
    required int initialEpisodeIndex,
    required String? resumePlayableItemId,
  }) {
    if (playableItems.isEmpty) {
      return;
    }

    final selectedIndex = initialEpisodeIndex.clamp(0, playableItems.length - 1);
    final selectedItem = playableItems[selectedIndex];
    final progress = selectedItem.playbackProgress;
    final signature =
        '${mediaItem.dataSourceId}|${selectedItem.dataSourceId}|'
        '${progress?.position.inMilliseconds ?? 0}|'
        '${progress?.duration.inMilliseconds ?? 0}|'
        '${resumePlayableItemId ?? ''}|$selectedIndex';
    if (_lastResumeLogSignature == signature) {
      return;
    }
    _lastResumeLogSignature = signature;
    debugPrint(
      '[Resume][Detail][Refresh] media=${mediaItem.dataSourceId} '
      'selectedItem=${selectedItem.dataSourceId} '
      'selectedIndex=$selectedIndex '
      'resumePlayable=${resumePlayableItemId ?? ''} '
      'position=${progress?.position.inMilliseconds ?? 0}ms '
      'duration=${progress?.duration.inMilliseconds ?? 0}ms',
    );
  }
}

int _resolveInitialEpisodeIndex({
  required MediaItem mediaItem,
  required List<MediaItem> playableItems,
  required String? resumePlayableItemId,
  required int fallbackEpisodeIndex,
}) {
  if (mediaItem.type == MediaType.movie || playableItems.isEmpty) {
    return 0;
  }

  if (resumePlayableItemId != null && resumePlayableItemId.isNotEmpty) {
    final matchedIndex = playableItems.indexWhere(
      (item) => item.dataSourceId == resumePlayableItemId,
    );
    if (matchedIndex >= 0) {
      return matchedIndex;
    }
  }

  if (fallbackEpisodeIndex >= 0 &&
      fallbackEpisodeIndex < playableItems.length) {
    return fallbackEpisodeIndex;
  }

  var latestIndex = -1;
  DateTime? latestPlayedAt;
  for (var index = 0; index < playableItems.length; index++) {
    final item = playableItems[index];
    final lastPlayedAt = item.lastPlayedAt;
    if (lastPlayedAt == null) {
      continue;
    }
    if (latestPlayedAt == null || lastPlayedAt.isAfter(latestPlayedAt)) {
      latestPlayedAt = lastPlayedAt;
      latestIndex = index;
    }
  }
  if (latestIndex >= 0) {
    return latestIndex;
  }

  for (var index = 0; index < playableItems.length; index++) {
    final progress = playableItems[index].playbackProgress;
    if (progress != null && progress.position > Duration.zero) {
      return index;
    }
  }

  return 0;
}
