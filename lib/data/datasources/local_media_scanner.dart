import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../models/local_media_scan_result.dart';
import '../services/media_file_name_parser.dart';
import 'local_file_resolver.dart';
import 'local_nfo_parser.dart';

class LocalMediaScanner {
  const LocalMediaScanner();

  // Delegated to MediaFileNameParser — keep for backward compat within file.
  static const _videoExtensions = MediaFileNameParser.videoExtensions;
  static const _imageNames = MediaFileNameParser.imageNames;
  static const _fanartNames = MediaFileNameParser.fanartNames;
  static const _seasonFolderPattern = MediaFileNameParser.seasonFolderPattern;

  /// Run a full scan for the given root paths.
  /// This is intended to be called from an Isolate via [runInIsolate].
  static Future<LocalMediaScanResult> runScan(
    List<String> rootPaths,
    Map<String, int> knownFiles,
  ) async {
    final stopwatch = Stopwatch()..start();
    final scanner = const LocalMediaScanner();

    debugPrint('[LocalMedia][Scanner] ===== Isolate 扫描开始 =====');
    debugPrint('[LocalMedia][Scanner] 根路径: $rootPaths');
    debugPrint('[LocalMedia][Scanner] 已知文件数: ${knownFiles.length}');

    final enumerated = <_FileEntry>[];
    for (final rootPath in rootPaths) {
      final before = enumerated.length;
      enumerated.addAll(scanner._enumerateFiles(rootPath, rootPath));
      debugPrint('[LocalMedia][Scanner] 枚举路径 "$rootPath": 找到 ${enumerated.length - before} 个视频文件');
    }
    debugPrint('[LocalMedia][Scanner] 枚举总计: ${enumerated.length} 个视频文件');

    final diff = scanner._diff(enumerated, knownFiles);
    debugPrint('[LocalMedia][Scanner] Diff 结果: 新增=${diff.added.length}, 变更=${diff.changed.length}, 删除=${diff.deleted.length}');

    final newAndChangedFiles = <ScannedFileMetadata>[];

    for (final entry in [...diff.added, ...diff.changed]) {
      final metadata = scanner._extractMetadata(entry);
      newAndChangedFiles.add(metadata);
    }

    debugPrint('[LocalMedia][Scanner] 元数据提取完成: ${newAndChangedFiles.length} 个文件');
    for (final f in newAndChangedFiles) {
      debugPrint('[LocalMedia][Scanner]   文件: ${f.fileName} | type=${f.mediaType} | title="${f.title}" | seriesId=${f.seriesId ?? "无"} | S${f.seasonNumber}E${f.episodeNumber} | poster=${f.posterPath != null ? "有" : "无"} | nfo=${f.nfoPath != null ? "有" : "无"}');
    }

    // Post-process: group unclassified files from multi-video folders into series
    final groupedFiles = scanner._postProcessFolderGrouping(
      newAndChangedFiles,
      rootPaths,
    );
    final groupedCount = groupedFiles
        .where((f) => f.mediaType == 'series' && f.seriesId != null)
        .length;
    final previouslySeriesCount = newAndChangedFiles
        .where((f) => f.mediaType == 'series' && f.seriesId != null)
        .length;
    if (groupedCount > previouslySeriesCount) {
      debugPrint('[LocalMedia][Scanner] 文件夹分组: 新增 ${groupedCount - previouslySeriesCount} 个系列文件');
    }

    final series = scanner._detectSeries(groupedFiles);
    debugPrint('[LocalMedia][Scanner] 系列检测完成: ${series.length} 个系列');
    for (final s in series) {
      debugPrint('[LocalMedia][Scanner]   系列: id=${s.id} | title="${s.title}" | poster=${s.posterPath != null ? "有" : "无"}');
    }

    stopwatch.stop();
    debugPrint('[LocalMedia][Scanner] ===== Isolate 扫描结束, 耗时: ${stopwatch.elapsed} =====');
    return LocalMediaScanResult(
      newFiles: diff.added
          .map((e) => groupedFiles.firstWhere((f) => f.filePath == e.path))
          .toList(),
      changedFiles: diff.changed
          .map((e) => groupedFiles.firstWhere((f) => f.filePath == e.path))
          .toList(),
      deletedPaths: diff.deleted,
      newSeries: series,
      scanDuration: stopwatch.elapsed,
      totalScanned: enumerated.length,
    );
  }

