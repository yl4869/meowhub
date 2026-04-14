class EmbyResumeItemDto {
  const EmbyResumeItemDto({
    required this.id,
    required this.name,
    this.primaryImageUrl,
    this.playbackPositionTicks = 0,
    this.runTimeTicks = 0,
    this.lastPlayedDate,
  });

  final String id;
  final String name;
  final String? primaryImageUrl;
  final int playbackPositionTicks;
  final int runTimeTicks;
  final String? lastPlayedDate; // ISO 8601 string from server
}
