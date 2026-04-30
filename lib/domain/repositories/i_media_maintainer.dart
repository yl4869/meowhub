import '../entities/scan_progress.dart';

abstract class IMediaMaintainer {
  ScanProgress get currentProgress;

  Stream<ScanProgress> get progressStream;

  Future<void> runScan(List<String> rootPaths);

  Future<void> runIncrementalScan(List<String> rootPaths);
}
