import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/scan_progress.dart';
import '../../domain/repositories/i_media_maintainer.dart';
import '../../domain/utils/id_generator.dart';
import '../datasources/local_media_database.dart';
import '../datasources/local_media_scanner.dart';
import '../datasources/local_nfo_parser.dart';
import '../models/local_media_scan_result.dart';
import 'android_saf_service.dart';
import 'media_file_name_parser.dart';

class LocalMediaMaintainer implements IMediaMaintainer {
  LocalMediaMaintainer({
    required LocalMediaDatabase database,
    AndroidSafService? safService,
  }) : _database = database, _safService = safService;

  @override
  VoidCallback? onScanCompleted;

  final LocalMediaDatabase _database;
  final AndroidSafService? _safService;

  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  ScanProgress _currentProgress = const ScanProgress();
  bool _isScanning = false;
  List<String>? _pendingRootPaths;

  @override
  ScanProgress get currentProgress => _currentProgress;

  @override
  Stream<ScanProgress> get progressStream => _progressController.stream;

  @override
  Future<void> runScan(List<String> rootPaths) async {
    if (_isScanning) {
      debugPrint('[LocalMedia][Maintainer] 扫描已在进行中，排队等待: ${rootPaths.length} 个根路径');
      _pendingRootPaths = rootPaths;
      return;
    }

    debugPrint('[LocalMedia][Maintainer] ========== 开始全量扫描 ==========');
    debugPrint('[LocalMedia][Maintainer] 根路径数量: ${rootPaths.length}');
    for (var i = 0; i < rootPaths.length; i++) {
      debugPrint('[LocalMedia][Maintainer] 根路径[$i]: ${rootPaths[i]}');
    }

    _isScanning = true;
    _emitProgress(const ScanProgress(
      phase: ScanPhase.scanning,
      message: '正在扫描文件夹...',
    ));

    try {
      // Partition paths: file-system paths vs SAF content:// URIs.
      final filePaths = rootPaths
          .where((p) => !AndroidSafService.isContentUri(p))
          .toList();
      final safTreeUris = rootPaths
          .where((p) => AndroidSafService.isContentUri(p))
          .toList();

      final allKnownFiles = await _database.getKnownFiles();
      debugPrint('[LocalMedia][Maintainer] 已知文件数: ${allKnownFiles.length}');

      LocalMediaScanResult result = const LocalMediaScanResult();
      final stopwatch = Stopwatch()..start();

      // --- dart:io path (existing, runs in Isolate) ---
      if (filePaths.isNotEmpty) {
        _emitProgress(const ScanProgress(
          phase: ScanPhase.scanning,
          message: '正在扫描本地文件夹...',
        ));
        result = await LocalMediaScanner.runInIsolate(
          filePaths,
          allKnownFiles,
        );
        debugPrint(
          '[LocalMedia][Maintainer] Isolate 扫描完成, 耗时: ${result.scanDuration}',
        );
      }

      // --- SAF path (platform channel, runs on main thread) ---
      if (safTreeUris.isNotEmpty && _safService != null) {
        _emitProgress(ScanProgress(
          phase: ScanPhase.scanning,
          message: '正在扫描 SAF 文件夹 (${safTreeUris.length} 个)...',
        ));
        final safResult = await _scanSafTrees(safTreeUris, allKnownFiles);
        result = _mergeScanResults(result, safResult);
      }

      final elapsed = stopwatch.elapsed;
      debugPrint(
        '[LocalMedia][Maintainer] 总扫描完成, 耗时: $elapsed, '
        '新增=${result.newFiles.length}, 变更=${result.changedFiles.length}, '
        '删除=${result.deletedPaths.length}, 新系列=${result.newSeries.length}',
      );

      await _persistScanResult(result, rootPaths);

      _currentProgress = ScanProgress(
        phase: ScanPhase.completed,
        message: _buildCompletionMessage(result),
        processedFiles: result.newAndChanged.length,
        totalFiles: result.totalScanned,
        newFilesCount: result.newFiles.length,
        changedFilesCount: result.changedFiles.length,
        deletedFilesCount: result.deletedPaths.length,
        newSeriesCount: result.newSeries.length,
      );
      _progressController.add(_currentProgress);
      onScanCompleted?.call();
      debugPrint(
        '[LocalMedia][Maintainer] 扫描状态已设为 completed, '
        '消息: ${_currentProgress.message}',
      );
    } catch (error, stackTrace) {
      debugPrint('[LocalMedia][Maintainer] 扫描失败: $error');
      debugPrint('[LocalMedia][Maintainer] 堆栈: $stackTrace');
      _currentProgress = ScanProgress(
        phase: ScanPhase.error,
        message: '扫描失败: $error',
      );
      _progressController.add(_currentProgress);
      onScanCompleted?.call();
    }

    _isScanning = false;
    debugPrint('[LocalMedia][Maintainer] ========== 扫描结束 ==========');

    // 处理排队中的扫描请求
    if (_pendingRootPaths != null) {
      final pending = _pendingRootPaths!;
      _pendingRootPaths = null;
      debugPrint('[LocalMedia][Maintainer] 开始处理排队扫描: ${pending.length} 个根路径');
      unawaited(runScan(pending));
    }
  }

