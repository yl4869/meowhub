import '../../domain/entities/watch_history_item.dart';

class PlaybackRecord {
  const PlaybackRecord({
    required this.id,
    required this.title,
    required this.poster,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.episodeIndex = 0,
  });

  final String id;
  final String title;
  final String poster;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;
  final int episodeIndex;

  PlaybackRecord copyWith({
    String? id,
    String? title,
    String? poster,
    Duration? position,
    Duration? duration,
    DateTime? updatedAt,
    int? episodeIndex,
  }) {
    return PlaybackRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      episodeIndex: episodeIndex ?? this.episodeIndex,
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
      sourceType: WatchSourceType.local,
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
      episodeIndex: episodeIndex,
    );
  }
}
