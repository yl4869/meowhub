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
}

const Object _sentinel = Object();
