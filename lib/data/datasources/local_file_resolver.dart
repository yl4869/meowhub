import 'dart:io';

import '../../domain/utils/id_generator.dart';

abstract final class LocalFileResolver {
  static String? posterUrl(Map<String, dynamic> row) {
    final posterPath = row['poster_path'] as String?;
    if (posterPath != null && posterPath.isNotEmpty) {
      final file = File(posterPath);
      if (file.existsSync()) {
        return Uri.file(file.absolute.path).toString();
      }
    }
    return null;
  }

  static String? backdropUrl(Map<String, dynamic> row) {
    final backdropPath = row['backdrop_path'] as String?;
    if (backdropPath != null && backdropPath.isNotEmpty) {
      final file = File(backdropPath);
      if (file.existsSync()) {
        return Uri.file(file.absolute.path).toString();
      }
    }
    return null;
  }

  static String? resolvePlayUrl(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) return null;
    final file = File(sourceId);
    if (file.existsSync()) {
      return Uri.file(file.absolute.path).toString();
    }
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
