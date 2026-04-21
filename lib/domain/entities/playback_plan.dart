class PlaybackPlan {
  const PlaybackPlan({
    required this.url,
    this.isTranscoding = false,
    this.playSessionId,
    this.mediaSourceId,
    this.audioStreams = const [],
    this.subtitleStreams = const [],
  });

  final String url; // absolute url to open
  final bool isTranscoding;
  final String? playSessionId;
  final String? mediaSourceId;
  final List<PlaybackStream> audioStreams;
  final List<PlaybackStream> subtitleStreams;
}

class PlaybackStream {
  const PlaybackStream({
    required this.index,
    required this.title,
    this.language,
    this.codec,
    this.channels,
    this.isDefault = false,
    this.isExternal = false,
    this.isTextSubtitleStream = false,
    this.deliveryUrl,
  });

  final int index;
  final String title;
  final String? language;
  final String? codec;
  final int? channels;
  final bool isDefault;
  // subtitle-only metadata (safe defaults for audio streams)
  final bool isExternal;
  final bool isTextSubtitleStream;
  final String? deliveryUrl; // absolute & authorized when available
}
