class LocalMediaScanResult {
  const LocalMediaScanResult({
    this.newFiles = const [],
    this.changedFiles = const [],
    this.deletedPaths = const [],
    this.newSeries = const [],
    this.scanDuration = Duration.zero,
    this.totalScanned = 0,
    this.errors = const [],
  });

  final List<ScannedFileMetadata> newFiles;
  final List<ScannedFileMetadata> changedFiles;
  final List<String> deletedPaths;
  final List<SeriesMetadata> newSeries;
  final Duration scanDuration;
  final int totalScanned;
  final List<String> errors;

  List<ScannedFileMetadata> get newAndChanged => [...newFiles, ...changedFiles];
}

class ScannedFileMetadata {
  const ScannedFileMetadata({
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.mtime,
    required this.parentFolder,
    this.mediaType = 'movie',
    this.title,
    this.originalTitle,
    this.overview,
    this.year,
    this.rating,
    this.posterPath,
    this.backdropPath,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.nfoPath,
    this.durationMs = 0,
    this.width,
    this.height,
  });

  final String filePath;
  final String fileName;
  final int fileSize;
  final int mtime;
  final String parentFolder;
  final String mediaType;
  final String? title;
  final String? originalTitle;
  final String? overview;
  final int? year;
  final double? rating;
  final String? posterPath;
  final String? backdropPath;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? nfoPath;
  final int durationMs;
  final int? width;
  final int? height;
}

class SeriesMetadata {
  const SeriesMetadata({
    required this.id,
    required this.title,
    required this.folderPath,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.year,
    this.rating,
  });

  final String id;
  final String title;
  final String folderPath;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final int? year;
  final double? rating;
}
