import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'local_file_resolver.dart';

class LocalThumbnailService {
  LocalThumbnailService();

  static const int _maxCacheFiles = 500;

  Directory? _cacheDir;
  bool _cleanupScheduled = false;

  Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationSupportDirectory();
    _cacheDir = Directory('${appDir.path}/thumbnails');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  String _thumbnailFileName(String filePath) {
    final hash = LocalFileResolver.stableHash(filePath).toRadixString(36);
    return 'thumb_$hash.jpg';
  }

  /// Get thumbnail path for a video file.
  /// Returns cached path if exists, otherwise generates a new thumbnail.
  Future<String?> thumbnailFor(String filePath) async {
    final cacheDir = await cacheDirectory;
    final thumbName = _thumbnailFileName(filePath);
    final thumbFile = File('${cacheDir.path}/$thumbName');

    if (await thumbFile.exists()) {
      debugPrint('[LocalMedia][Thumb] 使用缓存缩略图: ${thumbFile.path}');
      return thumbFile.path;
    }

    debugPrint('[LocalMedia][Thumb] 缓存未命中, 开始生成缩略图: $filePath');
    return _generateThumbnail(filePath, thumbFile);
  }

  Future<String?> _generateThumbnail(String filePath, File thumbFile) async {
    if (!File(filePath).existsSync()) {
      debugPrint('[LocalMedia][Thumb] 源文件不存在, 无法生成缩略图: $filePath');
      return null;
    }

    String? result;

    // video_thumbnail only works on Android/iOS
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        debugPrint('[LocalMedia][Thumb] 尝试 video_thumbnail 插件...');
        final path = await VideoThumbnail.thumbnailFile(
          video: filePath,
          thumbnailPath: thumbFile.parent.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 320,
          quality: 85,
        );
        if (path != null && File(path).existsSync()) {
          debugPrint('[LocalMedia][Thumb] video_thumbnail 成功: $path');
          result = path;
        }
      } catch (e) {
        debugPrint('[LocalMedia][Thumb] video_thumbnail 失败: $e, 回退到 ffmpeg');
      }
    } else {
      debugPrint('[LocalMedia][Thumb] 非移动平台 (${Platform.operatingSystem}), 跳过 video_thumbnail');
    }

    // Desktop fallback: try ffmpeg
    result ??= await _generateWithFfmpeg(filePath, thumbFile);

    if (result != null) {
      debugPrint('[LocalMedia][Thumb] 缩略图生成完成: $result');
      unawaited(_scheduleCleanup());
    } else {
      debugPrint('[LocalMedia][Thumb] 缩略图生成失败, 无可用方法');
    }
    return result;
  }

  Future<String?> _generateWithFfmpeg(String filePath, File thumbFile) async {
    try {
      debugPrint('[LocalMedia][Thumb] 尝试 ffmpeg: $filePath');
      final result = await Process.run(
        'ffmpeg',
        [
          '-ss', '00:00:05',
          '-i', filePath,
          '-vframes', '1',
          '-vf', 'scale=320:-1',
          '-q:v', '5',
          '-y',
          thumbFile.path,
        ],
        runInShell: true,
      );

      if (result.exitCode == 0 && await thumbFile.exists()) {
        debugPrint('[LocalMedia][Thumb] ffmpeg 成功: ${thumbFile.path}');
        return thumbFile.path;
      }
      debugPrint('[LocalMedia][Thumb] ffmpeg 失败: exitCode=${result.exitCode}, stderr=${result.stderr}');
    } catch (e) {
      debugPrint('[LocalMedia][Thumb] ffmpeg 不可用: $e');
    }
    return null;
  }

  /// Clear all cached thumbnails.
  Future<void> clearCache() async {
    final cacheDir = await cacheDirectory;
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      _cacheDir = null;
    }
  }

  Future<void> _scheduleCleanup() async {
    if (_cleanupScheduled) return;
    _cleanupScheduled = true;
    Future<void>.microtask(() async {
      try {
        await _pruneOldest();
      } catch (_) {
        // Best-effort cleanup; failures are non-critical.
      } finally {
        _cleanupScheduled = false;
      }
    });
  }

  Future<void> _pruneOldest() async {
    final cacheDir = await cacheDirectory;
    if (!await cacheDir.exists()) return;

    final files = await cacheDir.list().toList();
    if (files.length <= _maxCacheFiles) return;

    final withDates = <_FileWithDate>[];
    for (final entity in files) {
      if (entity is File) {
        try {
          final stat = await entity.stat();
          withDates.add(_FileWithDate(entity, stat.modified));
        } catch (_) {
          // Skip files we can't stat.
        }
      }
    }

    withDates.sort((a, b) => a.modified.compareTo(b.modified));
    final toRemove = withDates.take(files.length - _maxCacheFiles);
    for (final entry in toRemove) {
      try {
        await entry.file.delete();
      } catch (_) {
        // Skip files we can't delete.
      }
    }
  }
}

class _FileWithDate {
  const _FileWithDate(this.file, this.modified);
  final File file;
  final DateTime modified;
}
