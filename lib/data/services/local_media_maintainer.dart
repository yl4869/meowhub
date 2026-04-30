import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/scan_progress.dart';
import '../../domain/repositories/i_media_maintainer.dart';
import '../../domain/utils/id_generator.dart';
import '../datasources/local_media_database.dart';
import '../datasources/local_media_scanner.dart';
import '../models/local_media_scan_result.dart';

class LocalMediaMaintainer implements IMediaMaintainer {
  LocalMediaMaintainer({required LocalMediaDatabase database})
    : _database = database;

  @override
  VoidCallback? onScanCompleted;

  final LocalMediaDatabase _database;

  final StreamController<ScanProgress> _progressController =
      StreamController<ScanProgress>.broadcast();

  ScanProgress _currentProgress = const ScanProgress();
  bool _isScanning = false;

  @override
  ScanProgress get currentProgress => _currentProgress;

  @override
  Stream<ScanProgress> get progressStream => _progressController.stream;

  @override
  Future<void> runScan(List<String> rootPaths) async {
    if (_isScanning) {
      debugPrint('[LocalMedia][Maintainer] 扫描已在进行中，跳过本次请求');
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
      final knownFiles = await _database.getKnownFiles();
      debugPrint('[LocalMedia][Maintainer] 已知文件数: ${knownFiles.length}');

      _emitProgress(ScanProgress(
        phase: ScanPhase.scanning,
        message: '发现 ${knownFiles.length} 个已知文件，正在检测变更...',
      ));

      final result = await LocalMediaScanner.runInIsolate(
        rootPaths,
        knownFiles,
      );
      debugPrint(
        '[LocalMedia][Maintainer] Isolate 扫描完成, 耗时: ${result.scanDuration}',
      );
      debugPrint(
        '[LocalMedia][Maintainer] 扫描结果: 新增=${result.newFiles.length}, '
        '变更=${result.changedFiles.length}, 删除=${result.deletedPaths.length}, '
        '新系列=${result.newSeries.length}, 总文件=${result.totalScanned}',
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
  }

  @override
  Future<void> runIncrementalScan(List<String> rootPaths) async {
    if (_isScanning) return;
    await runScan(rootPaths);
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
