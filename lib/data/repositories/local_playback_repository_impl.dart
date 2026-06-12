import 'package:flutter/foundation.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/entities/playback_plan.dart';
import '../../domain/repositories/playback_repository.dart';

class LocalPlaybackRepositoryImpl implements PlaybackRepository {
  const LocalPlaybackRepositoryImpl();

  @override
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    bool preferTranscoding = false,
  }) async {
    final url = item.playUrl ?? 'file://${item.sourceId ?? ''}';
    debugPrint('[LocalMedia][Playback] getPlaybackPlan: url=$url, sourceId=${item.sourceId}, playUrl=${item.playUrl}');
    return PlaybackPlan(
      url: url,
      isTranscoding: false,
      playSessionId: null,
      mediaSourceId: item.sourceId,
      audioStreams: const [],
      subtitleStreams: const [],
      chapters: const [],
      markers: const {},
      videoInfo: null,
    );
  }
}
