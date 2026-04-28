class SeasonInfo {
  const SeasonInfo({
    required this.id,
    required this.name,
    required this.seriesId,
    required this.indexNumber,
    this.posterUrl,
  });

  final String id;
  final String name;
  final String seriesId;
  final int indexNumber;
  final String? posterUrl;
}
