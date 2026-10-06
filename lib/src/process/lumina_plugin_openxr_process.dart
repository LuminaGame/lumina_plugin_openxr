import 'dart:async';

import 'package:lumina_editor_api/lumina_editor_api.dart';

import '../lumina_plugin_openxr_plugin.dart';
import 'openxr_status_view.dart';

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
/// Shell calls (`PluginProcessChannel.call`): `status` answers the same
/// JSON as the `get_status` MCP tool.
class LuminaPluginOpenxrProcess extends PluginProcessAdapter {
  LuminaPluginOpenxrProcess([LuminaPluginOpenxrPlugin? plugin]) : super(plugin ?? LuminaPluginOpenxrPlugin());

  LuminaPluginOpenxrPlugin get openxr => plugin as LuminaPluginOpenxrPlugin;

  PluginProcessContext? _process;
  void Function()? _detach;
  bool _ownsCrashHandler = false;

  @override
  FutureOr<void> register(PluginProcessContext context) {
    _process = context;
    // In its own process nothing reports the plugin's caught native errors
    // yet: send them to the editor's log. Inside the editor (the debugging
    // override) the editor's crash reporter stays in charge.
    if (!LuminaPluginCrashReporter.hasHandler) {
      _ownsCrashHandler = true;
      LuminaPluginCrashReporter.setHandler((error, stack, {required plugin, context}) {
        final where = context == null || context.isEmpty ? '' : ' while $context';
        _process?.log('$plugin error$where: $error${stack == null ? '' : '\n$stack'}', level: 'error');
      });
    }
    super.register(context);
    context.registerViewPanel(OpenXrStatusView.panel(openxr));
    context.handle('status', (_) => openxr.statusJson());

    // Keep the panel current when a menu command, the status button's menu
    // or an MCP client changes the state.
    void push() {
      final view = context is ConnectedPluginProcessContext ? context.views[OpenXrStatusView.viewId] : null;
      if (view != null) OpenXrStatusView.refresh(openxr, view);
    }

    openxr.changes.addListener(push);
    _detach = () => openxr.changes.removeListener(push);
  }

  @override
  Future<void> onShutdown() async {
    _detach?.call();
    _detach = null;
    try {
      await super.onShutdown();
    } finally {
      if (_ownsCrashHandler) {
        LuminaPluginCrashReporter.setHandler(null);
        _ownsCrashHandler = false;
      }
      _process = null;
    }
  }
}
