import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StandardMethodCodec,
  Log
} from '@ohos/flutter_ohos';
import common from '@ohos.app.ability.common';

const TAG = 'PathProviderPlugin';
const CHANNEL_NAME = 'plugins.flutter.io/path_provider';

export default class PathProviderPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private appContext: common.Context | null = null;

  getUniqueClassName(): string {
    return 'PathProviderPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.appContext = binding.getApplicationContext();
    const messenger = binding.getBinaryMessenger();
    this.channel = new MethodChannel(messenger, CHANNEL_NAME, StandardMethodCodec.INSTANCE);
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.appContext = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (this.appContext == null) {
      result.error('NO_CONTEXT', 'Context is null', null);
      return;
    }
    const ctx = this.appContext!;

    switch (call.method) {
      case 'getTemporaryDirectory':
        result.success(ctx.tempDir);
        break;
      case 'getApplicationSupportDirectory':
        // Use filesDir as the application support directory
        result.success(ctx.filesDir);
        break;
      case 'getApplicationDocumentsDirectory':
        result.success(ctx.filesDir);
        break;
      case 'getApplicationCacheDirectory':
        result.success(ctx.cacheDir);
        break;
      case 'getLibraryDirectory':
        result.success(ctx.filesDir);
        break;
      case 'getStorageDirectory':
      case 'getExternalCacheDirectories':
      case 'getExternalStorageDirectories':
      case 'getDownloadsDirectory':
        // These are platform-specific (Android/macOS), return not implemented
        result.notImplemented();
        break;
      default:
        result.notImplemented();
    }
  }
}
