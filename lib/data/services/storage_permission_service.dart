import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class StoragePermissionService {
  const StoragePermissionService._();

  /// Check if the app has sufficient storage access to scan local media files.
  static Future<bool> hasFullStorageAccess() async {
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;

    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;

    final videos = await Permission.videos.status;
    final photos = await Permission.photos.status;
    return videos.isGranted && photos.isGranted;
  }

  /// Request storage permissions appropriate for the current Android version.
  ///
  /// On Android 11+ this opens the system "All files access" settings page.
  /// Returns `true` if permissions were granted.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // MANAGE_EXTERNAL_STORAGE gives the broadest access (all files, USB drives).
    // On API 30+ it opens system settings; on API <30 it auto-grants.
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    // Fallback: granular media permissions (API 33+), auto-grants on API <33
    final videos = await Permission.videos.request();
    final photos = await Permission.photos.request();
    if (videos.isGranted && photos.isGranted) return true;

    // Last fallback: legacy storage permission (API <33)
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }
}
