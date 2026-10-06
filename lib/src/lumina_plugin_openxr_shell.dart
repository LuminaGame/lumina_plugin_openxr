import 'package:lumina_editor_api/lumina_editor_api.dart';

/// The in-editor half of the OpenXR plugin (`.lmplugin`
/// `registration_class`). OpenXR runs in its own process
/// ([LuminaPluginOpenxrProcess]): the menu items, the status bar button,
/// the OpenXR panel and the MCP tool all come from there, so this shell
/// registers nothing, never opens the OpenXR loader bridge and never
/// creates an [OpenXrBindings] instance.
///
/// [channel] is the line to the process (`status` answers the runtime and
/// session state as JSON) for editor code that needs it.
class LuminaPluginOpenxrShell extends LuminaEditorPlugin {
  PluginProcessChannel? _channel;

  @override
  String get pluginName => 'lumina_plugin_openxr';

  /// The channel to the plugin process, once registered.
  PluginProcessChannel? get channel => _channel;

  @override
  void register(LuminaEditorContext context) {
    _channel = context.processChannel(pluginName);
  }

  @override
  void unregister(LuminaEditorContext context) {
    _channel = null;
  }
}
