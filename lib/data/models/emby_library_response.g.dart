// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'emby_library_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EmbyLibraryResponse _$EmbyLibraryResponseFromJson(Map<String, dynamic> json) =>
    EmbyLibraryResponse(
      items:
          (json['Items'] as List<dynamic>?)
              ?.map((e) => EmbyLibraryItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalRecordCount: (json['TotalRecordCount'] as num?)?.toInt() ?? 0,
      startIndex: (json['StartIndex'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$EmbyLibraryResponseToJson(
  EmbyLibraryResponse instance,
) => <String, dynamic>{
  'Items': instance.items.map((e) => e.toJson()).toList(),
  'TotalRecordCount': instance.totalRecordCount,
  'StartIndex': instance.startIndex,
};

EmbyLibraryItem _$EmbyLibraryItemFromJson(Map<String, dynamic> json) =>
    EmbyLibraryItem(
      id: json['Id'] as String,
      name: json['Name'] as String,
      serverId: json['ServerId'] as String?,
      collectionType: json['CollectionType'] as String?,
      type: json['Type'] as String?,
      imageTags: json['ImageTags'] == null
          ? null
          : EmbyImageTags.fromJson(json['ImageTags'] as Map<String, dynamic>),
      childCount: (json['ChildCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$EmbyLibraryItemToJson(EmbyLibraryItem instance) =>
    <String, dynamic>{
      'Id': instance.id,
      'Name': instance.name,
      'ServerId': instance.serverId,
      'CollectionType': instance.collectionType,
      'Type': instance.type,
      'ImageTags': instance.imageTags,
      'ChildCount': instance.childCount,
    };

EmbyMovieListResponse _$EmbyMovieListResponseFromJson(
  Map<String, dynamic> json,
) => EmbyMovieListResponse(
  items:
      (json['Items'] as List<dynamic>?)
          ?.map((e) => EmbyMovieItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  totalRecordCount: (json['TotalRecordCount'] as num?)?.toInt() ?? 0,
  startIndex: (json['StartIndex'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$EmbyMovieListResponseToJson(
  EmbyMovieListResponse instance,
) => <String, dynamic>{
  'Items': instance.items.map((e) => e.toJson()).toList(),
  'TotalRecordCount': instance.totalRecordCount,
  'StartIndex': instance.startIndex,
};

EmbyMovieItem _$EmbyMovieItemFromJson(Map<String, dynamic> json) =>
    EmbyMovieItem(
      id: json['Id'] as String,
      name: json['Name'] as String,
      serverId: json['ServerId'] as String?,
      overview: json['Overview'] as String?,
      type: json['Type'] as String?,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      communityRating: json['CommunityRating'] as num?,
      officialRating: json['OfficialRating'] as String?,
      dateCreated: json['DateCreated'] == null
          ? null
          : DateTime.parse(json['DateCreated'] as String),
      premiereDate: json['PremiereDate'] == null
          ? null
          : DateTime.parse(json['PremiereDate'] as String),
      imageTags: json['ImageTags'] == null
          ? null
          : EmbyImageTags.fromJson(json['ImageTags'] as Map<String, dynamic>),
      backdropImageTags:
          (json['BackdropImageTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      primaryImageAspectRatio: json['PrimaryImageAspectRatio'] as num?,
    );

Map<String, dynamic> _$EmbyMovieItemToJson(EmbyMovieItem instance) =>
    <String, dynamic>{
      'Id': instance.id,
      'Name': instance.name,
      'ServerId': instance.serverId,
      'Overview': instance.overview,
      'Type': instance.type,
      'RunTimeTicks': instance.runTimeTicks,
      'ProductionYear': instance.productionYear,
      'CommunityRating': instance.communityRating,
      'OfficialRating': instance.officialRating,
      'DateCreated': instance.dateCreated?.toIso8601String(),
      'PremiereDate': instance.premiereDate?.toIso8601String(),
      'ImageTags': instance.imageTags?.toJson(),
      'BackdropImageTags': instance.backdropImageTags,
      'PrimaryImageAspectRatio': instance.primaryImageAspectRatio,
    };

EmbyImageTags _$EmbyImageTagsFromJson(Map<String, dynamic> json) =>
    EmbyImageTags(
      primary: json['Primary'] as String?,
      thumb: json['Thumb'] as String?,
      backdrop: json['Backdrop'] as String?,
      logo: json['Logo'] as String?,
    );

Map<String, dynamic> _$EmbyImageTagsToJson(EmbyImageTags instance) =>
    <String, dynamic>{
      'Primary': instance.primary,
      'Thumb': instance.thumb,
      'Backdrop': instance.backdrop,
      'Logo': instance.logo,
    };
