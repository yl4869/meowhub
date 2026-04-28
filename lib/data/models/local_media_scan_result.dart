class LocalMediaScanResult {
  const LocalMediaScanResult({
    this.newFiles = const [],
    this.changedFiles = const [],
    this.deletedPaths = const [],
    this.newSeries = const [],
    this.scanDuration = Duration.zero,
    this.totalScanned = 0,
  });

  final List<ScannedFileMetadata> newFiles;
  final List<ScannedFileMetadata> changedFiles;
  final List<String> deletedPaths;
  final List<SeriesMetadata> newSeries;
  final Duration scanDuration;
  final int totalScanned;

  bool get hasChanges =>
      newFiles.isNotEmpty ||
      changedFiles.isNotEmpty ||
      deletedPaths.isNotEmpty ||
      newSeries.isNotEmpty;

  List<ScannedFileMetadata> get newAndChanged => [...newFiles, ...changedFiles];

  Map<String, dynamic> toJson() => {
        'newFiles': newFiles.map((f) => f.toJson()).toList(),
        'changedFiles': changedFiles.map((f) => f.toJson()).toList(),
        'deletedPaths': deletedPaths,
        'newSeries': newSeries.map((s) => s.toJson()).toList(),
        'scanDurationMs': scanDuration.inMilliseconds,
        'totalScanned': totalScanned,
      };

  factory LocalMediaScanResult.fromJson(Map<String, dynamic> json) {
    return LocalMediaScanResult(
      newFiles: (json['newFiles'] as List<dynamic>?)
              ?.map((e) =>
                  ScannedFileMetadata.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      changedFiles: (json['changedFiles'] as List<dynamic>?)
              ?.map((e) =>
                  ScannedFileMetadata.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      deletedPaths: (json['deletedPaths'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const [],
      newSeries: (json['newSeries'] as List<dynamic>?)
              ?.map(
                  (e) => SeriesMetadata.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      scanDuration: Duration(
        milliseconds: (json['scanDurationMs'] as int?) ?? 0,
      ),
      totalScanned: (json['totalScanned'] as int?) ?? 0,
    );
  }
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

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'fileName': fileName,
        'fileSize': fileSize,
        'mtime': mtime,
        'parentFolder': parentFolder,
        'mediaType': mediaType,
        if (title != null) 'title': title,
        if (originalTitle != null) 'originalTitle': originalTitle,
        if (overview != null) 'overview': overview,
        if (year != null) 'year': year,
        if (rating != null) 'rating': rating,
        if (posterPath != null) 'posterPath': posterPath,
        if (backdropPath != null) 'backdropPath': backdropPath,
        if (seriesId != null) 'seriesId': seriesId,
        if (seasonNumber != null) 'seasonNumber': seasonNumber,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        if (nfoPath != null) 'nfoPath': nfoPath,
        'durationMs': durationMs,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  factory ScannedFileMetadata.fromJson(Map<String, dynamic> json) {
    return ScannedFileMetadata(
      filePath: json['filePath'] as String,
      fileName: json['fileName'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      mtime: (json['mtime'] as num).toInt(),
      parentFolder: json['parentFolder'] as String,
      mediaType: json['mediaType'] as String? ?? 'movie',
      title: json['title'] as String?,
      originalTitle: json['originalTitle'] as String?,
      overview: json['overview'] as String?,
      year: json['year'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      seriesId: json['seriesId'] as String?,
      seasonNumber: json['seasonNumber'] as int?,
      episodeNumber: json['episodeNumber'] as int?,
      nfoPath: json['nfoPath'] as String?,
      durationMs: (json['durationMs'] as int?) ?? 0,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'folderPath': folderPath,
        if (originalTitle != null) 'originalTitle': originalTitle,
        if (overview != null) 'overview': overview,
        if (posterPath != null) 'posterPath': posterPath,
        if (backdropPath != null) 'backdropPath': backdropPath,
        if (year != null) 'year': year,
        if (rating != null) 'rating': rating,
      };

  factory SeriesMetadata.fromJson(Map<String, dynamic> json) {
    return SeriesMetadata(
      id: json['id'] as String,
      title: json['title'] as String,
      folderPath: json['folderPath'] as String,
      originalTitle: json['originalTitle'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['posterPath'] as String?,
      backdropPath: json['backdropPath'] as String?,
      year: json['year'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
    );
  }
}
