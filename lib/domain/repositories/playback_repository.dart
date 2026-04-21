import '../entities/media_item.dart';
import '../entities/playback_plan.dart';

abstract class PlaybackRepository {
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    Duration startPosition = Duration.zero,
  });
}
