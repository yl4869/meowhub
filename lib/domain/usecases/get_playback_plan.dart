import '../entities/media_item.dart';
import '../entities/playback_plan.dart';
import '../repositories/playback_repository.dart';

class GetPlaybackPlanUseCase {
  const GetPlaybackPlanUseCase(this._repo);
  final PlaybackRepository _repo;

  Future<PlaybackPlan> call(
    MediaItem item, {
    int? maxStreamingBitrate,
    bool? requireAvc,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    String? playSessionId,
    bool preferTranscoding = false,
  }) => _repo.getPlaybackPlan(
    item,
    maxStreamingBitrate: maxStreamingBitrate,
    requireAvc: requireAvc,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex,
    playSessionId: playSessionId,
    preferTranscoding: preferTranscoding,
  );
}
