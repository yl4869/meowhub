enum WatchSourceType {
  emby,
  local;

  factory WatchSourceType.fromJson(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'local' || 'file' || 'disk' || 'network' => WatchSourceType.local,
      _ => WatchSourceType.emby,
    };
  }

  String toJson() {
    return switch (this) {
      WatchSourceType.emby => 'emby',
      WatchSourceType.local => 'local',
    };
  }
}

class WatchHistoryItem {
  const WatchHistoryItem({
    required this.id,
    required this.title,
    required this.poster,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.sourceType,
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
  final String? seriesId;
  final int? parentIndexNumber;
  final int? indexNumber;

  String get uniqueKey => '${sourceType.name}:$id';

  double get progressFraction {
    if (duration <= Duration.zero) {
      return 0;
    }

    final rawValue = position.inMilliseconds / duration.inMilliseconds;
    return rawValue.clamp(0.0, 1.0).toDouble();
  }

  WatchHistoryItem copyWith({
    String? id,
    String? title,
    String? poster,
    Duration? position,
    Duration? duration,
    DateTime? updatedAt,
    WatchSourceType? sourceType,
    Object? seriesId = _sentinel,
    Object? parentIndexNumber = _sentinel,
    Object? indexNumber = _sentinel,
  }) {
    return WatchHistoryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceType: sourceType ?? this.sourceType,
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
}

const Object _sentinel = Object();
