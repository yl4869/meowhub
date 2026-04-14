class EmbyPlaybackInfoDto {
  const EmbyPlaybackInfoDto({this.mediaSources = const [], this.playSessionId});

  final List<EmbyMediaSourceDto> mediaSources;
  final String? playSessionId;

  factory EmbyPlaybackInfoDto.fromJson(Map<String, dynamic> json) {
    final sources = (json['MediaSources'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaSourceDto.fromJson)
        .toList(growable: false);
    return EmbyPlaybackInfoDto(
      mediaSources: sources,
      playSessionId: json['PlaySessionId'] as String?,
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
  });

  final String id;
  final String? protocol;
  final String? container;
  final bool supportsDirectPlay;
  final bool supportsTranscoding;
  final String? transcodingUrl; // relative path
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final List<EmbyMediaStreamDto> mediaStreams;

  factory EmbyMediaSourceDto.fromJson(Map<String, dynamic> json) {
    final streams = (json['MediaStreams'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaStreamDto.fromJson)
        .toList(growable: false);
    return EmbyMediaSourceDto(
      id: json['Id']?.toString() ?? '',
      protocol: json['Protocol'] as String?,
      container: json['Container'] as String?,
      supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
      supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
      transcodingUrl: json['TranscodingUrl'] as String?,
      defaultAudioStreamIndex: (json['DefaultAudioStreamIndex'] as num?)
          ?.toInt(),
      defaultSubtitleStreamIndex: (json['DefaultSubtitleStreamIndex'] as num?)
          ?.toInt(),
      mediaStreams: streams,
    );
  }
}

class EmbyMediaStreamDto {
  const EmbyMediaStreamDto({
    required this.index,
    required this.type,
    this.language,
    this.displayTitle,
    this.codec,
    this.channels,
    this.isDefault = false,
    this.isExternal = false,
    this.deliveryUrl,
    this.isTextSubtitleStream = false,
  });

  final int index;
  final String type; // Audio / Video / Subtitle
  final String? language;
  final String? displayTitle;
  final String? codec;
  final int? channels;
  final bool isDefault;
  final bool isExternal;
  final String? deliveryUrl;
  final bool isTextSubtitleStream;

  factory EmbyMediaStreamDto.fromJson(Map<String, dynamic> json) {
    return EmbyMediaStreamDto(
      index: (json['Index'] as num?)?.toInt() ?? 0,
      type: json['Type']?.toString() ?? '',
      language: json['Language'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      codec: json['Codec'] as String?,
      channels: (json['Channels'] as num?)?.toInt(),
      isDefault: json['IsDefault'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
      deliveryUrl: json['DeliveryUrl'] as String?,
      isTextSubtitleStream: json['IsTextSubtitleStream'] as bool? ?? false,
    );
  }
}
