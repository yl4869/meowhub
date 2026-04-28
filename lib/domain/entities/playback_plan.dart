// 1. 定义章节结构体
class VideoChapter {
  const VideoChapter({required this.title, required this.startTime});

  final String title;
  final Duration startTime;
}

// 2. 定义时间范围结构体
class DurationRange {
  const DurationRange({required this.start, required this.end});

  final Duration start;
  final Duration end;

  bool contains(Duration position) => position >= start && position <= end;
}

// 3. 更新 PlaybackStream：增加 bitrate 参数
class PlaybackStream {
  const PlaybackStream({
    required this.index,
    required this.title,
    this.language,
    this.codec,
    this.deliveryMethod,
    this.subtitleLocationType,
    this.supportsExternalStream = false,
    this.channels,
    this.bitrate, // 👈 关键点：添加这一行
    this.isDefault = false,
    this.isExternal = false,
    this.isTextSubtitleStream = false,
    this.deliveryUrl,
  });

  final int index;
  final String title;
  final String? language;
  final String? codec;
  final String? deliveryMethod;
  final String? subtitleLocationType;
  final bool supportsExternalStream;
  final int? channels;
  final int? bitrate; // 👈 关键点：定义变量
  final bool isDefault;
  final bool isExternal;
  final bool isTextSubtitleStream;
  final String? deliveryUrl;
}

class PlaybackVideoInfo {
  const PlaybackVideoInfo({
    this.width,
    this.height,
    this.sourceWidth,
    this.sourceHeight,
    this.bitrate,
    this.codec,
    this.isTranscoding = false,
  });

  final int? width;
  final int? height;
  final int? sourceWidth;
  final int? sourceHeight;
  final int? bitrate;
  final String? codec;
  final bool isTranscoding;
}

// 4. 更新 PlaybackPlan：增加 chapters 和 markers
class PlaybackPlan {
  const PlaybackPlan({
    required this.url,
    this.isTranscoding = false,
    this.playSessionId,
    this.mediaSourceId,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
    this.chapters = const [], // 👈 添加这一行
    this.markers = const {}, // 👈 添加这一行
    this.videoInfo,
  });

  final String url;
  final bool isTranscoding;
  final String? playSessionId;
  final String? mediaSourceId;
  final List<PlaybackStream> audioStreams;
  final List<PlaybackStream> subtitleStreams;
  final List<VideoChapter> chapters; // 👈 变量定义
  final Map<String, DurationRange> markers; // 👈 变量定义
  final PlaybackVideoInfo? videoInfo;
}