  @override
  Future<void> runIncrementalScan(List<String> rootPaths) async {
    if (_isScanning) {
      _pendingRootPaths = rootPaths;
      return;
    }
    await runScan(rootPaths);
  }

  /// Scan SAF tree URIs via the native platform channel.
  ///
  /// The native side handles all I/O (tree walk, NFO reading, image
  /// discovery). Dart only does pure computation: filename parsing,
  /// NFO XML parsing, folder grouping, and series detection.
  Future<LocalMediaScanResult> _scanSafTrees(
    List<String> treeUris,
    Map<String, int> knownFiles,
  ) async {
    final allNewFiles = <ScannedFileMetadata>[];
    final allChangedFiles = <ScannedFileMetadata>[];
    final allDeletedPaths = <String>[];
    final allSeries = <SeriesMetadata>[];
    var totalScanned = 0;

    for (final treeUri in treeUris) {
      debugPrint('[LocalMedia][Maintainer] SAF 扫描: $treeUri');
      final safResult = await _safService!.scanTree(treeUri);
      totalScanned += safResult.totalFound;

      // Build set of current URIs for diffing.
      final currentUris = <String>{};
      for (final entry in safResult.files) {
        currentUris.add(entry.uri);
        final mtime = entry.mtime;
        final knownMtime = knownFiles[entry.uri];

        if (knownMtime == null || knownMtime != mtime) {
          final metadata = _safEntryToMetadata(entry);
          if (knownMtime == null) {
            allNewFiles.add(metadata);
          } else {
            allChangedFiles.add(metadata);
          }
        }
      }

      // Detect deletions: entries known but not in current scan.
      for (final knownUri in knownFiles.keys) {
        if (knownUri.startsWith('content://') &&
            _isUnderTreeUri(knownUri, treeUri) &&
            !currentUris.contains(knownUri)) {
          allDeletedPaths.add(knownUri);
        }
      }

      // Post-process: folder grouping + series detection (pure Dart).
      final grouped = _postProcessFolderGrouping(
        [...allNewFiles, ...allChangedFiles],
        treeUris,
      );
      final series = _detectSeriesSaf(grouped);
      allSeries.addAll(series);
    }

    return LocalMediaScanResult(
      newFiles: allNewFiles,
      changedFiles: allChangedFiles,
      deletedPaths: allDeletedPaths,
      newSeries: allSeries,
      totalScanned: totalScanned,
    );
  }

