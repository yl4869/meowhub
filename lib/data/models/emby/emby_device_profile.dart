import '../../../core/services/capability_prober.dart';

/// Emby `DeviceProfile` 的完整模型。
///
/// 这里将原本散落在 API Client 中的 Map 结构收敛为明确的 Dart 类型，
/// 方便按平台生成不同能力，并保持 `toJson()` 输出与 Emby 协议一致。
class EmbyDeviceProfile {
  const EmbyDeviceProfile({
    required this.name,
    required this.id,
    this.supportedMediaTypes = const ['Video', 'Audio'],
    required this.maxStreamingBitrate,
    required this.maxStaticBitrate,
    this.musicStreamingTranscodingBitrate,
    this.maxStaticMusicBitrate,
    this.directPlayProfiles = const [],
    this.directStreamProfiles = const [],
    this.transcodingProfiles = const [],
    this.responseProfiles = const [],
    this.containerProfiles = const [],
    this.codecProfiles = const [],
    this.subtitleProfiles = const [],
    this.supportedSubtitles = const [],
  });

  final String name;
  final String id;
  final List<String> supportedMediaTypes;
  final int maxStreamingBitrate;
  final int maxStaticBitrate;
  final int? musicStreamingTranscodingBitrate;
  final int? maxStaticMusicBitrate;
  final List<EmbyDirectPlayProfile> directPlayProfiles;
  final List<EmbyDirectPlayProfile> directStreamProfiles;
  final List<EmbyTranscodingProfile> transcodingProfiles;
  final List<EmbyResponseProfile> responseProfiles;
  final List<EmbyContainerProfile> containerProfiles;
  final List<EmbyCodecProfile> codecProfiles;
  final List<EmbySubtitleProfile> subtitleProfiles;
  final List<String> supportedSubtitles;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Name': name,
      'Id': id,
      'SupportedMediaTypes': _toCsv(supportedMediaTypes),
      'MaxStreamingBitrate': maxStreamingBitrate,
      'MaxStaticBitrate': maxStaticBitrate,
      if (musicStreamingTranscodingBitrate != null)
        'MusicStreamingTranscodingBitrate': musicStreamingTranscodingBitrate,
      if (maxStaticMusicBitrate != null)
        'MaxStaticMusicBitrate': maxStaticMusicBitrate,
      'DirectPlayProfiles': directPlayProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'DirectStreamProfiles': directStreamProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'TranscodingProfiles': transcodingProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'ResponseProfiles': responseProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'ContainerProfiles': containerProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'CodecProfiles': codecProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'SubtitleProfiles': subtitleProfiles
          .map((profile) => profile.toJson())
          .toList(growable: false),
      if (supportedSubtitles.isNotEmpty)
        'SupportedSubtitles': _toCsv(supportedSubtitles),
    };
  }
}

class EmbyDirectPlayProfile {
  const EmbyDirectPlayProfile({
    required this.type,
    this.container = const [],
    this.videoCodec = const [],
    this.audioCodec = const [],
    this.subtitleCodec = const [],
  });

  final String type;
  final List<String> container;
  final List<String> videoCodec;
  final List<String> audioCodec;
  final List<String> subtitleCodec;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Type': type,
      if (container.isNotEmpty) 'Container': _toCsv(container),
      if (videoCodec.isNotEmpty) 'VideoCodec': _toCsv(videoCodec),
      if (audioCodec.isNotEmpty) 'AudioCodec': _toCsv(audioCodec),
      if (subtitleCodec.isNotEmpty) 'SubtitleCodec': _toCsv(subtitleCodec),
    };
  }
}

class EmbyTranscodingProfile {
  const EmbyTranscodingProfile({
    required this.type,
    required this.container,
    required this.protocol,
    required this.context,
    this.videoCodec = const [],
    this.audioCodec = const [],
    this.transcodeSeekInfo,
    this.copyTimestamps,
    this.breakOnNonKeyFrames,
    this.minSegments,
    this.segmentLength,
    this.enableMpegtsM2TsMode,
    this.manifestSubtitles = const [],
  });

