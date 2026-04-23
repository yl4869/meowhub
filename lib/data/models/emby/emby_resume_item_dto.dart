// lib/data/models/emby/emby_resume_item_dto.dart

class EmbyResumeItemDto {
  final String id;
  final String name;
  final String? primaryImageUrl;
  final int playbackPositionTicks;
  final int runTimeTicks;
  final String? lastPlayedDate;
  final String? seriesId;
  final String? seriesName;
  final int? indexNumber;
  final int? parentIndexNumber;

  EmbyResumeItemDto({
    required this.id,
    required this.name,
    this.primaryImageUrl,
    required this.playbackPositionTicks,
    required this.runTimeTicks,
    this.lastPlayedDate,
    this.seriesId,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
  });

  /// ✅ 就是漏了这个工厂构造函数！
  /// 它负责接收一个 Map（零件），并返回一个完整的 DTO 对象（成品）
  factory EmbyResumeItemDto.fromJson(Map<String, dynamic> json) {
    // Emby 的进度数据通常嵌套在 UserData 字段里
    final userData = json['UserData'] as Map<String, dynamic>?;

    return EmbyResumeItemDto(
      id: json['Id'] ?? '',
      name: json['Name'] ?? '',
      // 处理图片：Emby 可能返回 ImageTags 对象
      primaryImageUrl: json['ImageTags']?['Primary'],
      playbackPositionTicks: userData?['PlaybackPositionTicks']?.toInt() ?? 0,
      runTimeTicks: json['RunTimeTicks']?.toInt() ?? 0,
      lastPlayedDate: userData?['LastPlayedDate'],
      seriesId: json['SeriesId'],
      seriesName: json['SeriesName'],
      indexNumber: json['IndexNumber'],
      parentIndexNumber: json['ParentIndexNumber'],
    );
  }
}