  /// Convert a native SAF entry into [ScannedFileMetadata].
  ///
  /// Merges NFO metadata (priority) with filename heuristics, mirroring
  /// [LocalMediaScanner._extractMetadata].
  ScannedFileMetadata _safEntryToMetadata(AndroidSafFileEntry entry) {
    final parsed = MediaFileNameParser.parseFilename(entry.name);

    NfoMetadata? nfo;
    if (entry.nfoContent != null) {
      nfo = LocalNfoParser.tryParseString(entry.nfoContent!,
          parentDir: entry.parentUri);
    }

    final mediaType = (nfo != null && nfo.type == NfoType.episode) ||
            parsed.mediaType == 'series'
        ? 'series'
        : 'movie';

    final seriesId = mediaType == 'series'
        ? (nfo?.showTitle ?? entry.parentUri).hashCode.toString()
        : null;

    final seasonNumber = nfo?.seasonNumber ??
        parsed.seasonNum ??
        _extractSeasonFromName(entry.seasonFolderName);

    return ScannedFileMetadata(
      filePath: entry.uri,
      fileName: entry.name,
      fileSize: entry.size,
      mtime: entry.mtime,
      parentFolder: entry.parentUri,
      mediaType: mediaType,
      title: nfo?.title ?? parsed.title ?? entry.name,
      originalTitle: nfo?.originalTitle ?? parsed.originalTitle,
      overview: nfo?.plot,
      year: nfo?.year ?? parsed.year,
      rating: nfo?.rating,
      posterPath: nfo?.thumb ?? entry.posterUri,
      backdropPath: nfo?.fanart ?? entry.backdropUri,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      episodeNumber: nfo?.episodeNumber ?? parsed.episodeNum,
      nfoPath: entry.nfoContent != null ? '${entry.parentUri}/.nfo' : null,
    );
  }

  /// Extract season number from a folder name like "Season 1".
  static int? _extractSeasonFromName(String? folderName) {
    if (folderName == null) return null;
    final match = RegExp(MediaFileNameParser.seasonFolderPattern,
            caseSensitive: false)
        .firstMatch(folderName);
    return match != null ? int.tryParse(match.group(1) ?? '') : null;
  }

  /// Check whether a document URI lives under a given tree URI.
  static bool _isUnderTreeUri(String docUri, String treeUri) {
    return docUri.startsWith(treeUri) ||
        docUri.startsWith(treeUri.replaceAll('/tree/', '/document/'));
  }

  /// Pure-Dart version of [LocalMediaScanner._postProcessFolderGrouping].
  ///
  /// Groups unclassified files from multi-video folders into series episodes.
  List<ScannedFileMetadata> _postProcessFolderGrouping(
    List<ScannedFileMetadata> files,
    List<String> rootPaths,
  ) {
    final unclassified = <String, List<int>>{};
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      if (file.mediaType == 'movie' && file.seriesId == null) {
        unclassified.putIfAbsent(file.parentFolder, () => []).add(i);
      }
    }
    if (unclassified.isEmpty) return files;

    final updated = List<ScannedFileMetadata>.of(files);
    final rootSet = rootPaths.toSet();

