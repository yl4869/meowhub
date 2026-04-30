import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../../domain/repositories/i_permission_service.dart';

class StoragePermissionService implements IPermissionService {
  const StoragePermissionService();

  @override
  Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;

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
    if (!Platform.isAndroid) return true;

    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;

    final videos = await Permission.videos.request();
    final photos = await Permission.photos.request();
    if (videos.isGranted && photos.isGranted) return true;

    final storage = await Permission.storage.request();
    return storage.isGranted;
  }
}
