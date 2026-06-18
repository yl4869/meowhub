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
import data_preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

const TAG = 'SharedPreferencesPlugin';
const CHANNEL_NAME = 'plugins.flutter.io/shared_preferences';
const STORE_NAME = 'flutter_shared_preferences';

export default class SharedPreferencesPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private prefs: data_preferences.Preferences | null = null;
  private appContext: common.Context | null = null;

  getUniqueClassName(): string {
    return 'SharedPreferencesPlugin';
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
    this.prefs = null;
    this.appContext = null;
  }

  private async getPrefs(): Promise<data_preferences.Preferences> {
    if (this.prefs != null) {
      return this.prefs;
    }
    if (this.appContext == null) {
      throw new Error('Context is null, plugin not attached');
    }
    this.prefs = await data_preferences.getPreferences(this.appContext, STORE_NAME);
    return this.prefs;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getAll':
        this.getAll(result);
        break;
      case 'getAllWithParameters':
        this.getAllWithParameters(call.args as Record<string, Object>, result);
        break;
      case 'setBool':
      case 'setInt':
      case 'setDouble':
      case 'setString':
      case 'setStringList':
        this.setValue(call.method, call.args as Record<string, Object>, result);
        break;
      case 'remove':
        this.remove(call.args as Record<string, Object>, result);
        break;
      case 'clear':
        this.clear(result);
        break;
      case 'clearWithParameters':
        this.clearWithParameters(call.args as Record<string, Object>, result);
        break;
      default:
        result.notImplemented();
    }
  }

  private async getAll(result: MethodResult): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const rawEntries = prefs.getAllSync() as Map<string, data_preferences.ValueType>;
      const allEntries = new Map<string, Object>();

      for (const key of rawEntries.keys()) {
        if (key.startsWith('_sp_type_')) {
          continue;
        }
        const value = rawEntries.get(key);
        if (value != undefined) {
          allEntries.set(key, value as Object);
        }
      }
      result.success(allEntries);
    } catch (e) {
      Log.e(TAG, 'getAll failed', e);
      result.error('GET_ALL_ERROR', 'Failed to get all preferences', null);
    }
  }

  private async getAllWithParameters(args: Record<string, Object>, result: MethodResult): Promise<void> {
    try {
      const prefix: string = (args['prefix'] as string) ?? '';
      const allowList: string[] | null = args['allowList'] as string[] | null;
      const prefs = await this.getPrefs();
      const rawEntries = prefs.getAllSync() as Map<string, data_preferences.ValueType>;

      const filtered = new Map<string, Object>();
      for (const key of rawEntries.keys()) {
        if (key.startsWith('_sp_type_')) {
          continue;
        }
        if (!key.startsWith(prefix)) {
          continue;
        }
        if (allowList != null && !allowList.includes(key)) {
          continue;
        }
        const value = rawEntries.get(key);
        if (value != undefined) {
          filtered.set(key, value as Object);
        }
      }
      result.success(filtered);
    } catch (e) {
      Log.e(TAG, 'getAllWithParameters failed', e);
      result.error('GET_ALL_ERROR', 'Failed to get all preferences', null);
    }
  }

  private async setValue(method: string, args: Record<string, Object>, result: MethodResult): Promise<void> {
    try {
      const key: string = args['key'] as string;
      const value: Object = args['value'] as Object;
      const prefs = await this.getPrefs();

      switch (method) {
        case 'setBool':
          await prefs.put(key, value as boolean);
          break;
        case 'setInt':
          await prefs.put(key, value as number);
          break;
        case 'setDouble':
          await prefs.put(key, value as number);
          break;
        case 'setString':
          await prefs.put(key, value as string);
          break;
        case 'setStringList':
          // HarmonyOS preferences API supports Array<string> natively
          await prefs.put(key, value as string[]);
          // Store type marker so we know how to interpret on read
          await prefs.put('_sp_type_' + key, 'StringList');
          break;
        default:
          result.error('UNKNOWN_METHOD', 'Unknown method: ' + method, null);
          return;
      }
      await prefs.flush();
      result.success(true);
    } catch (e) {
      Log.e(TAG, 'setValue failed: ' + method, e);
      result.error('SET_VALUE_ERROR', 'Failed to set value', null);
    }
  }

  private async remove(args: Record<string, Object>, result: MethodResult): Promise<void> {
    try {
      const key: string = args['key'] as string;
      const prefs = await this.getPrefs();
      await prefs.delete(key);
      await prefs.delete('_sp_type_' + key);
      await prefs.flush();
      result.success(true);
    } catch (e) {
      Log.e(TAG, 'remove failed', e);
      result.error('REMOVE_ERROR', 'Failed to remove preference', null);
    }
  }

  private async clear(result: MethodResult): Promise<void> {
    try {
      const prefs = await this.getPrefs();
      const allEntries = prefs.getAllSync() as Map<string, data_preferences.ValueType>;
      // Delete all flutter-prefixed keys and type markers
      for (const key of allEntries.keys()) {
        if (key.startsWith('flutter.') || key.startsWith('_sp_type_')) {
          await prefs.delete(key);
        }
      }
      await prefs.flush();
      result.success(true);
    } catch (e) {
      Log.e(TAG, 'clear failed', e);
      result.error('CLEAR_ERROR', 'Failed to clear preferences', null);
    }
  }

  private async clearWithParameters(args: Record<string, Object>, result: MethodResult): Promise<void> {
    try {
      const prefix: string = (args['prefix'] as string) ?? '';
      const allowList: string[] | null = args['allowList'] as string[] | null;
      const prefs = await this.getPrefs();
      const allEntries = prefs.getAllSync() as Map<string, data_preferences.ValueType>;

      for (const key of allEntries.keys()) {
        if (!key.startsWith(prefix)) {
          continue;
        }
        if (allowList != null && !allowList.includes(key)) {
          continue;
        }
        await prefs.delete(key);
        await prefs.delete('_sp_type_' + key);
      }
      await prefs.flush();
      result.success(true);
    } catch (e) {
      Log.e(TAG, 'clearWithParameters failed', e);
      result.error('CLEAR_ERROR', 'Failed to clear preferences', null);
    }
  }
}
