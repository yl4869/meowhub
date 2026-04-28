import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Data returned from a single native `scanTree` call.
class AndroidSafScanResult {
  const AndroidSafScanResult({required this.files, required this.totalFound});

  final List<AndroidSafFileEntry> files;
  final int totalFound;
}

/// Per-file entry returned by the native SAF scanner.
class AndroidSafFileEntry {
  const AndroidSafFileEntry({
    required this.uri,
    required this.name,
    required this.size,
    required this.mtime,
    required this.parentUri,
    this.nfoContent,
    this.posterUri,
    this.backdropUri,
    this.dirHasTvshowNfo = false,
    this.seasonFolderName,
  });

  final String uri; // content:// document URI
  final String name;
  final int size;
  final int mtime;
  final String parentUri;
  final String? nfoContent; // NFO file content read by native side
  final String? posterUri;
  final String? backdropUri;
  final bool dirHasTvshowNfo;
  final String? seasonFolderName;
}

/// Minimal platform-channel wrapper for Android SAF operations.
///
/// Delegates heavy I/O (tree walk, NFO reading, image discovery) to the native
/// [SafService] so the Dart side only does pure computation (filename parsing,
/// NFO XML parsing, folder grouping, series detection).
class AndroidSafService {
  AndroidSafService() {
    if (Platform.isAndroid) {
      _channel.setMethodCallHandler(_onMethodCall);
    }
  }

  static const _channel = MethodChannel('com.example.meowhub/saf');

  static const defaultVideoExtensions = {
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.m4v',
  };

  /// Scan an entire SAF document tree in a single platform-channel call.
  ///
  /// The native side recursively walks the tree, collects every video file,
  /// and for each video checks the parent directory for companion files
  /// (NFO, poster, backdrop, tvshow.nfo).
  Future<AndroidSafScanResult> scanTree(
    String treeUri, {
    Set<String> videoExtensions = defaultVideoExtensions,
  }) async {
    if (!Platform.isAndroid) {
      return const AndroidSafScanResult(files: [], totalFound: 0);
    }
    final result = await _channel.invokeMethod('scanTree', {
      'treeUri': treeUri,
      'videoExtensions': videoExtensions.toList(),
    });
    final map = result as Map<dynamic, dynamic>;
    final rawFiles = (map['files'] as List<dynamic>?) ?? [];
    final files = rawFiles.map((f) {
      final m = f as Map<dynamic, dynamic>;
      return AndroidSafFileEntry(
        uri: m['uri'] as String,
        name: m['name'] as String,
        size: m['size'] as int,
        mtime: m['mtime'] as int,
        parentUri: m['parentUri'] as String,
        nfoContent: m['nfoContent'] as String?,
        posterUri: m['posterUri'] as String?,
        backdropUri: m['backdropUri'] as String?,
        dirHasTvshowNfo: (m['dirHasTvshowNfo'] as bool?) ?? false,
        seasonFolderName: m['seasonFolderName'] as String?,
      );
    }).toList();
    return AndroidSafScanResult(
      files: files,
      totalFound: (map['totalFound'] as int?) ?? files.length,
    );
  }

  /// Generate a video thumbnail via Android MediaMetadataRetriever.
  ///
  /// Returns [outputPath] on success, `null` on failure.
  Future<String?> generateThumbnail(
    String contentUri,
    String outputPath,
  ) async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMethod('generateThumbnail', {
        'uri': contentUri,
        'outputPath': outputPath,
      });
      return result as String?;
    } catch (e) {
      debugPrint('[SAF] generateThumbnail failed: $e');
      return null;
    }
  }

  /// Check whether [path] is a content:// URI.
  static bool isContentUri(String path) => path.startsWith('content://');

  /// Extract the parent folder URI from a content:// document URI.
  ///
  /// SAF document URIs encode path segments with %2F as separator.
  /// e.g. `content://...tree/document/primary%3AMovies%2Fvideo.mp4`
  /// parent: `content://...tree/document/primary%3AMovies`
  static String parentUriFromDocumentUri(String docUri) {
    final idx = docUri.lastIndexOf('%2F');
    if (idx >= 0) return docUri.substring(0, idx);
    final lastPlain = docUri.lastIndexOf('/');
    return lastPlain > 0 ? docUri.substring(0, lastPlain) : docUri;
  }

  // No incoming method calls expected.
  Future<dynamic> _onMethodCall(MethodCall call) async {
    throw UnimplementedError('${call.method} is not implemented');
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
