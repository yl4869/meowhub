abstract class IPermissionService {
  Future<bool> hasStorageAccess();
  Future<bool> requestStoragePermission();
}