  final String type;
  final String container;
  final String protocol;
  final String context;
  final List<String> videoCodec;
  final List<String> audioCodec;
  final String? transcodeSeekInfo;
  final bool? copyTimestamps;
  final bool? breakOnNonKeyFrames;
  final int? minSegments;
  final int? segmentLength;
  final bool? enableMpegtsM2TsMode;
  final List<String> manifestSubtitles;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Type': type,
      'Container': container,
      'Protocol': protocol,
      'Context': context,
      if (videoCodec.isNotEmpty) 'VideoCodec': _toCsv(videoCodec),
      if (audioCodec.isNotEmpty) 'AudioCodec': _toCsv(audioCodec),
      if (transcodeSeekInfo != null) 'TranscodeSeekInfo': transcodeSeekInfo,
      if (copyTimestamps != null) 'CopyTimestamps': copyTimestamps,
      if (breakOnNonKeyFrames != null)
        'BreakOnNonKeyFrames': breakOnNonKeyFrames,
      if (minSegments != null) 'MinSegments': minSegments,
      if (segmentLength != null) 'SegmentLength': segmentLength,
      if (enableMpegtsM2TsMode != null)
        'EnableMpegtsM2TsMode': enableMpegtsM2TsMode,
      if (manifestSubtitles.isNotEmpty)
        'ManifestSubtitles': _toCsv(manifestSubtitles),
    };
  }
}

class EmbyResponseProfile {
  const EmbyResponseProfile({
    required this.type,
    required this.container,
    required this.mimeType,
  });

  final String type;
  final String container;
  final String mimeType;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Type': type,
      'Container': container,
      'MimeType': mimeType,
    };
  }
}

class EmbyContainerProfile {
  const EmbyContainerProfile({
    required this.type,
    required this.container,
    this.conditions = const [],
  });

  final String type;
  final List<String> container;
  final List<EmbyProfileCondition> conditions;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Type': type,
      'Container': _toCsv(container),
      if (conditions.isNotEmpty)
        'Conditions': conditions
            .map((condition) => condition.toJson())
            .toList(growable: false),
    };
  }
}

class EmbyCodecProfile {
  const EmbyCodecProfile({
    required this.type,
    required this.codec,
    this.conditions = const [],
  });

  final String type;
  final List<String> codec;
  final List<EmbyProfileCondition> conditions;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Type': type,
      'Codec': _toCsv(codec),
      if (conditions.isNotEmpty)
        'Conditions': conditions
            .map((condition) => condition.toJson())
            .toList(growable: false),
    };
  }
}

class EmbyProfileCondition {
  const EmbyProfileCondition({
    required this.condition,
    required this.property,
    required this.value,
    this.isRequired,
  });

  final String condition;
  final String property;
  final String value;
  final bool? isRequired;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Condition': condition,
      'Property': property,
      'Value': value,
      if (isRequired != null) 'IsRequired': isRequired,
    };
  }
}

class EmbySubtitleProfile {
  const EmbySubtitleProfile({required this.format, required this.method});

  final String format;
  final String method;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'Format': format, 'Method': method};
  }
}

class EmbyProfileFactory {
  const EmbyProfileFactory._();

  static EmbyDeviceProfile forCurrentPlatform({
    required String deviceId,
    required CapabilitySnapshot capabilities,
  }) {
    if (capabilities.isWeb) {
      return getWebProfile(deviceId: deviceId, capabilities: capabilities);
    }
    return getMediaKitProfile(deviceId: deviceId, capabilities: capabilities);
  }

