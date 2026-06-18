
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import SharedPreferencesPlugin from '../plugins/SharedPreferencesPlugin';
import PathProviderPlugin from '../plugins/PathProviderPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Manually register ohos platform plugins that don't have pub.dev ohos support yet.
    flutterEngine.getPlugins()?.add(new SharedPreferencesPlugin());
    flutterEngine.getPlugins()?.add(new PathProviderPlugin());
  }
}
