// lib/data/models/emby/emby_resume_item_dto.dart

class EmbyResumeItemDto {
  final String id;
  final String name;
  final String? originalTitle;
  final String? overview;
  final String? type;
  final String? posterUrl;
  final String? backdropUrl;
  final int playbackPositionTicks;
  final int runTimeTicks;
  final String? lastPlayedDate;
  final String? seriesId;
  final String? seriesName;
  final int? productionYear;
  final int? indexNumber;
  final int? parentIndexNumber;

  EmbyResumeItemDto({
    required this.id,
    required this.name,
    this.originalTitle,
    this.overview,
    this.type,
    this.posterUrl,
    this.backdropUrl,
    required this.playbackPositionTicks,
    required this.runTimeTicks,
    this.lastPlayedDate,
    this.seriesId,
    this.seriesName,
    this.productionYear,
    this.indexNumber,
    this.parentIndexNumber,
  });

  factory EmbyResumeItemDto.fromJson(
    Map<String, dynamic> json, {
    required String serverUrl,
  }) {
    final userData = json['UserData'] as Map<String, dynamic>?;

    return EmbyResumeItemDto(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      originalTitle: json['OriginalTitle']?.toString(),
      overview: json['Overview']?.toString(),
      type: json['Type']?.toString(),
      posterUrl: _buildPosterUrl(json, serverUrl),
      backdropUrl: _buildBackdropUrl(json, serverUrl),
      playbackPositionTicks: userData?['PlaybackPositionTicks']?.toInt() ?? 0,
      runTimeTicks: json['RunTimeTicks']?.toInt() ?? 0,
      lastPlayedDate: userData?['LastPlayedDate']?.toString(),
      seriesId: json['SeriesId']?.toString(),
      seriesName: json['SeriesName']?.toString(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
    );
  }
}

String? _buildPosterUrl(Map<String, dynamic> json, String serverUrl) {
  final itemId = json['Id']?.toString();
  if (itemId == null || itemId.isEmpty) {
    return null;
  }

  final imageTags = json['ImageTags'];
  final primaryTag = imageTags is Map ? imageTags['Primary']?.toString() : null;
  if (primaryTag != null && primaryTag.isNotEmpty) {
    return '$serverUrl/emby/Items/$itemId/Images/Primary?tag=$primaryTag&maxHeight=720';
  }

  final seriesPrimaryTag = json['SeriesPrimaryImageTag']?.toString();
  final seriesId = json['SeriesId']?.toString();
  if (seriesPrimaryTag != null &&
      seriesPrimaryTag.isNotEmpty &&
      seriesId != null &&
      seriesId.isNotEmpty) {
    return '$serverUrl/emby/Items/$seriesId/Images/Primary?tag=$seriesPrimaryTag&maxHeight=720';
  }

  return null;
}

String? _buildBackdropUrl(Map<String, dynamic> json, String serverUrl) {
  final itemId = json['Id']?.toString();
  if (itemId == null || itemId.isEmpty) {
    return null;
  }

  final rawTags = json['BackdropImageTags'] as List<dynamic>? ?? const [];
  final backdropTag = rawTags
      .map((tag) => tag.toString())
      .firstWhere((tag) => tag.isNotEmpty, orElse: () => '');
  if (backdropTag.isEmpty) {
    return null;
  }

  return '$serverUrl/emby/Items/$itemId/Images/Backdrop/0?tag=$backdropTag&maxWidth=1280';
}
