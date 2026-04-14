class TrackSelectionRequest {
  const TrackSelectionRequest({
    this.audioIndex,
    this.subtitleIndex,
    required this.subtitleIsText,
    this.deliveryUrl,
  });

  final int? audioIndex;
  final int? subtitleIndex; // -1 or null means off
  final bool subtitleIsText; // true => local render; false => server-burn
  final String? deliveryUrl; // for external text subs
}

