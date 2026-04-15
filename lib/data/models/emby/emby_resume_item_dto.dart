class EmbyResumeItemDto {
  const EmbyResumeItemDto({
    required this.id,
    required this.name,
    this.primaryImageUrl,
    this.playbackPositionTicks = 0,
    this.runTimeTicks = 0,
    this.lastPlayedDate,
    this.seriesId,
    this.parentIndexNumber,
    this.indexNumber,
  });

  final String id;
  final String name;
  final String? primaryImageUrl;
  final int playbackPositionTicks;
  final int runTimeTicks;
  final String? lastPlayedDate; // ISO 8601 string from server
  final String? seriesId;
  final int? parentIndexNumber;
  final int? indexNumber;
}
