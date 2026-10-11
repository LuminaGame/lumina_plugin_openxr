import 'dart:async';

import 'package:lumina_plugin_process/lumina_plugin_process.dart';

import 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_controller.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_panel.dart';

/// The OpenXR plugin's own process (`.lmplugin` `process_class`): the OpenXR
/// loader bridge (FFI), the session and every runtime query live in this
/// process, driven by an [OpenXrController]. A crash or hang in the OpenXR
/// runtime ends this process only; the editor marks the plugin stopped and
/// offers Restart.
///
/// It contributes the Plugins/OpenXR menu items, the status bar button with
/// its live state and menu and the `get_status` MCP tool. The OpenXR panel
/// is the editor panel Widget Blueprint [OpenXrPanel.asset] the plugin ships
/// as content: the commands that would open a dialog open it, its graph
/// calls this process's methods, and every change (from the panel, a menu,
/// the status button's menu or an MCP client) reaches it as an
/// [OpenXrPanel.statusEvent] event and as patches of its status texts.
///
/// Channel calls (`PluginProcessChannel.call`), each answering `statusJson()`:
/// `status` (the same JSON as the `get_status` MCP tool),
/// `setForceSimulation {value: bool}`, `setTrackingOrigin {value: <origin>}`,
/// `setStereoMode {value: <mode>}` and `toggleVrPreview`; a bad value answers
/// `bad_arguments`. The plugin has no in-editor part (its module names no
/// `registration_class`). Caught native errors reported through
/// `LuminaPluginCrashReporter` reach the editor's log through the plugin
/// process runtime.
class LuminaPluginOpenxrProcess extends LuminaPluginProcess {
  LuminaPluginOpenxrProcess([OpenXrController? controller]) : openxr = controller ?? OpenXrController();

  final OpenXrController openxr;

  void Function()? _detach;

  @override
  String get pluginName => OpenXrController.pluginName;

  @override
  FutureOr<void> register(PluginProcessContext context) {
    // Failures at the native boundary reach the editor's crash reporter with the plugin named.
    OpenXrErrorReporter.handler = (error, stack, where) =>
        LuminaPluginCrashReporter.reportCrash(error, stack, plugin: OpenXrController.pluginName, context: where);
    openxr.log = (message, level) => context.level.log(message, level: level, source: 'OpenXR');
    openxr.refreshStatus();

    void showPanel() => unawaited(context
        .openEditorPanel(OpenXrPanel.asset)
        .catchError((Object e) => context.log('opening ${OpenXrPanel.asset} failed: $e', level: 'error')));
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

    _handle(context, 'status', (_) {});
    _handle(context, 'setForceSimulation', (args) => openxr.setForceSimulation(_value<bool>(args, 'a bool')));
    _handle(context, 'setTrackingOrigin',
        (args) => openxr.setTrackingOrigin(_named(args, OpenXrTrackingOrigin.values, (o) => o.name)));
    _handle(context, 'setStereoMode', (args) => openxr.stereoMode = _named(args, OpenXrStereoMode.values, (m) => m.name));
    _handle(context, 'toggleVrPreview', (_) => openxr.toggleVrPreview());

    // Keep an open panel current when the panel itself, a menu command, the
    // status button's menu or an MCP client changes the state.
    void push() {
      context.patchPanel(OpenXrPanel.asset, OpenXrPanel.statusOps(openxr));
      context.emit(OpenXrPanel.statusEvent, openxr.statusJson());
    }

    openxr.changes.addListener(push);
    _detach = () => openxr.changes.removeListener(push);
  }

  /// A channel method that applies [apply] and answers the status JSON.
  void _handle(PluginProcessContext context, String method, void Function(Map<String, Object?> args) apply) =>
      context.handle(method, (args) {
        apply(args);
        return openxr.statusJson();
      });

  static T _value<T>(Map<String, Object?> args, String what) {
    final v = args['value'];
    if (v is T) return v;
    throw PluginRemoteError(code: PluginErrorCodes.badArguments, message: '"value" must be $what, not ${v ?? 'missing'}');
  }

  static T _named<T>(Map<String, Object?> args, List<T> values, String Function(T) name) {
    final names = values.map(name).join(', ');
    final v = _value<String>(args, 'one of $names');
    return values.where((e) => name(e) == v).firstOrNull ??
        (throw PluginRemoteError(code: PluginErrorCodes.badArguments, message: '"value" must be one of $names, not $v'));
  }

  @override
  Future<void> onShutdown() async {
    _detach?.call();
    _detach = null;
    openxr.shutdown();
  }
}
