class EmbyPlaybackInfoDto {
  const EmbyPlaybackInfoDto({
    this.mediaSources = const [],
    this.playSessionId,
    this.transcodingUrl,
  });

  final List<EmbyMediaSourceDto> mediaSources;
  final String? playSessionId;
  final String? transcodingUrl;

  factory EmbyPlaybackInfoDto.fromJson(Map<String, dynamic> json) {
    final sources = (json['MediaSources'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaSourceDto.fromJson)
        .toList(growable: false);
    return EmbyPlaybackInfoDto(
      mediaSources: sources,
      playSessionId: json['PlaySessionId'] as String?,
      transcodingUrl: json['TranscodingUrl'] as String?,
    );
  }
}

class EmbyMediaSourceDto {
  const EmbyMediaSourceDto({
    required this.id,
    this.protocol,
    this.container,
    this.supportsDirectPlay = false,
    this.supportsTranscoding = false,
    this.transcodingUrl,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.mediaStreams = const [],
    this.chapters, // 🚀 新增字段
    this.markers,  // 🚀 新增字段
  });

  final String id;
  final String? protocol;
  final String? container;
  final bool supportsDirectPlay;
  final bool supportsTranscoding;
  final String? transcodingUrl;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final List<EmbyMediaStreamDto> mediaStreams;
  final List<EmbyChapterDto>? chapters; // 章节
  final List<EmbyMarkerDto>? markers;   // 标记 (Intro/Outro)

  factory EmbyMediaSourceDto.fromJson(Map<String, dynamic> json) {
    final streams = (json['MediaStreams'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaStreamDto.fromJson)
        .toList(growable: false);

    // 解析章节
    final chaptersJson = json['Chapters'] as List<dynamic>?;
    final chapters = chaptersJson?.whereType<Map<String, dynamic>>()
        .map(EmbyChapterDto.fromJson).toList();

    // 解析标记
    final markersJson = json['Markers'] as List<dynamic>?;
    final markers = markersJson?.whereType<Map<String, dynamic>>()
        .map(EmbyMarkerDto.fromJson).toList();

    return EmbyMediaSourceDto(
      id: json['Id']?.toString() ?? '',
      protocol: json['Protocol'] as String?,
      container: json['Container'] as String?,
      supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
      supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
      transcodingUrl: json['TranscodingUrl'] as String?,
      defaultAudioStreamIndex: (json['DefaultAudioStreamIndex'] as num?)?.toInt(),
      defaultSubtitleStreamIndex: (json['DefaultSubtitleStreamIndex'] as num?)?.toInt(),
      mediaStreams: streams,
      chapters: chapters,
      markers: markers,
    );
  }
}

class EmbyMediaStreamDto {
  const EmbyMediaStreamDto({
    required this.index,
    required this.type,
    this.language,
    this.displayLanguage,
    this.title,
    this.displayTitle,
    this.codec,
    this.channels,
    this.bitrate, // 🚀 关键：新增码率字段
    this.isDefault = false,
    this.isExternal = false,
    this.deliveryUrl,
    this.isTextSubtitleStream = false,
  });

  final int index;
  final String type;
  final String? language;
  final String? displayLanguage;
  final String? title;
  final String? displayTitle;
  final String? codec;
  final int? channels;
  final int? bitrate; // 码率 (bps)
  final bool isDefault;
  final bool isExternal;
  final String? deliveryUrl;
  final bool isTextSubtitleStream;

  factory EmbyMediaStreamDto.fromJson(Map<String, dynamic> json) {
    return EmbyMediaStreamDto(
      index: (json['Index'] as num?)?.toInt() ?? 0,
      type: json['Type']?.toString() ?? '',
      language: json['Language'] as String?,
      displayLanguage: json['DisplayLanguage'] as String?,
      title: json['Title'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      codec: json['Codec'] as String?,
      channels: (json['Channels'] as num?)?.toInt(),
      bitrate: (json['Bitrate'] as num?)?.toInt(), // 映射 Emby 的 "Bitrate" 键
      isDefault: json['IsDefault'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
      deliveryUrl: json['DeliveryUrl'] as String?,
      isTextSubtitleStream: json['IsTextSubtitleStream'] as bool? ?? false,
    );
  }
}
// 🚀 新增：章节 DTO
class EmbyChapterDto {
  const EmbyChapterDto({this.name, required this.startTicks});
  final String? name;
  final int startTicks;

  factory EmbyChapterDto.fromJson(Map<String, dynamic> json) {
    return EmbyChapterDto(
      name: json['Name'] as String?,
      startTicks: (json['StartPositionTicks'] as num?)?.toInt() ?? 0,
    );
  }
}

// 🚀 新增：标记 DTO (用于 Intro/Outro)
class EmbyMarkerDto {
  const EmbyMarkerDto({this.type, required this.startTicks, required this.endTicks});
  final String? type;
  final int startTicks;
  final int endTicks;

  factory EmbyMarkerDto.fromJson(Map<String, dynamic> json) {
    return EmbyMarkerDto(
      type: json['MarkerType'] as String?,
      startTicks: (json['StartPositionTicks'] as num?)?.toInt() ?? 0,
      endTicks: (json['EndPositionTicks'] as num?)?.toInt() ?? 0,
    );
  }
}