    for (final entry in unclassified.entries) {
      final folderUri = entry.key;
      final indices = entry.value;
      if (indices.length < 2) continue;
      if (rootSet.contains(folderUri)) continue;

      final seriesId = folderUri.hashCode.toString();
      final folderFiles = indices.map((i) => files[i]).toList();
      final assignments =
          MediaFileNameParser.assignEpisodeNumbers(
              folderFiles.map((f) => f.fileName).toList());

      for (var j = 0; j < indices.length; j++) {
        final idx = indices[j];
        final old = files[idx];
        updated[idx] = ScannedFileMetadata(
          filePath: old.filePath,
          fileName: old.fileName,
          fileSize: old.fileSize,
          mtime: old.mtime,
          parentFolder: old.parentFolder,
          mediaType: 'series',
          title: old.title ?? old.fileName,
          originalTitle: old.originalTitle,
          overview: old.overview,
          year: old.year,
          rating: old.rating,
          posterPath: old.posterPath,
          backdropPath: old.backdropPath,
          seriesId: seriesId,
          seasonNumber: 1,
          episodeNumber: assignments[j],
          nfoPath: old.nfoPath,
          durationMs: old.durationMs,
          width: old.width,
          height: old.height,
        );
      }
    }
    return updated;
  }

  /// Pure-Dart version of [LocalMediaScanner._detectSeries].
  ///
  /// Consolidates series metadata from episode files.
  List<SeriesMetadata> _detectSeriesSaf(List<ScannedFileMetadata> files) {
    final series = <String, SeriesMetadata>{};
    for (final file in files) {
      if (file.mediaType != 'series' || file.seriesId == null) continue;
      if (series.containsKey(file.seriesId)) continue;

      // For SAF files the series title comes from folder grouping /
      // tvshow.nfo (already resolved in _safEntryToMetadata).
      series[file.seriesId!] = SeriesMetadata(
        id: file.seriesId!,
        title: file.title ?? file.parentFolder,
        folderPath: file.parentFolder,
        posterPath: file.posterPath,
        backdropPath: file.backdropPath,
        year: file.year,
        rating: file.rating,
      );
    }
    return series.values.toList();
  }

  /// Merge two [LocalMediaScanResult]s (dart:io + SAF).
  LocalMediaScanResult _mergeScanResults(
    LocalMediaScanResult a,
    LocalMediaScanResult b,
  ) {
    return LocalMediaScanResult(
      newFiles: [...a.newFiles, ...b.newFiles],
      changedFiles: [...a.changedFiles, ...b.changedFiles],
      deletedPaths: [...a.deletedPaths, ...b.deletedPaths],
      newSeries: [...a.newSeries, ...b.newSeries],
      scanDuration: a.scanDuration + b.scanDuration,
      totalScanned: a.totalScanned + b.totalScanned,
    );
  }

  void _emitProgress(ScanProgress progress) {
    _currentProgress = progress;
    _progressController.add(progress);
  }

  Future<void> _persistScanResult(
    LocalMediaScanResult result,
    List<String> rootPaths,
  ) async {
    debugPrint('[LocalMedia][Maintainer] 开始持久化扫描结果...');
    debugPrint(
      '[LocalMedia][Maintainer] 待持久化: ${result.newAndChanged.length} 个文件, '
      '${result.newSeries.length} 个系列, ${result.deletedPaths.length} 个待删除',
    );

    for (final file in result.newAndChanged) {
      debugPrint(
        '[LocalMedia][Maintainer]   持久化文件: path=${file.filePath}, '
        'type=${file.mediaType}, title=${file.title}, '
        'seriesId=${file.seriesId}, poster=${file.posterPath != null ? "有" : "无"}',
      );
      await _database.upsertScannedFile({
        'id': MediaIdGenerator.stableHash(file.filePath).toString(),
        'file_path': file.filePath,
        'file_name': file.fileName,
        'file_size': file.fileSize,
        'mtime': file.mtime,
        'duration_ms': file.durationMs,
        'width': file.width,
        'height': file.height,
        'media_type': file.mediaType,
        'title': file.title,
        'original_title': file.originalTitle,
        'overview': file.overview,
        'year': file.year,
        'rating': file.rating,
        'poster_path': file.posterPath,
        'backdrop_path': file.backdropPath,
        'series_id': file.seriesId,
        'season_number': file.seasonNumber,
        'episode_number': file.episodeNumber,
        'parent_folder': file.parentFolder,
        'nfo_path': file.nfoPath,
      });
    }

    for (final series in result.newSeries) {
      debugPrint(
        '[LocalMedia][Maintainer]   持久化系列: id=${series.id}, '
        'title=${series.title}, poster=${series.posterPath != null ? "有" : "无"}',
      );
      await _database.upsertSeries({
        'id': series.id,
        'title': series.title,
        'original_title': series.originalTitle,
        'overview': series.overview,
        'poster_path': series.posterPath,
        'backdrop_path': series.backdropPath,
        'year': series.year,
        'rating': series.rating,
        'folder_path': series.folderPath,
      });
    }

    if (result.deletedPaths.isNotEmpty) {
      debugPrint(
        '[LocalMedia][Maintainer]   删除文件: ${result.deletedPaths.length} 个路径',
      );
    }
    await _database.deleteScannedFiles(result.deletedPaths);

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final path in rootPaths) {
      await _database.updateScanFolder(path, scannedAt: now);
    }
    debugPrint('[LocalMedia][Maintainer] 持久化完成');
  }

  String _buildCompletionMessage(LocalMediaScanResult result) {
    final parts = <String>[];
    if (result.newFiles.isNotEmpty) {
      parts.add('新增 ${result.newFiles.length} 个');
    }
    if (result.changedFiles.isNotEmpty) {
      parts.add('更新 ${result.changedFiles.length} 个');
    }
    if (result.deletedPaths.isNotEmpty) {
      parts.add('移除 ${result.deletedPaths.length} 个');
    }
    if (result.newSeries.isNotEmpty) {
      parts.add('识别 ${result.newSeries.length} 个系列');
    }
    if (parts.isEmpty) {
      return '未发现变化';
    }
    return '扫描完成：${parts.join('，')}';
  }

  void dispose() {
    _progressController.close();
  }
}
