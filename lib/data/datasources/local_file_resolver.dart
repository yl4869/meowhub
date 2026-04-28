import 'dart:io';

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

  static bool _isContentUri(String path) => path.startsWith('content://');

  String? posterUrl(Map<String, dynamic> row) {
    final posterPath = row['poster_path'] as String?;
    if (posterPath == null || posterPath.isEmpty) return null;
    if (_isContentUri(posterPath)) return posterPath;
    final file = File(posterPath);
    if (file.existsSync()) {
      return Uri.file(file.absolute.path).toString();
    }
    return null;
  }

  String? backdropUrl(Map<String, dynamic> row) {
    final backdropPath = row['backdrop_path'] as String?;
    if (backdropPath == null || backdropPath.isEmpty) return null;
    if (_isContentUri(backdropPath)) return backdropPath;
    final file = File(backdropPath);
    if (file.existsSync()) {
      return Uri.file(file.absolute.path).toString();
    }
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
    if (sourceId == null || sourceId.isEmpty) return null;
    // content:// URIs pass through directly — MediaKit handles them natively.
    if (_isContentUri(sourceId)) return sourceId;
    final file = File(sourceId);
    if (file.existsSync()) {
      return Uri.file(file.absolute.path).toString();
    }
    return Uri.file(sourceId).toString();
  }

  /// Extract a display-friendly title from a file path or URI.
  static String titleFromPath(String filePath) {
    if (_isContentUri(filePath)) {
      // Decode the last segment of a content URI.
      final decoded = Uri.decodeComponent(filePath);
      final lastSlash = decoded.lastIndexOf('/');
      final name = lastSlash >= 0 ? decoded.substring(lastSlash + 1) : decoded;
      final dot = name.lastIndexOf('.');
      return dot > 0 ? name.substring(0, dot) : name;
    }
    final name = filePath.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static int stableHash(String value) => MediaIdGenerator.stableHash(value);
}
