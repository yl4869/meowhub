import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../domain/repositories/i_permission_service.dart';

class StoragePermissionService implements IPermissionService {
  const StoragePermissionService();

  bool get _needsPermissionSystem =>
      Platform.isAndroid || Platform.operatingSystem == 'ohos';

  @override
  Future<bool> hasStorageAccess() async {
    if (!_needsPermissionSystem) return true;

    if (Platform.operatingSystem == 'ohos') {
      // HarmonyOS permission model: caller should use ohos.permission.READ_MEDIA
      // and ohos.permission.WRITE_MEDIA via the OHOS permission_handler adapter.
      // Returning true as a fallback — replace with actual OHOS permission check.
      return true;
    }

    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;

    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;

    final videos = await Permission.videos.status;
    final photos = await Permission.photos.status;
    return videos.isGranted && photos.isGranted;
  }

  @override
  Future<bool> requestStoragePermission() async {
    if (!_needsPermissionSystem) return true;

    if (Platform.operatingSystem == 'ohos') {
      // HarmonyOS: request ohos.permission.READ_MEDIA / WRITE_MEDIA.
      // Returning true as a fallback — replace with actual OHOS permission request.
      return true;
    }

    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    final videos = await Permission.videos.request();
    final photos = await Permission.photos.request();
    if (videos.isGranted && photos.isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }
}
