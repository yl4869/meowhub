import '../entities/media_item.dart';
import '../entities/playback_plan.dart';

/// Domain-level contract for building a playback plan.
///
/// This interface intentionally exposes only business entities and method
/// signatures. Concrete Emby/Jellyfin/local implementations belong in the
/// data layer.
abstract class PlaybackRepository {
  Future<PlaybackPlan> getPlaybackPlan(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
  });
}
