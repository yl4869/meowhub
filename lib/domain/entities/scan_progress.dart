enum ScanPhase { idle, scanning, completed, error }

class ScanProgress {
  const ScanProgress({
    this.phase = ScanPhase.idle,
    this.message,
    this.processedFiles = 0,
    this.totalFiles = 0,
    this.newFilesCount = 0,
    this.changedFilesCount = 0,
    this.deletedFilesCount = 0,
    this.newSeriesCount = 0,
    this.errors = const [],
  });

  final ScanPhase phase;
  final String? message;
  final int processedFiles;
  final int totalFiles;
  final int newFilesCount;
  final int changedFilesCount;
  final int deletedFilesCount;
  final int newSeriesCount;
  final List<String> errors;

  bool get isScanning => phase == ScanPhase.scanning;
  bool get isCompleted => phase == ScanPhase.completed;
  bool get isError => phase == ScanPhase.error;

  ScanProgress copyWith({
    ScanPhase? phase,
    Object? message = _sentinel,
    int? processedFiles,
    int? totalFiles,
    int? newFilesCount,
    int? changedFilesCount,
    int? deletedFilesCount,
    int? newSeriesCount,
    List<String>? errors,
  }) {
    return ScanProgress(
      phase: phase ?? this.phase,
      message:
          identical(message, _sentinel) ? this.message : message as String?,
      processedFiles: processedFiles ?? this.processedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      newFilesCount: newFilesCount ?? this.newFilesCount,
      changedFilesCount: changedFilesCount ?? this.changedFilesCount,
      deletedFilesCount: deletedFilesCount ?? this.deletedFilesCount,
      newSeriesCount: newSeriesCount ?? this.newSeriesCount,
      errors: errors ?? this.errors,
    );
  }
}

const Object _sentinel = Object();