  /// 原生端使用 media_kit/libmpv，能力声明可以更激进：
  /// HEVC/AV1/MKV/PGS 都尽量协商为直放或直串，避免服务端额外转码。
  static EmbyDeviceProfile getMediaKitProfile({
    required String deviceId,
    required CapabilitySnapshot capabilities,
  }) {
    const videoContainers = [
      'mp4',
      'm4v',
      'mov',
      'mkv',
      'webm',
      'ts',
      'm2ts',
      'mpegts',
      'mpeg',
      'mpg',
      'avi',
      'asf',
      'wmv',
      'flv',
      'ogv',
      '3gp',
    ];
    const videoCodecs = [
      'h264',
      'hevc',
      'av1',
      'vp8',
      'vp9',
      'mpeg1video',
      'mpeg2video',
      'mpeg4',
      'msmpeg4v3',
      'vc1',
      'wmv3',
      'mjpeg',
      'prores',
      'theora',
    ];
    const audioCodecs = [
      'aac',
      'alac',
      'ac3',
      'eac3',
      'dts',
      'flac',
      'mp2',
      'mp3',
      'opus',
      'pcm_alaw',
      'pcm_mulaw',
      'pcm_s16le',
      'pcm_s24le',
      'truehd',
      'vorbis',
      'wavpack',
      'wmav2',
    ];
    const audioContainers = [
      'aac',
      'm4a',
      'mp3',
      'flac',
      'ogg',
      'oga',
      'opus',
      'wav',
      'webma',
      'wma',
    ];
    const textSubtitles = ['srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt'];
    const imageSubtitles = ['pgs', 'pgssub', 'sup', 'dvdsub', 'sub', 'idx'];
    const subtitleCodecs = [...textSubtitles, ...imageSubtitles];

    return EmbyDeviceProfile(
      name: 'MeowHub media_kit',
      id: deviceId,
      maxStreamingBitrate: capabilities.maxStreamingBitrate,
      maxStaticBitrate: capabilities.maxStreamingBitrate,
      musicStreamingTranscodingBitrate: 384000,
      maxStaticMusicBitrate: capabilities.maxStreamingBitrate,
      directPlayProfiles: const [
        EmbyDirectPlayProfile(
          type: 'Video',
          container: videoContainers,
          videoCodec: videoCodecs,
          audioCodec: audioCodecs,
          subtitleCodec: subtitleCodecs,
        ),
        EmbyDirectPlayProfile(
          type: 'Audio',
          container: audioContainers,
          audioCodec: audioCodecs,
        ),
      ],
      directStreamProfiles: const [
        EmbyDirectPlayProfile(
          type: 'Video',
          container: videoContainers,
          videoCodec: videoCodecs,
          audioCodec: audioCodecs,
          subtitleCodec: subtitleCodecs,
        ),
        EmbyDirectPlayProfile(
          type: 'Audio',
          container: audioContainers,
          audioCodec: audioCodecs,
        ),
      ],
      transcodingProfiles: const [
        EmbyTranscodingProfile(
          type: 'Video',
          container: 'ts',
          protocol: 'hls',
          context: 'Streaming',
          videoCodec: ['h264', 'hevc', 'av1', 'vp9'],
          audioCodec: ['aac', 'ac3', 'eac3', 'mp3', 'opus', 'flac'],
          transcodeSeekInfo: 'Auto',
          copyTimestamps: true,
          breakOnNonKeyFrames: true,
          minSegments: 1,
          segmentLength: 3,
          enableMpegtsM2TsMode: false,
          manifestSubtitles: ['vtt'],
        ),
        EmbyTranscodingProfile(
          type: 'Video',
          container: 'ts',
          protocol: 'http',
          context: 'Streaming',
          videoCodec: ['h264', 'hevc', 'av1', 'vp9'],
          audioCodec: ['aac', 'ac3', 'eac3', 'mp3', 'opus', 'flac'],
          transcodeSeekInfo: 'Auto',
          copyTimestamps: true,
          breakOnNonKeyFrames: true,
          minSegments: 1,
          segmentLength: 3,
          enableMpegtsM2TsMode: false,
        ),
        EmbyTranscodingProfile(
          type: 'Video',
          container: 'mp4',
          protocol: 'http',
          context: 'Static',
          videoCodec: ['h264', 'hevc', 'av1'],
          audioCodec: ['aac', 'ac3', 'eac3', 'mp3', 'opus'],
          transcodeSeekInfo: 'Auto',
          copyTimestamps: true,
          breakOnNonKeyFrames: true,
          minSegments: 1,
          segmentLength: 3,
          enableMpegtsM2TsMode: false,
        ),
        EmbyTranscodingProfile(
          type: 'Audio',
          container: 'aac',
          protocol: 'http',
          context: 'Streaming',
          audioCodec: ['aac', 'mp3', 'opus', 'flac'],
        ),
      ],
      responseProfiles: const [
        EmbyResponseProfile(
          type: 'Video',
          container: 'ts',
          mimeType: 'video/mp2t',
        ),
        EmbyResponseProfile(
          type: 'Video',
          container: 'mp4',
          mimeType: 'video/mp4',
        ),
        EmbyResponseProfile(
          type: 'Audio',
          container: 'aac',
          mimeType: 'audio/aac',
        ),
      ],
      containerProfiles: const [
        EmbyContainerProfile(
          type: 'Video',
          container: ['matroska', 'webm'],
          conditions: [
            // 限制为单视频流，避免服务端把多角度/多画面封装误判为可安全直放。
            EmbyProfileCondition(
              condition: 'EqualsAny',
              property: 'NumVideoStreams',
              value: '1',
              isRequired: false,
            ),
          ],
        ),
      ],
      codecProfiles: [
        EmbyCodecProfile(
          type: 'Video',
          codec: const ['h264', 'hevc', 'av1', 'vp9'],
          conditions: _buildVideoConditions(
            capabilities: capabilities,
            maxBitDepth: 10,
          ),
        ),
        const EmbyCodecProfile(
          type: 'VideoAudio',
          codec: ['aac', 'ac3', 'eac3', 'dts', 'flac', 'mp3', 'opus', 'truehd'],
          conditions: [
            // 8 声道以内是大多数桌面/Android 输出链路更容易稳定直出的范围。
            EmbyProfileCondition(
              condition: 'LessThanEqual',
              property: 'AudioChannels',
              value: '8',
              isRequired: false,
            ),
          ],
        ),
      ],
      subtitleProfiles: [
        ..._buildSubtitleProfiles(textSubtitles, methods: const ['External']),
        ..._buildSubtitleProfiles(
          const ['pgs', 'pgssub', 'sup'],
          methods: const ['Embed', 'External'],
        ),
        ..._buildSubtitleProfiles(
          const ['dvdsub', 'sub', 'idx'],
          methods: const ['External'],
        ),
      ],
      supportedSubtitles: const [...textSubtitles, ...imageSubtitles],
    );
  }

