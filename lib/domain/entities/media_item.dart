import 'watch_history_item.dart';

enum MediaType {
  movie,
  series;

  factory MediaType.fromValue(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'series' ||
      'episode' ||
      'tv' ||
      'tv_series' ||
      'tvseries' ||
      'show' => MediaType.series,
      _ => MediaType.movie,
    };
  }

  String toValue() => name;
}

class MediaPlaybackProgress {
  const MediaPlaybackProgress({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration <= Duration.zero) {
      return 0;
    }

    final progress = position.inMilliseconds / duration.inMilliseconds;
    return progress.clamp(0.0, 1.0).toDouble();
  }
}

class Cast {
  const Cast({
    required this.name,
    required this.characterName,
    required this.avatarUrl,
  });

  final String name;
  final String characterName;
  final String avatarUrl;
}

/// Refactor reason:
/// `MediaItem` is now a pure domain entity. It keeps only business fields and
/// derived values, without any JSON parsing or datasource logic.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.type,
    this.cast = const [],
    required this.sourceType,
    this.sourceId,
    this.posterUrl,
    this.backdropUrl,
    this.rating = 0,
    this.year,
    this.overview = '',
    this.isFavorite = false,
    this.playUrl,
    this.playbackProgress,
    this.playableItems = const [],
    this.parentTitle,
    this.seriesId,
    this.indexNumber,
    this.parentIndexNumber,
    this.lastPlayedAt,
    this.subtitles = const [],
  });

  final int id;
  final String title;
  final String originalTitle;
  final MediaType type;
  final List<Cast> cast;
  final WatchSourceType sourceType;
  final String? sourceId;
  final String? posterUrl;
  final String? backdropUrl;
  final double rating;
  final int? year;
  final String overview;
  final bool isFavorite;
  final String? playUrl;
  final MediaPlaybackProgress? playbackProgress;
  final List<MediaItem> playableItems;
  final String? parentTitle;
  final String? seriesId;
  final int? indexNumber;
  final int? parentIndexNumber;
  final DateTime? lastPlayedAt;
  final List<SubtitleInfo> subtitles;

  String get dataSourceId => sourceId ?? id.toString();

  String get mediaKey => '${sourceType.name}:$dataSourceId';

  String get playbackLabel {
    if (type == MediaType.movie) {
      return '正片';
    }

    final season = parentIndexNumber;
    final episode = indexNumber;
    if (season != null && episode != null) {
      return 'S$season E$episode';
    }
    if (episode != null) {
      return '第 $episode 集';
    }
    return title;
  }

  MediaItem copyWith({
    int? id,
    String? title,
    String? originalTitle,
    MediaType? type,
    List<Cast>? cast,
    WatchSourceType? sourceType,
    Object? sourceId = _sentinel,
    Object? posterUrl = _sentinel,
    Object? backdropUrl = _sentinel,
    double? rating,
    Object? year = _sentinel,
    String? overview,
    bool? isFavorite,
    Object? playUrl = _sentinel,
    Object? playbackProgress = _sentinel,
    List<MediaItem>? playableItems,
    Object? parentTitle = _sentinel,
    Object? seriesId = _sentinel,
    Object? indexNumber = _sentinel,
    Object? parentIndexNumber = _sentinel,
    Object? lastPlayedAt = _sentinel,
    List<SubtitleInfo>? subtitles,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      type: type ?? this.type,
      cast: cast ?? this.cast,
      sourceType: sourceType ?? this.sourceType,
      sourceId: identical(sourceId, _sentinel)
          ? this.sourceId
          : sourceId as String?,
      posterUrl: identical(posterUrl, _sentinel)
          ? this.posterUrl
          : posterUrl as String?,
      backdropUrl: identical(backdropUrl, _sentinel)
          ? this.backdropUrl
          : backdropUrl as String?,
      rating: rating ?? this.rating,
      year: identical(year, _sentinel) ? this.year : year as int?,
      overview: overview ?? this.overview,
      isFavorite: isFavorite ?? this.isFavorite,
      playUrl: identical(playUrl, _sentinel)
          ? this.playUrl
          : playUrl as String?,
      playbackProgress: identical(playbackProgress, _sentinel)
          ? this.playbackProgress
          : playbackProgress as MediaPlaybackProgress?,
      playableItems: playableItems ?? this.playableItems,
      parentTitle: identical(parentTitle, _sentinel)
          ? this.parentTitle
          : parentTitle as String?,
      seriesId: identical(seriesId, _sentinel)
          ? this.seriesId
          : seriesId as String?,
      indexNumber: identical(indexNumber, _sentinel)
          ? this.indexNumber
          : indexNumber as int?,
      parentIndexNumber: identical(parentIndexNumber, _sentinel)
          ? this.parentIndexNumber
          : parentIndexNumber as int?,
      lastPlayedAt: identical(lastPlayedAt, _sentinel)
          ? this.lastPlayedAt
          : lastPlayedAt as DateTime?,
      subtitles: subtitles ?? this.subtitles,
    );
  }
}

const Object _sentinel = Object();

class SubtitleInfo {
  const SubtitleInfo({
    required this.mediaSourceId,
    required this.streamIndex,
    required this.title,
    this.language,
    this.codec,
    this.isExternal = false,
    this.isDefault = false,
  });

  final String mediaSourceId;
  final int streamIndex;
  final String title;
  final String? language;
  final String? codec;
  final bool isExternal;
  final bool isDefault;
}
