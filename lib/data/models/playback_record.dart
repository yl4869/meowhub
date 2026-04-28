import '../../domain/entities/watch_history_item.dart';

class PlaybackRecord {
  const PlaybackRecord({
    required this.id,
    required this.title,
    required this.poster,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.sourceType,
    this.episodeIndex = 0,
    this.originalTitle,
    this.overview,
    this.backdrop,
    this.parentTitle,
    this.year,
    this.seriesId,
    this.parentIndexNumber,
    this.indexNumber,
  });

  final String id;
  final String title;
  final String poster;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final WatchSourceType sourceType;
  final int episodeIndex;
  final String? originalTitle;
  final String? overview;
  final String? backdrop;
  final String? parentTitle;
  final int? year;
  final String? seriesId;
  final int? parentIndexNumber;
  final int? indexNumber;

  PlaybackRecord copyWith({
    String? id,
    String? title,
    String? poster,
    Duration? position,
    Duration? duration,
    DateTime? updatedAt,
    WatchSourceType? sourceType,
    int? episodeIndex,
    Object? originalTitle = _sentinel,
    Object? overview = _sentinel,
    Object? backdrop = _sentinel,
    Object? parentTitle = _sentinel,
    Object? year = _sentinel,
    Object? seriesId = _sentinel,
    Object? parentIndexNumber = _sentinel,
    Object? indexNumber = _sentinel,
  }) {
    return PlaybackRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceType: sourceType ?? this.sourceType,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      originalTitle: identical(originalTitle, _sentinel)
          ? this.originalTitle
          : originalTitle as String?,
      overview: identical(overview, _sentinel)
          ? this.overview
          : overview as String?,
      backdrop: identical(backdrop, _sentinel)
          ? this.backdrop
          : backdrop as String?,
      parentTitle: identical(parentTitle, _sentinel)
          ? this.parentTitle
          : parentTitle as String?,
      year: identical(year, _sentinel) ? this.year : year as int?,
      seriesId: identical(seriesId, _sentinel)
          ? this.seriesId
          : seriesId as String?,
      parentIndexNumber: identical(parentIndexNumber, _sentinel)
          ? this.parentIndexNumber
          : parentIndexNumber as int?,
      indexNumber: identical(indexNumber, _sentinel)
          ? this.indexNumber
          : indexNumber as int?,
    );
  }

  WatchHistoryItem toWatchHistoryItem() {
    return WatchHistoryItem(
      id: id,
      title: title,
      poster: poster,
      position: position,
      duration: duration,
      updatedAt: updatedAt,
      sourceType: sourceType,
      originalTitle: originalTitle,
      overview: overview,
      backdrop: backdrop,
      parentTitle: parentTitle,
      year: year,
      seriesId: seriesId,
      parentIndexNumber: parentIndexNumber,
      indexNumber: indexNumber,
    );
  }

  factory PlaybackRecord.fromWatchHistoryItem(
    WatchHistoryItem item, {
    int episodeIndex = 0,
  }) {
    return PlaybackRecord(
      id: item.id,
      title: item.title,
      poster: item.poster,
      position: item.position,
      duration: item.duration,
      updatedAt: item.updatedAt,
      sourceType: item.sourceType,
      episodeIndex: episodeIndex,
      originalTitle: item.originalTitle,
      overview: item.overview,
      backdrop: item.backdrop,
      parentTitle: item.parentTitle,
      year: item.year,
      seriesId: item.seriesId,
      parentIndexNumber: item.parentIndexNumber,
      indexNumber: item.indexNumber,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'poster': poster,
        'position_ms': position.inMilliseconds,
        'duration_ms': duration.inMilliseconds,
        'updated_at': updatedAt.toIso8601String(),
        'source_type': sourceType.name,
        if (episodeIndex != 0) 'episode_index': episodeIndex,
        if (originalTitle != null) 'original_title': originalTitle,
        if (overview != null) 'overview': overview,
        if (backdrop != null) 'backdrop': backdrop,
        if (parentTitle != null) 'parent_title': parentTitle,
        if (year != null) 'year': year,
        if (seriesId != null) 'series_id': seriesId,
        if (parentIndexNumber != null) 'parent_index_number': parentIndexNumber,
        if (indexNumber != null) 'index_number': indexNumber,
      };

  factory PlaybackRecord.fromJson(Map<String, dynamic> json) =>
      PlaybackRecord(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        poster: json['poster'] as String? ?? '',
        position: Duration(milliseconds: json['position_ms'] as int? ?? 0),
        duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime(2020),
        sourceType: WatchSourceType.values.firstWhere(
          (s) => s.name == json['source_type'],
          orElse: () => WatchSourceType.emby,
        ),
        episodeIndex: json['episode_index'] as int? ?? 0,
        originalTitle: json['original_title'] as String?,
        overview: json['overview'] as String?,
        backdrop: json['backdrop'] as String?,
        parentTitle: json['parent_title'] as String?,
        year: json['year'] as int?,
        seriesId: json['series_id'] as String?,
        parentIndexNumber: json['parent_index_number'] as int?,
        indexNumber: json['index_number'] as int?,
      );
}

const Object _sentinel = Object();
