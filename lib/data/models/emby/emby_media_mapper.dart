import '../../../domain/entities/media_item.dart';
import '../../../domain/entities/watch_history_item.dart';
import 'emby_media_item_dto.dart';

/// Refactor reason:
/// Mapping stays in the data layer so DTOs own transport concerns, while
/// entities remain framework-agnostic and stable for provider/UI layers.
extension EmbyMediaItemDtoMapper on EmbyMediaItemDto {
  MediaItem toEntity({
    required String serverUrl,
    required WatchSourceType sourceType,
    String? accessToken,
    List<SubtitleInfo> subtitles = const [],
  }) {
    final playbackProgress = _buildPlaybackProgress(
      runTimeTicks: runTimeTicks,
      playbackPositionTicks: userData?.playbackPositionTicks,
    );
    return MediaItem(
      id: _stableNumericId(id),
      sourceId: id,
      title: name,
      originalTitle: originalTitle?.trim().isNotEmpty == true
          ? originalTitle!.trim()
          : name,
      type: MediaType.fromValue(type),
      sourceType: sourceType,
      posterUrl: _buildPrimaryImageUrl(serverUrl, id, imageTags?.primary),
      backdropUrl: _buildBackdropImageUrl(
        serverUrl,
        id,
        backdropImageTags.isEmpty ? null : backdropImageTags.first,
      ),
      rating: (communityRating ?? 0).toDouble(),
      year: productionYear ?? premiereDate?.year,
      overview: overview ?? '',
      playUrl: _buildPlaybackUrl(serverUrl, id, accessToken),
      playbackProgress: playbackProgress,
      parentTitle: seriesName,
      seriesId: seriesId,
      indexNumber: indexNumber,
      parentIndexNumber: parentIndexNumber,
      lastPlayedAt: userData?.lastPlayedDate,
      cast: people
          .where((person) => person.name.trim().isNotEmpty)
          .map(
            (person) => Cast(
              name: person.name,
              characterName: person.role?.trim().isNotEmpty == true
                  ? person.role!.trim()
                  : person.type?.trim().isNotEmpty == true
                  ? person.type!.trim()
                  : '演职员',
              avatarUrl: _buildPersonImageUrl(
                serverUrl,
                person.id,
                person.primaryImageTag,
              ),
            ),
          )
          .toList(growable: false),
      subtitles: subtitles,
    );
  }
}

MediaPlaybackProgress? _buildPlaybackProgress({
  required int? runTimeTicks,
  required int? playbackPositionTicks,
}) {
  final durationTicks = runTimeTicks ?? 0;
  if (durationTicks <= 0) {
    return null;
  }

  final positionTicks = playbackPositionTicks ?? 0;
  return MediaPlaybackProgress(
    position: Duration(milliseconds: positionTicks ~/ 10000),
    duration: Duration(milliseconds: durationTicks ~/ 10000),
  );
}

String? _buildPrimaryImageUrl(
  String serverUrl,
  String itemId,
  String? imageTag,
) {
  if (imageTag == null || imageTag.isEmpty) {
    return null;
  }

  return '$serverUrl/emby/Items/$itemId/Images/Primary?tag=$imageTag&maxHeight=720';
}

String? _buildBackdropImageUrl(
  String serverUrl,
  String itemId,
  String? imageTag,
) {
  if (imageTag == null || imageTag.isEmpty) {
    return null;
  }

  return '$serverUrl/emby/Items/$itemId/Images/Backdrop/0?tag=$imageTag&maxWidth=1280';
}

String? _buildPlaybackUrl(
  String serverUrl,
  String itemId,
  String? accessToken,
) {
  if (accessToken == null || accessToken.isEmpty) {
    return null;
  }

  return '$serverUrl/emby/Videos/$itemId/stream?Static=true&api_key=$accessToken';
}

String _buildPersonImageUrl(
  String serverUrl,
  String? personId,
  String? imageTag,
) {
  if (personId == null ||
      personId.isEmpty ||
      imageTag == null ||
      imageTag.isEmpty) {
    return '';
  }

  return '$serverUrl/emby/Items/$personId/Images/Primary?tag=$imageTag&maxHeight=300';
}

int _stableNumericId(String value) {
  var hash = 0x811C9DC5;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
