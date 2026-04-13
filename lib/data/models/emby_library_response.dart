import 'package:json_annotation/json_annotation.dart';

part 'emby_library_response.g.dart';

@JsonSerializable(explicitToJson: true)
class EmbyLibraryResponse {
  const EmbyLibraryResponse({
    this.items = const [],
    this.totalRecordCount = 0,
    this.startIndex = 0,
  });

  @JsonKey(name: 'Items', defaultValue: <EmbyLibraryItem>[])
  final List<EmbyLibraryItem> items;

  @JsonKey(name: 'TotalRecordCount', defaultValue: 0)
  final int totalRecordCount;

  @JsonKey(name: 'StartIndex', defaultValue: 0)
  final int startIndex;

  factory EmbyLibraryResponse.fromJson(Map<String, dynamic> json) =>
      _$EmbyLibraryResponseFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyLibraryResponseToJson(this);
}

@JsonSerializable()
class EmbyLibraryItem {
  const EmbyLibraryItem({
    required this.id,
    required this.name,
    this.serverId,
    this.collectionType,
    this.type,
    this.imageTags,
    this.childCount,
  });

  @JsonKey(name: 'Id')
  final String id;

  @JsonKey(name: 'Name')
  final String name;

  @JsonKey(name: 'ServerId')
  final String? serverId;

  @JsonKey(name: 'CollectionType')
  final String? collectionType;

  @JsonKey(name: 'Type')
  final String? type;

  @JsonKey(name: 'ImageTags')
  final EmbyImageTags? imageTags;

  @JsonKey(name: 'ChildCount')
  final int? childCount;

  factory EmbyLibraryItem.fromJson(Map<String, dynamic> json) =>
      _$EmbyLibraryItemFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyLibraryItemToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbyMovieListResponse {
  const EmbyMovieListResponse({
    this.items = const [],
    this.totalRecordCount = 0,
    this.startIndex = 0,
  });

  @JsonKey(name: 'Items', defaultValue: <EmbyMovieItem>[])
  final List<EmbyMovieItem> items;

  @JsonKey(name: 'TotalRecordCount', defaultValue: 0)
  final int totalRecordCount;

  @JsonKey(name: 'StartIndex', defaultValue: 0)
  final int startIndex;

  factory EmbyMovieListResponse.fromJson(Map<String, dynamic> json) =>
      _$EmbyMovieListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyMovieListResponseToJson(this);
}

@JsonSerializable(explicitToJson: true)
class EmbyMovieItem {
  const EmbyMovieItem({
    required this.id,
    required this.name,
    this.serverId,
    this.overview,
    this.type,
    this.runTimeTicks,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.dateCreated,
    this.premiereDate,
    this.imageTags,
    this.backdropImageTags = const [],
    this.primaryImageAspectRatio,
  });

  @JsonKey(name: 'Id')
  final String id;

  @JsonKey(name: 'Name')
  final String name;

  @JsonKey(name: 'ServerId')
  final String? serverId;

  @JsonKey(name: 'Overview')
  final String? overview;

  @JsonKey(name: 'Type')
  final String? type;

  @JsonKey(name: 'RunTimeTicks')
  final int? runTimeTicks;

  @JsonKey(name: 'ProductionYear')
  final int? productionYear;

  @JsonKey(name: 'CommunityRating')
  final num? communityRating;

  @JsonKey(name: 'OfficialRating')
  final String? officialRating;

  @JsonKey(name: 'DateCreated')
  final DateTime? dateCreated;

  @JsonKey(name: 'PremiereDate')
  final DateTime? premiereDate;

  @JsonKey(name: 'ImageTags')
  final EmbyImageTags? imageTags;

  @JsonKey(name: 'BackdropImageTags', defaultValue: <String>[])
  final List<String> backdropImageTags;

  @JsonKey(name: 'PrimaryImageAspectRatio')
  final num? primaryImageAspectRatio;

  factory EmbyMovieItem.fromJson(Map<String, dynamic> json) =>
      _$EmbyMovieItemFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyMovieItemToJson(this);
}

@JsonSerializable()
class EmbyImageTags {
  const EmbyImageTags({
    this.primary,
    this.thumb,
    this.backdrop,
    this.logo,
  });

  @JsonKey(name: 'Primary')
  final String? primary;

  @JsonKey(name: 'Thumb')
  final String? thumb;

  @JsonKey(name: 'Backdrop')
  final String? backdrop;

  @JsonKey(name: 'Logo')
  final String? logo;

  factory EmbyImageTags.fromJson(Map<String, dynamic> json) =>
      _$EmbyImageTagsFromJson(json);

  Map<String, dynamic> toJson() => _$EmbyImageTagsToJson(this);
}
