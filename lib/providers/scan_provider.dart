import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/scan_progress.dart';
import '../domain/repositories/i_media_maintainer.dart';

class ScanProvider extends ChangeNotifier {
  ScanProvider({required IMediaMaintainer maintainer}) : _maintainer = maintainer {
    _subscription = _maintainer.progressStream.listen((progress) {
      _progress = progress;
      notifyListeners();
    });
  }

  final IMediaMaintainer _maintainer;
  StreamSubscription<ScanProgress>? _subscription;

  ScanProgress _progress = const ScanProgress();

  ScanProgress get progress => _progress;
  Stream<ScanProgress> get progressStream => _maintainer.progressStream;
  bool get isScanning => _progress.isScanning;
  String? get message => _progress.message;

  Future<void> runScan(List<String> rootPaths) {
    return _maintainer.runScan(rootPaths);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