  /// Web 端遵循浏览器最保守的组合，优先争取 H.264/AAC/MP4 的直放协商。
  static EmbyDeviceProfile getWebProfile({
    required String deviceId,
    required CapabilitySnapshot capabilities,
  }) {
    const textSubtitles = ['srt', 'subrip', 'vtt', 'webvtt'];
    const imageSubtitles = ['pgs', 'pgssub', 'sup', 'dvdsub', 'sub', 'idx'];

    return EmbyDeviceProfile(
      name: 'MeowHub Web',
      id: deviceId,
      maxStreamingBitrate: capabilities.maxStreamingBitrate,
      maxStaticBitrate: capabilities.maxStreamingBitrate,
      musicStreamingTranscodingBitrate: 256000,
      maxStaticMusicBitrate: capabilities.maxStreamingBitrate,
      directPlayProfiles: const [
        EmbyDirectPlayProfile(
          type: 'Video',
          container: ['mp4', 'm4v'],
          videoCodec: ['h264'],
          audioCodec: ['aac', 'mp3'],
          subtitleCodec: textSubtitles,
        ),
        EmbyDirectPlayProfile(
          type: 'Audio',
          container: ['aac', 'm4a', 'mp3'],
          audioCodec: ['aac', 'mp3'],
        ),
      ],
      directStreamProfiles: const [
        EmbyDirectPlayProfile(
          type: 'Video',
          container: ['mp4', 'm4v'],
          videoCodec: ['h264'],
          audioCodec: ['aac', 'mp3'],
          subtitleCodec: textSubtitles,
        ),
        EmbyDirectPlayProfile(
          type: 'Audio',
          container: ['aac', 'm4a', 'mp3'],
          audioCodec: ['aac', 'mp3'],
        ),
      ],
      transcodingProfiles: const [
        EmbyTranscodingProfile(
          type: 'Video',
          container: 'ts',
          protocol: 'hls',
          context: 'Streaming',
          videoCodec: ['h264'],
          audioCodec: ['aac'],
          transcodeSeekInfo: 'Auto',
          copyTimestamps: true,
          breakOnNonKeyFrames: true,
          minSegments: 1,
          segmentLength: 3,
          enableMpegtsM2TsMode: false,
          manifestSubtitles: ['vtt'],
        ),
        EmbyTranscodingProfile(
          type: 'Video',
          container: 'mp4',
          protocol: 'http',
          context: 'Static',
          videoCodec: ['h264'],
          audioCodec: ['aac'],
          transcodeSeekInfo: 'Auto',
          copyTimestamps: true,
          breakOnNonKeyFrames: true,
          minSegments: 1,
          segmentLength: 3,
          enableMpegtsM2TsMode: false,
        ),
        EmbyTranscodingProfile(
          type: 'Audio',
          container: 'aac',
          protocol: 'http',
          context: 'Streaming',
          audioCodec: ['aac', 'mp3'],
        ),
      ],
      responseProfiles: const [
        EmbyResponseProfile(
          type: 'Video',
          container: 'ts',
          mimeType: 'video/mp2t',
        ),
        EmbyResponseProfile(
          type: 'Video',
          container: 'mp4',
          mimeType: 'video/mp4',
        ),
        EmbyResponseProfile(
          type: 'Audio',
          container: 'aac',
          mimeType: 'audio/aac',
        ),
      ],
      codecProfiles: [
        EmbyCodecProfile(
          type: 'Video',
          codec: const ['h264'],
          conditions: _buildVideoConditions(
            capabilities: capabilities,
            maxBitDepth: 8,
          ),
        ),
        const EmbyCodecProfile(
          type: 'VideoAudio',
          codec: ['aac', 'mp3'],
          conditions: [
            // 6 声道以内更接近浏览器默认音频解码与输出的稳定范围。
            EmbyProfileCondition(
              condition: 'LessThanEqual',
              property: 'AudioChannels',
              value: '6',
              isRequired: false,
            ),
          ],
        ),
      ],
      subtitleProfiles: [
        ..._buildSubtitleProfiles(textSubtitles, methods: const ['External']),
        ..._buildSubtitleProfiles(imageSubtitles, methods: const ['Embed']),
      ],
      supportedSubtitles: const [...textSubtitles, ...imageSubtitles],
    );
  }