  /// Run scan in a separate Isolate to avoid blocking the UI.
  static Future<LocalMediaScanResult> runInIsolate(
    List<String> rootPaths,
    Map<String, int> knownFiles,
  ) async {
    return Isolate.run(() => runScan(rootPaths, knownFiles));
  }

  // --- Private implementation ---

  List<_FileEntry> _enumerateFiles(String rootPath, String rootForRelative) {
    final entries = <_FileEntry>[];
    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      debugPrint('[LocalMedia][Scanner]   _enumerateFiles: 目录不存在, 跳过: $rootPath');
      return entries;
    }

    try {
      final contents = dir.listSync();
      debugPrint('[LocalMedia][Scanner]   _enumerateFiles: 目录 "$rootPath" 包含 ${contents.length} 个子项');
      for (final entity in contents) {
        if (entity is File) {
          final ext = _extension(entity.path).toLowerCase();
          if (_videoExtensions.contains(ext)) {
            final stat = entity.statSync();
            final parentFolder = entity.parent.path;
            entries.add(_FileEntry(
              path: entity.path,
              mtime: stat.modified.millisecondsSinceEpoch,
              size: stat.size,
              parentFolder: parentFolder,
            ));
            debugPrint('[LocalMedia][Scanner]     -> 视频文件: ${entity.path}');
          }
        } else if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('.')) {
            debugPrint('[LocalMedia][Scanner]     -> 跳过隐藏目录: $name');
            continue; // skip hidden dirs
          }
          entries.addAll(_enumerateFiles(entity.path, rootForRelative));
        }
      }
    } catch (e) {
      debugPrint('[LocalMedia][Scanner]   _enumerateFiles: 无法读取目录 "$rootPath": $e');
      // Skip directories we cannot read
    }

    return entries;
  }

  _ScanDiff _diff(List<_FileEntry> enumerated, Map<String, int> knownFiles) {
    final added = <_FileEntry>[];
    final changed = <_FileEntry>[];
    final enumeratedPaths = <String>{};

    for (final entry in enumerated) {
      enumeratedPaths.add(entry.path);
      final knownMtime = knownFiles[entry.path];
      if (knownMtime == null) {
        added.add(entry);
      } else if (knownMtime != entry.mtime) {
        changed.add(entry);
      }
    }

    final deleted = knownFiles.keys
        .where((path) => !enumeratedPaths.contains(path))
        .toList();

    return _ScanDiff(added: added, changed: changed, deleted: deleted);
  }

  ScannedFileMetadata _extractMetadata(_FileEntry entry) {
    final file = File(entry.path);
    final fileName = entry.path.split(Platform.pathSeparator).last;
    final fileSize = entry.size;
    final mtime = entry.mtime;

    debugPrint('[LocalMedia][Scanner]   --- 提取元数据: $fileName ---');
    debugPrint('[LocalMedia][Scanner]     路径: ${entry.path}');
    debugPrint('[LocalMedia][Scanner]     大小: $fileSize bytes, mtime: $mtime');
    debugPrint('[LocalMedia][Scanner]     父目录: ${entry.parentFolder}');

    // Layer 1: NFO parsing
    final nfoMetadata = LocalNfoParser.parseForVideo(file);
    if (nfoMetadata != null) {
      debugPrint('[LocalMedia][Scanner]     NFO 解析成功: type=${nfoMetadata.type.name}, title="${nfoMetadata.title}", showTitle="${nfoMetadata.showTitle}", S${nfoMetadata.seasonNumber}E${nfoMetadata.episodeNumber}, year=${nfoMetadata.year}, thumb=${nfoMetadata.thumb != null ? "有" : "无"}');
    } else {
      debugPrint('[LocalMedia][Scanner]     NFO: 未找到或解析失败');
    }

    // Layer 2: Same-name images
    final posterPath = _findImage(file, isPoster: true);
    final backdropPath = _findImage(file, isPoster: false);
    debugPrint('[LocalMedia][Scanner]     图片: poster=${posterPath != null ? posterPath.split("/").last : "无"}, backdrop=${backdropPath != null ? backdropPath.split("/").last : "无"}');

    // Layer 3: Filename parsing
    final parsed = _parseFilename(fileName);
    debugPrint('[LocalMedia][Scanner]     文件名解析: title="${parsed.title}", originalTitle="${parsed.originalTitle}", year=${parsed.year}, type=${parsed.mediaType}, S${parsed.seasonNum}E${parsed.episodeNum}');

    // Determine media type and season/episode info
    final seasonMatch = RegExp(
      _seasonFolderPattern,
      caseSensitive: false,
    ).firstMatch(entry.parentFolder.split(Platform.pathSeparator).last);

    var mediaType = parsed.mediaType ?? 'movie';
    int? seasonNumber;
    int? episodeNumber;
    String? seriesTitle;

    if (nfoMetadata != null && nfoMetadata.type == NfoType.episode) {
      mediaType = 'series';
      seasonNumber = nfoMetadata.seasonNumber;
      episodeNumber = nfoMetadata.episodeNumber;
      seriesTitle = nfoMetadata.showTitle;
      debugPrint('[LocalMedia][Scanner]     类型判断: NFO 剧集 -> series, seriesTitle="${seriesTitle}"');
    } else if (parsed.seasonNum != null && parsed.episodeNum != null) {
      mediaType = 'series';
      seasonNumber = parsed.seasonNum;
      episodeNumber = parsed.episodeNum;
      debugPrint('[LocalMedia][Scanner]     类型判断: 文件名 SxxExx -> series');
    } else if (parsed.episodeNum != null) {
      // Episode number detected via EP##, E##, Chinese, or bare number patterns
      mediaType = 'series';
      seasonNumber = parsed.seasonNum ?? 1;
      episodeNumber = parsed.episodeNum;
      debugPrint('[LocalMedia][Scanner]     类型判断: 文件名剧集模式(EP/中文/数字) -> series, S${seasonNumber}E${episodeNumber}');
    } else if (seasonMatch != null) {
      mediaType = 'series';
      seasonNumber = int.tryParse(seasonMatch.group(1) ?? '');
      debugPrint('[LocalMedia][Scanner]     类型判断: 季文件夹匹配 -> series, season=$seasonNumber');
    } else {
      debugPrint('[LocalMedia][Scanner]     类型判断: 未匹配系列特征 -> movie');
    }

    final foundSeriesFolder = _findSeriesFolder(entry.path);
    debugPrint('[LocalMedia][Scanner]     系列文件夹检测: ${foundSeriesFolder ?? "未找到"}');

    // Only set seriesId for files classified as series episodes.
    // Standalone movies should not get a seriesId even if _findSeriesFolder
    // returns a folder path (e.g., their own parent directory).
    final seriesId = mediaType == 'series'
        ? (seriesTitle != null
            ? LocalFileResolver.stableHash(seriesTitle).toString()
            : (foundSeriesFolder != null
                ? LocalFileResolver.stableHash(foundSeriesFolder).toString()
                : null))
        : null;
    debugPrint('[LocalMedia][Scanner]     最终 seriesId: ${seriesId ?? "null"}');

    final title = nfoMetadata?.title ??
        parsed.title ??
        LocalFileResolver.titleFromPath(entry.path);
    debugPrint('[LocalMedia][Scanner]     最终标题: "$title"');

    return ScannedFileMetadata(
      filePath: entry.path,
      fileName: fileName,
      fileSize: fileSize,
      mtime: mtime,
      parentFolder: entry.parentFolder,
      mediaType: mediaType,
      title: title,
      originalTitle: nfoMetadata?.originalTitle ?? parsed.originalTitle,
      overview: nfoMetadata?.plot,
      year: nfoMetadata?.year ?? parsed.year,
      rating: nfoMetadata?.rating,
      posterPath: nfoMetadata?.thumb ?? posterPath,
      backdropPath: nfoMetadata?.fanart ?? backdropPath,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      nfoPath: nfoMetadata != null ? '${file.parent.path}/.nfo' : null,
    );
  }

  List<SeriesMetadata> _detectSeries(List<ScannedFileMetadata> files) {
    debugPrint('[LocalMedia][Scanner] --- 开始系列检测, 候选文件: ${files.length} ---');
    final series = <String, SeriesMetadata>{};

    for (final file in files) {
      if (file.mediaType != 'series') {
        debugPrint('[LocalMedia][Scanner]   跳过: ${file.fileName} (type=${file.mediaType})');
        continue;
      }
      if (file.seriesId == null) {
        debugPrint('[LocalMedia][Scanner]   跳过: ${file.fileName} (seriesId=null)');
        continue;
      }

      if (series.containsKey(file.seriesId)) {
        debugPrint('[LocalMedia][Scanner]   跳过: ${file.fileName} (seriesId=${file.seriesId} 已存在)');
        continue;
      }

      final seriesFolder = _findSeriesFolder(file.filePath);
      if (seriesFolder == null) {
        debugPrint('[LocalMedia][Scanner]   跳过: ${file.fileName} (找不到系列文件夹)');
        continue;
      }

      debugPrint('[LocalMedia][Scanner]   检测系列: seriesId=${file.seriesId}, folder=$seriesFolder');

      final nfoFile = File('${seriesFolder}/tvshow.nfo');
      NfoMetadata? nfo;
      if (nfoFile.existsSync()) {
        nfo = LocalNfoParser.tryParse(nfoFile);
        debugPrint('[LocalMedia][Scanner]     tvshow.nfo: ${nfo != null ? "解析成功, title=${nfo.title}" : "解析失败"}');
      } else {
        debugPrint('[LocalMedia][Scanner]     tvshow.nfo: 文件不存在');
      }

      final folderName = seriesFolder.split(Platform.pathSeparator).last;
      final title = nfo?.title ?? folderName;
      debugPrint('[LocalMedia][Scanner]     系列标题: "$title"');

      final posterPath = _findImageInDir(Directory(seriesFolder), isPoster: true);
      debugPrint('[LocalMedia][Scanner]     系列海报: ${posterPath ?? "无"}');

      series[file.seriesId!] = SeriesMetadata(
        id: file.seriesId!,
        title: title,
        folderPath: seriesFolder,
        originalTitle: nfo?.originalTitle,
        overview: nfo?.plot,
        posterPath: nfo?.thumb ?? posterPath,
        backdropPath: nfo?.fanart ??
            _findImageInDir(Directory(seriesFolder), isPoster: false),
        year: nfo?.year,
        rating: nfo?.rating,
      );
    }

    debugPrint('[LocalMedia][Scanner] --- 系列检测完成: ${series.length} 个唯一系列 ---');
    return series.values.toList();
  }

  /// Post-process: group unclassified files from multi-video folders into series.
  /// This handles folders where videos don't have SxxExx/NFO metadata but are
  /// clearly episodes of the same show based on folder grouping.
  List<ScannedFileMetadata> _postProcessFolderGrouping(
    List<ScannedFileMetadata> files,
    List<String> rootPaths,
  ) {
    // Group unclassified files by parent folder
    final unclassified = <String, List<int>>{};
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file.mediaType == 'movie' && file.seriesId == null) {
        unclassified.putIfAbsent(file.parentFolder, () => []).add(i);
      }
    }

    if (unclassified.isEmpty) {
      debugPrint('[LocalMedia][Scanner] 文件夹分组: 无未分类文件');
      return files;
    }

    debugPrint('[LocalMedia][Scanner] === 开始文件夹分组, ${unclassified.length} 个候选文件夹 ===');

    final updated = List<ScannedFileMetadata>.of(files);
    final rootPathSet = rootPaths.map((p) => p.endsWith('/') ? p : '$p/').toSet();

    for (final entry in unclassified.entries) {
      final folderPath = entry.key;
      final indices = entry.value;

      // Skip folders with only 1 file (standalone movies are fine as-is)
      if (indices.length < 2) continue;

      // Skip root paths themselves (videos directly in scan root)
      final normalizedFolder = folderPath.endsWith('/') ? folderPath : '$folderPath/';
      if (rootPathSet.any((rp) => normalizedFolder == rp)) continue;

      final folderName = folderPath.split(Platform.pathSeparator).last;
      final seriesId = LocalFileResolver.stableHash(folderPath).toString();

      debugPrint('[LocalMedia][Scanner]   文件夹分组: "$folderName" ($folderPath), ${indices.length} 个文件');

      final folderFiles = indices.map((i) => files[i]).toList();
      final assignments = _assignEpisodeNumbers(folderFiles);

      // Also scan folder for images to use as series poster
      final folderDir = Directory(folderPath);
      final seriesPoster = _findImageInDir(folderDir, isPoster: true);
      final seriesBackdrop = _findImageInDir(folderDir, isPoster: false);

      for (var j = 0; j < indices.length; j++) {
        final idx = indices[j];
        final oldFile = files[idx];
        final episodeNum = assignments[j];

        // Use series poster as fallback if individual file has no poster
        final posterPath = oldFile.posterPath ?? seriesPoster;

        updated[idx] = ScannedFileMetadata(
          filePath: oldFile.filePath,
          fileName: oldFile.fileName,
          fileSize: oldFile.fileSize,
          mtime: oldFile.mtime,
          parentFolder: oldFile.parentFolder,
          mediaType: 'series',
          title: oldFile.title ?? oldFile.fileName,
          originalTitle: oldFile.originalTitle,
          overview: oldFile.overview,
          year: oldFile.year,
          rating: oldFile.rating,
          posterPath: posterPath,
          backdropPath: oldFile.backdropPath ?? seriesBackdrop,
          seriesId: seriesId,
          seasonNumber: 1,
          episodeNumber: episodeNum,
          nfoPath: oldFile.nfoPath,
          durationMs: oldFile.durationMs,
          width: oldFile.width,
          height: oldFile.height,
        );
        debugPrint('[LocalMedia][Scanner]      -> ${oldFile.fileName}: S01E$episodeNum poster=${posterPath != null ? "有" : "无"}');
      }
    }

    debugPrint('[LocalMedia][Scanner] === 文件夹分组完成 ===');
    return updated;
  }

  /// Try to extract episode numbers from filenames. Missing numbers get
  /// auto-assigned sequentially starting from 1, skipping already-used numbers.
  List<int> _assignEpisodeNumbers(List<ScannedFileMetadata> files) {
    return MediaFileNameParser.assignEpisodeNumbers(
      files.map((f) => f.fileName).toList(),
    );
  }

  String? _findImage(File videoFile, {required bool isPoster}) {
    final dir = videoFile.parent;
    final basename = LocalNfoParser.basenameWithoutExtension(videoFile.path);

    // Same-name poster
    for (final ext in ['.jpg', '.png']) {
      final candidate = File('${dir.path}/$basename$ext');
      if (candidate.existsSync()) {
        debugPrint('[LocalMedia][Scanner]       _findImage(${isPoster ? "poster" : "backdrop"}): 找到同名图片 ${candidate.path.split("/").last}');
        return candidate.path;
      }
    }
    for (final ext in ['.jpg', '.png']) {
      final candidate = File('${dir.path}/${basename}-poster$ext');
      if (isPoster && candidate.existsSync()) {
        debugPrint('[LocalMedia][Scanner]       _findImage(poster): 找到 poster 变体 ${candidate.path.split("/").last}');
        return candidate.path;
      }
    }

    // Generic images in directory
    final generic = _findImageInDir(dir, isPoster: isPoster);
    if (generic != null) {
      debugPrint('[LocalMedia][Scanner]       _findImage(${isPoster ? "poster" : "backdrop"}): 找到通用图片 ${generic.split("/").last}');
    }
    return generic;
  }

  String? _findImageInDir(Directory dir, {required bool isPoster}) {
    final names = isPoster ? _imageNames : _fanartNames;
    try {
      for (final entity in dir.listSync()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last.toLowerCase();
          if (names.contains(name)) return entity.path;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _findSeriesFolder(String filePath) {
    // Walk up directories looking for the series root.
    // Strategy: walk up from the video file. If a directory contains tvshow.nfo
    // or its name doesn't match a season folder pattern, it's the series root.
    // Season folders (e.g. "Season 1") are skipped by walking up.
    var current = File(filePath).parent;
    const maxDepth = 5;
    for (var i = 0; i < maxDepth; i++) {
      final dirName = current.path.split(Platform.pathSeparator).last;
      debugPrint('[LocalMedia][Scanner]       _findSeriesFolder depth=$i: 检查 "$dirName" (${current.path})');

      // tvshow.nfo is the strongest signal
      if (File('${current.path}/tvshow.nfo').existsSync()) {
        debugPrint('[LocalMedia][Scanner]         -> 找到 tvshow.nfo, 返回: ${current.path}');
        return current.path;
      }

      // If the directory name does NOT look like a season folder (e.g. "Season 1",
      // "S01", etc.), it's the series root — whether at depth 0 (flat structure
      // like /ShowName/Episode.mp4) or depth > 0 (walked past season subdir).
      if (!RegExp(_seasonFolderPattern, caseSensitive: false).hasMatch(dirName)) {
        debugPrint('[LocalMedia][Scanner]         -> 非季文件夹, 返回: ${current.path}');
        return current.path;
      }

      // Directory name matches season pattern, walk up to parent
      current = current.parent;
    }
    debugPrint('[LocalMedia][Scanner]       _findSeriesFolder: 未找到系列文件夹 (maxDepth=$maxDepth)');
    return null;
  }

  static String _extension(String path) => MediaFileNameParser.extension(path);

  static _ParsedFilename _parseFilename(String fileName) {
    final parsed = MediaFileNameParser.parseFilename(fileName);
    debugPrint('[LocalMedia][Scanner]       _parseFilename: 原始="$fileName"'
        ' -> type=${parsed.mediaType} title=${parsed.title}'
        ' S${parsed.seasonNum}E${parsed.episodeNum}');
    return _ParsedFilename(
      title: parsed.title,
      originalTitle: parsed.originalTitle,
      year: parsed.year,
      mediaType: parsed.mediaType,
      seasonNum: parsed.seasonNum,
      episodeNum: parsed.episodeNum,
    );
  }

}

// --- Internal types ---

class _FileEntry {
  const _FileEntry({
    required this.path,
    required this.mtime,
    required this.size,
    required this.parentFolder,
  });

  final String path;
  final int mtime;
  final int size;
  final String parentFolder;
}

class _ScanDiff {
  const _ScanDiff({
    required this.added,
    required this.changed,
    required this.deleted,
  });

  final List<_FileEntry> added;
  final List<_FileEntry> changed;
  final List<String> deleted;
}

class _ParsedFilename {
  const _ParsedFilename({
    this.title,
    this.originalTitle,
    this.year,
    this.mediaType,
    this.seasonNum,
    this.episodeNum,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final String? mediaType;
  final int? seasonNum;
  final int? episodeNum;
}
