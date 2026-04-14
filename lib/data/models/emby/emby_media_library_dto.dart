class EmbyMediaLibraryDto {
  const EmbyMediaLibraryDto({
    required this.id,
    required this.name,
    this.collectionType,
    this.type,
    this.childCount,
  });

  final String id;
  final String name;
  final String? collectionType;
  final String? type;
  final int? childCount;

  factory EmbyMediaLibraryDto.fromJson(Map<String, dynamic> json) {
    return EmbyMediaLibraryDto(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      collectionType: json['CollectionType'] as String?,
      type: json['Type'] as String?,
      childCount: (json['ChildCount'] as num?)?.toInt(),
    );
  }
}

class EmbyMediaLibraryListDto {
  const EmbyMediaLibraryListDto({
    this.items = const [],
    this.totalRecordCount = 0,
    this.startIndex = 0,
  });

  final List<EmbyMediaLibraryDto> items;
  final int totalRecordCount;
  final int startIndex;
}
