import 'dart:async';

import 'package:lumina_editor_api/lumina_editor_api.dart';

import 'package:lumina_plugin_openxr/src/lumina_plugin_openxr_plugin.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_status_view.dart';

/// The OpenXR plugin's own process (`.lmplugin` `process_class`): it runs
/// [LuminaPluginOpenxrPlugin] unchanged through [PluginProcessAdapter], so
/// the OpenXR loader bridge (FFI), the session and every runtime query live
/// in this process. A crash or hang in the OpenXR runtime ends this process
/// only; the editor marks the plugin stopped and offers Restart.
///
/// Next to the plugin's data contributions (menu items, the status bar
/// button with its live state and menu, the `get_status` MCP tool) it
/// registers the OpenXR panel as a declarative view ([OpenXrStatusView]),
/// which the menu commands open, and keeps it current when the runtime,
/// the settings or the VR preview change.
///
/// Channel calls (`PluginProcessChannel.call`): `status` answers the same
/// JSON as the `get_status` MCP tool. The plugin has no in-editor shell
/// (its module names no `registration_class`). Caught native errors the
/// plugin reports through `LuminaPluginCrashReporter` reach the editor's log
/// through the plugin process runtime.
class LuminaPluginOpenxrProcess extends PluginProcessAdapter {
  LuminaPluginOpenxrProcess([LuminaPluginOpenxrPlugin? plugin]) : super(plugin ?? LuminaPluginOpenxrPlugin());

  LuminaPluginOpenxrPlugin get openxr => plugin as LuminaPluginOpenxrPlugin;

  void Function()? _detach;

  @override
  FutureOr<void> register(PluginProcessContext context) {
    super.register(context);
    context.registerViewPanel(OpenXrStatusView.panel(openxr));
    context.handle('status', (_) => openxr.statusJson());

    // Keep the panel current when a menu command, the status button's menu
    // or an MCP client changes the state.
    void push() {
      final view = context.view(OpenXrStatusView.viewId);
      if (view != null) OpenXrStatusView.refresh(openxr, view);
    }

    openxr.changes.addListener(push);
    _detach = () => openxr.changes.removeListener(push);
  }

  @override
  Future<void> onShutdown() async {
    _detach?.call();
    _detach = null;
    await super.onShutdown();
  }
}
