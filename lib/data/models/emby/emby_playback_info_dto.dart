int? _asInt(Object? value) {
  return switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}

double? _asDouble(Object? value) {
  return switch (value) {
    final double number => number,
    final num number => number.toDouble(),
    final String text => double.tryParse(text),
    _ => null,
  };
}

bool _asBool(Object? value, {bool fallback = false}) {
  return switch (value) {
    final bool flag => flag,
    final String text when text.toLowerCase() == 'true' => true,
    final String text when text.toLowerCase() == 'false' => false,
    _ => fallback,
  };
}

Map<String, String> _asStringMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  return value.map(
    (key, item) => MapEntry(key.toString(), item?.toString() ?? ''),
  );
}

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
    this.path,
    this.type,
    this.protocol,
    this.container,
    this.size,
    this.name,
    this.isRemote = false,
    this.hasMixedProtocols = false,
    this.runTimeTicks,
    this.supportsTranscoding = false,
    this.supportsDirectStream = false,
    this.supportsDirectPlay = false,
    this.isInfiniteStream = false,
    this.requiresOpening = false,
    this.requiresClosing = false,
    this.requiresLooping = false,
    this.supportsProbing = false,
    this.mediaStreams = const [],
    this.chapters,
    this.markers,
    this.formats = const [],
    this.bitrate,
    this.requiredHttpHeaders = const {},
    this.directStreamUrl,
    this.addApiKeyToDirectStreamUrl = false,
    this.transcodingUrl,
    this.transcodingSubProtocol,
    this.transcodingContainer,
    this.readAtNativeFramerate = false,
    this.defaultAudioStreamIndex,
    this.defaultSubtitleStreamIndex,
    this.itemId,
  });

  final String id;
  final String? path;
  final String? type;
  final String? protocol;
  final String? container;
  final int? size;
  final String? name;
  final bool isRemote;
  final bool hasMixedProtocols;
  final int? runTimeTicks;
  final bool supportsTranscoding;
  final bool supportsDirectStream;
  final bool supportsDirectPlay;
  final bool isInfiniteStream;
  final bool requiresOpening;
  final bool requiresClosing;
  final bool requiresLooping;
  final bool supportsProbing;
  final List<EmbyMediaStreamDto> mediaStreams;
  final List<EmbyChapterDto>? chapters;
  final List<EmbyMarkerDto>? markers;
  final List<String> formats;
  final int? bitrate;
  final Map<String, String> requiredHttpHeaders;
  final String? directStreamUrl;
  final bool addApiKeyToDirectStreamUrl;
  final String? transcodingUrl;
  final String? transcodingSubProtocol;
  final String? transcodingContainer;
  final bool readAtNativeFramerate;
  final int? defaultAudioStreamIndex;
  final int? defaultSubtitleStreamIndex;
  final String? itemId;

  factory EmbyMediaSourceDto.fromJson(Map<String, dynamic> json) {
    final streams = (json['MediaStreams'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EmbyMediaStreamDto.fromJson)
        .toList(growable: false);

    final chaptersJson = json['Chapters'] as List<dynamic>?;
    final chapters = chaptersJson
        ?.whereType<Map<String, dynamic>>()
        .map(EmbyChapterDto.fromJson)
        .toList(growable: false);

    final markersJson = json['Markers'] as List<dynamic>?;
    final markers = markersJson
        ?.whereType<Map<String, dynamic>>()
        .map(EmbyMarkerDto.fromJson)
        .toList(growable: false);

    final formats = (json['Formats'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);

    return EmbyMediaSourceDto(
      id: json['Id']?.toString() ?? '',
      path: json['Path'] as String?,
      type: json['Type'] as String?,
      protocol: json['Protocol'] as String?,
      container: json['Container'] as String?,
      size: _asInt(json['Size']),
      name: json['Name'] as String?,
      isRemote: _asBool(json['IsRemote']),
      hasMixedProtocols: _asBool(json['HasMixedProtocols']),
      runTimeTicks: _asInt(json['RunTimeTicks']),
      supportsTranscoding: _asBool(json['SupportsTranscoding']),
      supportsDirectStream: _asBool(json['SupportsDirectStream']),
      supportsDirectPlay: _asBool(json['SupportsDirectPlay']),
      isInfiniteStream: _asBool(json['IsInfiniteStream']),
      requiresOpening: _asBool(json['RequiresOpening']),
      requiresClosing: _asBool(json['RequiresClosing']),
      requiresLooping: _asBool(json['RequiresLooping']),
      supportsProbing: _asBool(json['SupportsProbing']),
      mediaStreams: streams,
      chapters: chapters,
      markers: markers,
      formats: formats,
      bitrate: _asInt(json['Bitrate']),
      requiredHttpHeaders: _asStringMap(json['RequiredHttpHeaders']),
      directStreamUrl: json['DirectStreamUrl'] as String?,
      addApiKeyToDirectStreamUrl: _asBool(json['AddApiKeyToDirectStreamUrl']),
      transcodingUrl: json['TranscodingUrl'] as String?,
      transcodingSubProtocol: json['TranscodingSubProtocol'] as String?,
      transcodingContainer: json['TranscodingContainer'] as String?,
      readAtNativeFramerate: _asBool(json['ReadAtNativeFramerate']),
      defaultAudioStreamIndex: _asInt(json['DefaultAudioStreamIndex']),
      defaultSubtitleStreamIndex: _asInt(json['DefaultSubtitleStreamIndex']),
      itemId: json['ItemId']?.toString(),
    );
  }
}

class EmbyMediaStreamDto {
  const EmbyMediaStreamDto({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.displayLanguage,
    this.title,
    this.displayTitle,
    this.timeBase,
    this.videoRange,
    this.nalLengthSize,
    this.isInterlaced = false,
    this.bitrate,
    this.bitDepth,
    this.refFrames,
    this.isDefault = false,
    this.isForced = false,
    this.isHearingImpaired = false,
    this.height,
    this.width,
    this.averageFrameRate,
    this.realFrameRate,
    this.profile,
    this.aspectRatio,
    this.isExternal = false,
    this.isTextSubtitleStream = false,
    this.supportsExternalStream = false,
    this.protocol,
    this.pixelFormat,
    this.level,
    this.isAnamorphic = false,
    this.extendedVideoType,
    this.extendedVideoSubType,
    this.extendedVideoSubTypeDescription,
    this.attachmentSize,
    this.channelLayout,
    this.channels,
    this.sampleRate,
    this.deliveryUrl,
    this.deliveryMethod,
    this.path,
    this.subtitleLocationType,
  });

  final int index;
  final String type;
  final String? codec;
  final String? language;
  final String? displayLanguage;
  final String? title;
  final String? displayTitle;
  final String? timeBase;
  final String? videoRange;
  final String? nalLengthSize;
  final bool isInterlaced;
  final int? bitrate;
  final int? bitDepth;
  final int? refFrames;
  final bool isDefault;
  final bool isForced;
  final bool isHearingImpaired;
  final int? height;
  final int? width;
  final double? averageFrameRate;
  final double? realFrameRate;
  final String? profile;
  final String? aspectRatio;
  final bool isExternal;
  final bool isTextSubtitleStream;
  final bool supportsExternalStream;
  final String? protocol;
  final String? pixelFormat;
  final int? level;
  final bool isAnamorphic;
  final String? extendedVideoType;
  final String? extendedVideoSubType;
  final String? extendedVideoSubTypeDescription;
  final int? attachmentSize;
  final String? channelLayout;
  final int? channels;
  final int? sampleRate;
  final String? deliveryUrl;
  final String? deliveryMethod;
  final String? path;
  final String? subtitleLocationType;

  factory EmbyMediaStreamDto.fromJson(Map<String, dynamic> json) {
    return EmbyMediaStreamDto(
      index: _asInt(json['Index']) ?? 0,
      type: json['Type']?.toString() ?? '',
      codec: json['Codec'] as String?,
      language: json['Language'] as String?,
      displayLanguage: json['DisplayLanguage'] as String?,
      title: json['Title'] as String?,
      displayTitle: json['DisplayTitle'] as String?,
      timeBase: json['TimeBase'] as String?,
      videoRange: json['VideoRange'] as String?,
      nalLengthSize: json['NalLengthSize']?.toString(),
      isInterlaced: _asBool(json['IsInterlaced']),
      bitrate: _asInt(json['BitRate'] ?? json['Bitrate']),
      bitDepth: _asInt(json['BitDepth']),
      refFrames: _asInt(json['RefFrames']),
      isDefault: _asBool(json['IsDefault']),
      isForced: _asBool(json['IsForced']),
      isHearingImpaired: _asBool(json['IsHearingImpaired']),
      height: _asInt(json['Height']),
      width: _asInt(json['Width']),
      averageFrameRate: _asDouble(json['AverageFrameRate']),
      realFrameRate: _asDouble(json['RealFrameRate']),
      profile: json['Profile'] as String?,
      aspectRatio: json['AspectRatio'] as String?,
      isExternal: _asBool(json['IsExternal']),
      isTextSubtitleStream: _asBool(json['IsTextSubtitleStream']),
      supportsExternalStream: _asBool(json['SupportsExternalStream']),
      protocol: json['Protocol'] as String?,
      pixelFormat: json['PixelFormat'] as String?,
      level: _asInt(json['Level']),
      isAnamorphic: _asBool(json['IsAnamorphic']),
      extendedVideoType: json['ExtendedVideoType'] as String?,
      extendedVideoSubType: json['ExtendedVideoSubType'] as String?,
      extendedVideoSubTypeDescription:
          json['ExtendedVideoSubTypeDescription'] as String?,
      attachmentSize: _asInt(json['AttachmentSize']),
      channelLayout: json['ChannelLayout'] as String?,
      channels: _asInt(json['Channels']),
      sampleRate: _asInt(json['SampleRate']),
      deliveryUrl: json['DeliveryUrl'] as String?,
      deliveryMethod: json['DeliveryMethod'] as String?,
      path: json['Path'] as String?,
      subtitleLocationType: json['SubtitleLocationType'] as String?,
    );
  }
}

class EmbyChapterDto {
  const EmbyChapterDto({
    this.name,
    required this.startTicks,
    this.markerType,
    this.chapterIndex,
  });

  final String? name;
  final int startTicks;
  final String? markerType;
  final int? chapterIndex;

  factory EmbyChapterDto.fromJson(Map<String, dynamic> json) {
    return EmbyChapterDto(
      name: json['Name'] as String?,
      startTicks: _asInt(json['StartPositionTicks']) ?? 0,
      markerType: json['MarkerType'] as String?,
      chapterIndex: _asInt(json['ChapterIndex']),
    );
  }
}

class EmbyMarkerDto {
  const EmbyMarkerDto({
    this.type,
    required this.startTicks,
    required this.endTicks,
  });

  final String? type;
  final int startTicks;
  final int endTicks;

  factory EmbyMarkerDto.fromJson(Map<String, dynamic> json) {
    return EmbyMarkerDto(
      type: json['MarkerType'] as String?,
      startTicks: _asInt(json['StartPositionTicks']) ?? 0,
      endTicks: _asInt(json['EndPositionTicks']) ?? 0,
    );
  }
}
