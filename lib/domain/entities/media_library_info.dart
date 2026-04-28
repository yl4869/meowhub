/// 媒体库/文件夹信息，跨后端通用
class MediaLibraryInfo {
  const MediaLibraryInfo({
    required this.id,
    required this.name,
    required this.collectionType,
    this.imageUrl,
  });

  final String id;
  final String name;

  /// 集合类型：movies, tvshows, music, photos, homevideos, books, mixed 等
  final String collectionType;

  final String? imageUrl;

  /// 是否为影视类集合
  bool get isVideoCollection =>
      collectionType == 'movies' ||
      collectionType == 'tvshows' ||
      collectionType == 'mixed';

  /// 是否为音乐类集合
  bool get isMusicCollection => collectionType == 'music';

  /// 是否为照片类集合
  bool get isPhotoCollection => collectionType == 'photos';
}
