import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/datasources/local_media_database.dart';
import '../data/datasources/local_media_scanner.dart';
import '../data/models/local_media_scan_result.dart';

enum ScanState { idle, scanning, completed, error }

class LocalMediaProvider extends ChangeNotifier {
  LocalMediaProvider({required LocalMediaDatabase database})
    : _database = database;

  final LocalMediaDatabase _database;

  ScanState _scanState = ScanState.idle;
  String? _scanMessage;
  String? _scanError;
  int _scannedFiles = 0;
  int _totalFiles = 0;
  LocalMediaScanResult? _lastScanResult;

  ScanState get scanState => _scanState;
  String? get scanMessage => _scanMessage;
  String? get scanError => _scanError;
  int get scannedFiles => _scannedFiles;
  int get totalFiles => _totalFiles;
  LocalMediaScanResult? get lastScanResult => _lastScanResult;
  bool get isScanning => _scanState == ScanState.scanning;

  /// Run a full scan for all registered root paths.
  Future<void> runFullScan(List<String> rootPaths) async {
    if (_scanState == ScanState.scanning) {
      debugPrint('[LocalMedia][Provider] 扫描已在进行中，跳过本次请求');
      return;
    }

    debugPrint('[LocalMedia][Provider] ========== 开始全量扫描 ==========');
    debugPrint('[LocalMedia][Provider] 根路径数量: ${rootPaths.length}');
    for (var i = 0; i < rootPaths.length; i++) {
      debugPrint('[LocalMedia][Provider] 根路径[$i]: ${rootPaths[i]}');
    }

    _scanState = ScanState.scanning;
    _scanMessage = '正在扫描文件夹...';
    _scanError = null;
    _scannedFiles = 0;
    _totalFiles = 0;
    notifyListeners();

    try {
      final knownFiles = await _database.getKnownFiles();
      debugPrint('[LocalMedia][Provider] 已知文件数: ${knownFiles.length}');

      _scanMessage = '发现 ${knownFiles.length} 个已知文件，正在检测变更...';
      notifyListeners();

      final result = await LocalMediaScanner.runInIsolate(rootPaths, knownFiles);
      debugPrint('[LocalMedia][Provider] Isolate 扫描完成, 耗时: ${result.scanDuration}');
      debugPrint('[LocalMedia][Provider] 扫描结果: 新增=${result.newFiles.length}, 变更=${result.changedFiles.length}, 删除=${result.deletedPaths.length}, 新系列=${result.newSeries.length}, 总文件=${result.totalScanned}');

      _persistScanResult(result, rootPaths);

      _lastScanResult = result;
      _scanState = ScanState.completed;
      _scanMessage = _buildCompletionMessage(result);
      _scannedFiles = result.newAndChanged.length;
      _totalFiles = result.totalScanned;
      debugPrint('[LocalMedia][Provider] 扫描状态已设为 completed, 消息: $_scanMessage');
    } catch (error, stackTrace) {
      debugPrint('[LocalMedia][Provider] 扫描失败: $error');
      debugPrint('[LocalMedia][Provider] 堆栈: $stackTrace');
      _scanState = ScanState.error;
      _scanError = error.toString();
      _scanMessage = '扫描失败';
    }

    debugPrint('[LocalMedia][Provider] ========== 扫描结束 (状态: ${_scanState.name}) ==========');
    notifyListeners();
  }

  Future<void> _persistScanResult(
    LocalMediaScanResult result,
    List<String> rootPaths,
  ) async {
    debugPrint('[LocalMedia][Provider] 开始持久化扫描结果...');
    debugPrint('[LocalMedia][Provider] 待持久化: ${result.newAndChanged.length} 个文件, ${result.newSeries.length} 个系列, ${result.deletedPaths.length} 个待删除');

    // Persist new and changed files
    for (final file in result.newAndChanged) {
      debugPrint('[LocalMedia][Provider]   持久化文件: path=${file.filePath}, type=${file.mediaType}, title=${file.title}, seriesId=${file.seriesId}, poster=${file.posterPath != null ? "有" : "无"}');
      await _database.upsertScannedFile({
        'id': file.filePath.hashCode.toString(),
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

    // Persist new series
    for (final series in result.newSeries) {
      debugPrint('[LocalMedia][Provider]   持久化系列: id=${series.id}, title=${series.title}, poster=${series.posterPath != null ? "有" : "无"}');
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

    // Delete removed files
    if (result.deletedPaths.isNotEmpty) {
      debugPrint('[LocalMedia][Provider]   删除文件: ${result.deletedPaths.length} 个路径');
    }
    await _database.deleteScannedFiles(result.deletedPaths);

    // Update scan timestamps
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final path in rootPaths) {
      await _database.updateScanFolder(path, scannedAt: now);
    }
    debugPrint('[LocalMedia][Provider] 持久化完成');
  }

  /// Run incremental scan for registered paths.
  Future<void> runIncrementalScan(List<String> rootPaths) async {
    if (_scanState == ScanState.scanning) return;
    await runFullScan(rootPaths);
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
}
