class EmbyImageTagsDto {
  const EmbyImageTagsDto({this.primary, this.thumb, this.backdrop, this.logo});

  final String? primary;
  final String? thumb;
  final String? backdrop;
  final String? logo;

  factory EmbyImageTagsDto.fromJson(Map<String, dynamic> json) {
    return EmbyImageTagsDto(
      primary: json['Primary'] as String?,
      thumb: json['Thumb'] as String?,
      backdrop: json['Backdrop'] as String?,
      logo: json['Logo'] as String?,
    );
  }
}
