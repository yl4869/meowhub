import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/utils/id_generator.dart';

class LocalFileResolver {
  LocalFileResolver();

  Directory? _cacheDir;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${appDir.path}/local_media_cache');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String? posterUrl(Map<String, dynamic> row) {
    final posterPath = row['poster_path'] as String?;
    if (posterPath != null && posterPath.isNotEmpty) {
      final file = File(posterPath);
      if (file.existsSync()) {
        final url = Uri.file(file.absolute.path).toString();
        debugPrint('[LocalMedia][Resolver] posterUrl: 找到海报 -> $url');
        return url;
      }
      debugPrint('[LocalMedia][Resolver] posterUrl: 海报路径存在但文件不存在: $posterPath');
    }
    debugPrint('[LocalMedia][Resolver] posterUrl: 无海报路径');
    return null;
  }

  String? backdropUrl(Map<String, dynamic> row) {
    final backdropPath = row['backdrop_path'] as String?;
    if (backdropPath != null && backdropPath.isNotEmpty) {
      final file = File(backdropPath);
      if (file.existsSync()) {
        final url = Uri.file(file.absolute.path).toString();
        debugPrint('[LocalMedia][Resolver] backdropUrl: 找到背景 -> $url');
        return url;
      }
      debugPrint('[LocalMedia][Resolver] backdropUrl: 背景路径存在但文件不存在: $backdropPath');
    }
    debugPrint('[LocalMedia][Resolver] backdropUrl: 无背景路径');
    return null;
  }

  Future<String?> thumbnailPathFor(String filePath) async {
    final cacheDir = await cacheDirectory;
    final hash = stableHash(filePath).toRadixString(36);
    final thumbPath = '${cacheDir.path}/thumb_$hash.jpg';
    final thumbFile = File(thumbPath);
    if (await thumbFile.exists()) {
      return thumbPath;
    }
    return null;
  }

  String? resolvePlayUrl(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) {
      debugPrint('[LocalMedia][Resolver] resolvePlayUrl: sourceId 为空');
      return null;
    }
    final file = File(sourceId);
    if (file.existsSync()) {
      final url = Uri.file(file.absolute.path).toString();
      debugPrint('[LocalMedia][Resolver] resolvePlayUrl: 文件存在 -> $url');
      return url;
    }
    debugPrint('[LocalMedia][Resolver] resolvePlayUrl: 文件不存在, 使用原始路径: $sourceId');
    return Uri.file(sourceId).toString();
  }

  /// Extract title from a file path (filename without extension).
  static String titleFromPath(String filePath) {
    final name = filePath.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static int stableHash(String value) => MediaIdGenerator.stableHash(value);
}
