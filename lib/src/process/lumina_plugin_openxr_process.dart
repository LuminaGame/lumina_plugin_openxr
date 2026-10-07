import 'dart:async';

import 'package:lumina_plugin_process/lumina_plugin_process.dart';

import 'package:lumina_plugin_openxr/src/process/openxr_controller.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_status_view.dart';

/// The OpenXR plugin's own process (`.lmplugin` `process_class`): the OpenXR
/// loader bridge (FFI), the session and every runtime query live in this
/// process, driven by an [OpenXrController]. A crash or hang in the OpenXR
/// runtime ends this process only; the editor marks the plugin stopped and
/// offers Restart.
///
/// It contributes the Plugins/OpenXR menu items, the status bar button with
/// its live state and menu, the `get_status` MCP tool and the OpenXR panel
/// as a declarative view ([OpenXrStatusView]), which the commands that would
/// open a dialog show, and keeps the panel current when the runtime, the
/// settings or the VR preview change.
///
/// Channel calls (`PluginProcessChannel.call`): `status` answers the same
/// JSON as the `get_status` MCP tool. The plugin has no in-editor shell (its
/// module names no `registration_class`). Caught native errors reported
/// through `LuminaPluginCrashReporter` reach the editor's log through the
/// plugin process runtime.
class LuminaPluginOpenxrProcess extends LuminaPluginProcess {
  LuminaPluginOpenxrProcess([OpenXrController? controller]) : openxr = controller ?? OpenXrController();

  final OpenXrController openxr;

  void Function()? _detach;

  @override
  String get pluginName => OpenXrController.pluginName;

  @override
  FutureOr<void> register(PluginProcessContext context) {
    openxr.log = (message, level) => context.level.log(message, level: level, source: 'OpenXR');
    openxr.refreshStatus();

    void showPanel() => unawaited(context
        .showPanel(OpenXrController.panelId)
        .catchError((Object e) => context.log('show ${OpenXrController.panelId} failed: $e', level: 'error')));
    final checkRuntime = PluginProcessCommand(
      id: 'tools.lumina_plugin_openxr.checkRuntime',
      label: 'Check OpenXR Runtime',
      icon: OpenXrController.searchIcon,
      canExecute: () => true,
      run: showPanel,
    );
    final togglePreview = PluginProcessCommand(
      id: 'tools.lumina_plugin_openxr.togglePreview',
      label: 'Toggle VR Preview',
      icon: OpenXrController.glassesIcon,
      canExecute: () => true,
      run: openxr.toggleVrPreview,
    );
    final settings = PluginProcessCommand(
      id: 'tools.lumina_plugin_openxr.settings',
      label: 'OpenXR Settings',
      icon: OpenXrController.settingsIcon,
      canExecute: () => true,
      run: showPanel,
    );

    context.registerMenuItem('Plugins/OpenXR/Check Runtime', checkRuntime, section: 'status');
    context.registerMenuItem('Plugins/OpenXR/Toggle VR Preview', togglePreview,
        section: 'run', checked: openxr.vrPreview);
    context.registerMenuItem('Plugins/OpenXR/OpenXR Settings', settings, section: 'settings');
    context.registerMenuItem(
      'Plugins/OpenXR/About ${OpenXrController.friendlyName}',
      PluginProcessCommand(
        id: 'tools.lumina_plugin_openxr.about',
        label: 'About ${OpenXrController.friendlyName}',
        canExecute: () => true,
        run: showPanel,
      ),
      section: 'about',
    );

    // Status bar button: live runtime / preview state, a menu on click.
    context.registerSlotButton(PluginProcessSlotButton(
      id: 'openxr.status_badge',
      slot: 'statusBarRight',
      state: openxr.statusButtonState,
      command: PluginProcessCommand(
        id: 'tools.lumina_plugin_openxr.statusBadgeClick',
        label: 'OpenXR Status',
        canExecute: () => true,
        run: showPanel,
      ),
      menu: [
        PluginProcessCommand(
          id: 'tools.lumina_plugin_openxr.statusMenu.checkRuntime',
          label: 'Check OpenXR Runtime',
          icon: OpenXrController.searchIcon,
          canExecute: () => true,
          run: showPanel,
        ),
        PluginProcessCommand(
          id: 'tools.lumina_plugin_openxr.statusMenu.togglePreview',
          label: 'Toggle VR Preview',
          icon: OpenXrController.glassesIcon,
          canExecute: () => true,
          run: openxr.toggleVrPreview,
        ),
        PluginProcessCommand(
          id: 'tools.lumina_plugin_openxr.statusMenu.settings',
          label: 'OpenXR Settings',
          icon: OpenXrController.settingsIcon,
          canExecute: () => true,
          run: showPanel,
        ),
      ],
    ));

    // MCP tool for AI agents.
    context.registerMcpTool(openxr.statusTool);

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
    openxr.shutdown();
  }
}
