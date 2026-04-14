import 'emby_image_tags_dto.dart';

class EmbyMediaItemDto {
  const EmbyMediaItemDto({
    required this.id,
    required this.name,
    this.originalTitle,
    this.overview,
    this.type,
    this.runTimeTicks,
    this.productionYear,
    this.communityRating,
    this.premiereDate,
    this.imageTags,
    this.backdropImageTags = const [],
    this.people = const [],
    this.parentIndexNumber,
    this.indexNumber,
    this.seriesName,
  });

  final String id;
  final String name;
  final String? originalTitle;
  final String? overview;
  final String? type;
  final int? runTimeTicks;
  final int? productionYear;
  final num? communityRating;
  final DateTime? premiereDate;
  final EmbyImageTagsDto? imageTags;
  final List<String> backdropImageTags;
  final List<EmbyPersonDto> people;
  final int? parentIndexNumber;
  final int? indexNumber;
  final String? seriesName;

  factory EmbyMediaItemDto.fromJson(Map<String, dynamic> json) {
    final rawBackdropTags =
        json['BackdropImageTags'] as List<dynamic>? ?? const [];

    return EmbyMediaItemDto(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      originalTitle: json['OriginalTitle'] as String?,
      overview: json['Overview'] as String?,
      type: json['Type'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      communityRating: json['CommunityRating'] as num?,
      premiereDate: json['PremiereDate'] == null
          ? null
          : DateTime.tryParse(json['PremiereDate'].toString()),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      seriesName: json['SeriesName'] as String?,
      imageTags: json['ImageTags'] is Map<String, dynamic>
          ? EmbyImageTagsDto.fromJson(json['ImageTags'] as Map<String, dynamic>)
          : null,
      backdropImageTags: rawBackdropTags
          .map((tag) => tag.toString())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false),
      people: (json['People'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(EmbyPersonDto.fromJson)
          .toList(growable: false),
    );
  }
}

class EmbyPersonDto {
  const EmbyPersonDto({
    required this.name,
    this.role,
    this.type,
    this.primaryImageTag,
    this.id,
  });

  final String name;
  final String? role;
  final String? type;
  final String? primaryImageTag;
  final String? id;

  factory EmbyPersonDto.fromJson(Map<String, dynamic> json) {
    return EmbyPersonDto(
      name: json['Name'] as String? ?? '',
      role: json['Role'] as String?,
      type: json['Type'] as String?,
      primaryImageTag: json['PrimaryImageTag'] as String?,
      id: json['Id'] as String?,
    );
  }
}

class EmbyMediaItemListDto {
  const EmbyMediaItemListDto({
    this.items = const [],
    this.totalRecordCount = 0,
    this.startIndex = 0,
  });

  final List<EmbyMediaItemDto> items;
  final int totalRecordCount;
  final int startIndex;
}
