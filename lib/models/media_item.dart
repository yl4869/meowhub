import 'cast.dart';

enum MediaType {
  movie,
  series;

  factory MediaType.fromJson(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();

    switch (normalized) {
      case 'movie':
      case 'film':
        return MediaType.movie;
      case 'series':
      case 'tv':
      case 'tv_series':
      case 'tvseries':
      case 'show':
        return MediaType.series;
      default:
        return MediaType.movie;
    }
  }

  String toJson() {
    return switch (this) {
      MediaType.movie => 'movie',
      MediaType.series => 'series',
    };
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.type,
    this.cast = const [],
    this.posterUrl,
    this.backdropUrl,
    this.rating = 0,
    this.year,
    this.overview = '',
    this.isFavorite = false,
    this.playUrl,
  });

  final int id;
  final String title;
  final String originalTitle;
  final MediaType type;
  final List<Cast> cast;
  final String? posterUrl;
  final String? backdropUrl;
  final double rating;
  final int? year;
  final String overview;
  final bool isFavorite;
  final String? playUrl;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final title = _readString(json, keys: const ['title', 'name']);
    final originalTitle = _readString(
      json,
      keys: const [
        'originalTitle',
        'original_title',
        'originalName',
        'original_name',
      ],
    );

    return MediaItem(
      id: _readInt(json, keys: const ['id']) ?? 0,
      title: title ?? '',
      originalTitle: originalTitle ?? title ?? '',
      type: MediaType.fromJson(
        _readValue(json, keys: const ['type', 'mediaType', 'media_type']),
      ),
      cast: _readCastList(json),
      posterUrl: _readString(
        json,
        keys: const ['posterUrl', 'poster_url', 'posterPath', 'poster_path'],
      ),
      backdropUrl: _readString(
        json,
        keys: const [
          'backdropUrl',
          'backdrop_url',
          'backdropPath',
          'backdrop_path',
        ],
      ),
      rating:
          _readDouble(
            json,
            keys: const ['rating', 'voteAverage', 'vote_average'],
          ) ??
          0,
      year: _readYear(
        json,
        keys: const [
          'year',
          'releaseDate',
          'release_date',
          'firstAirDate',
          'first_air_date',
        ],
      ),
      overview: _readString(json, keys: const ['overview']) ?? '',
      isFavorite:
          _readBool(json, keys: const ['isFavorite', 'is_favorite']) ?? false,
      playUrl: _readString(json, keys: const ['playUrl', 'play_url']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'originalTitle': originalTitle,
      'type': type.toJson(),
      'cast': cast.map((member) => member.toJson()).toList(growable: false),
      'posterUrl': posterUrl,
      'backdropUrl': backdropUrl,
      'rating': rating,
      'year': year,
      'overview': overview,
      'isFavorite': isFavorite,
      'playUrl': playUrl,
    };
  }

  MediaItem copyWith({
    int? id,
    String? title,
    String? originalTitle,
    MediaType? type,
    List<Cast>? cast,
    String? posterUrl,
    String? backdropUrl,
    double? rating,
    int? year,
    String? overview,
    bool? isFavorite,
    String? playUrl,
  }) {
    return MediaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      originalTitle: originalTitle ?? this.originalTitle,
      type: type ?? this.type,
      cast: cast ?? this.cast,
      posterUrl: posterUrl ?? this.posterUrl,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      rating: rating ?? this.rating,
      year: year ?? this.year,
      overview: overview ?? this.overview,
      isFavorite: isFavorite ?? this.isFavorite,
      playUrl: playUrl ?? this.playUrl,
    );
  }

  static dynamic _readValue(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        return json[key];
      }
    }
    return null;
  }

  static String? _readString(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    final value = _readValue(json, keys: keys);
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _readInt(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    final value = _readValue(json, keys: keys);
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _readDouble(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    final value = _readValue(json, keys: keys);
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static bool? _readBool(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    final value = _readValue(json, keys: keys);
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
    return null;
  }

  static int? _readYear(
    Map<String, dynamic> json, {
    required List<String> keys,
  }) {
    final value = _readValue(json, keys: keys);
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is DateTime) {
      return value.year;
    }

    final text = value.toString();
    if (text.length >= 4) {
      return int.tryParse(text.substring(0, 4));
    }
    return int.tryParse(text);
  }

  static List<Cast> _readCastList(Map<String, dynamic> json) {
    final value = _readValue(json, keys: const ['cast', 'credits']);
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map<String, dynamic>>()
        .map(Cast.fromJson)
        .toList(growable: false);
  }
}