  static List<EmbySubtitleProfile> _buildSubtitleProfiles(
    List<String> formats, {
    required List<String> methods,
  }) {
    return methods
        .expand(
          (method) => formats.map(
            (format) => EmbySubtitleProfile(format: format, method: method),
          ),
        )
        .toList(growable: false);
  }

  static List<EmbyProfileCondition> _buildVideoConditions({
    required CapabilitySnapshot capabilities,
    required int maxBitDepth,
  }) {
    return [
      // 位深限制用于避免把超出当前播放器/浏览器稳定范围的 HDR 或高位深视频误协商为直放。
      EmbyProfileCondition(
        condition: 'LessThanEqual',
        property: 'VideoBitDepth',
        value: '$maxBitDepth',
        isRequired: false,
      ),
      // 运行时屏幕宽度被转成最大视频宽度，超过当前显示价值的分辨率就交给服务端降级。
      EmbyProfileCondition(
        condition: 'LessThanEqual',
        property: 'Width',
        value: '${capabilities.maxVideoWidth}',
        isRequired: true,
      ),
      // 运行时屏幕高度同理，保证 Emby 协商出的直放结果与当前设备的物理显示上限匹配。
      EmbyProfileCondition(
        condition: 'LessThanEqual',
        property: 'Height',
        value: '${capabilities.maxVideoHeight}',
        isRequired: true,
      ),
    ];
  }
}

String _toCsv(List<String> values) {
  return values.join(',');
}
