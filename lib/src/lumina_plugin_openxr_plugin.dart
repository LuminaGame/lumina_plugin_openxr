import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_controller.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_filament_bridge.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_session.dart';
import 'package:lumina_plugin_openxr/src/ui/openxr_dialogs.dart';

/// Khronos OpenXR plugin for Lumina Studio, as an in-process
/// [LuminaEditorPlugin] over the pure [OpenXrController].
///
/// In Lumina Studio the plugin runs in its own process through
/// `LuminaPluginOpenxrProcess` (every OpenXR loader call happens there); this
/// class serves a Flutter host that loads it in process, with dialogs.
/// Commands that run without a `BuildContext` open the OpenXR panel instead
/// of a dialog.
class LuminaPluginOpenxrPlugin extends LuminaEditorPlugin {
  LuminaPluginOpenxrPlugin([OpenXrController? controller]) : controller = controller ?? OpenXrController() {
    filamentBridge = OpenXrFilamentBridge();
    _status = ValueNotifier(_buttonStateOf(this.controller.statusButtonState.value));
    this.controller.changes.addListener(_mirror);
  }

  static const String friendlyName = OpenXrController.friendlyName;
  static const String version = OpenXrController.version;

  /// The OpenXR panel the plugin process registers
  /// (`PluginProcessViewPanel`); commands run without a `BuildContext` show it.
  static const String panelId = OpenXrController.panelId;

  /// The About text, shown in the About dialog and the OpenXR panel.
  static const String aboutText = OpenXrController.aboutText;

  /// The plugin's state and actions.
  final OpenXrController controller;
  late final OpenXrFilamentBridge filamentBridge;

  final ValueNotifier<bool> _previewActive = ValueNotifier(false);
  late final ValueNotifier<EditorButtonState> _status;
  final ValueNotifier<int> _revision = ValueNotifier(0);
  LuminaEditorContext? _context;

  OpenXrBindings get bindings => controller.bindings;
  OpenXrSession get session => controller.session;

  @override
  String get pluginName => OpenXrController.pluginName;

  bool get isVrPreviewActive => controller.isVrPreviewActive;

  /// Whether the VR preview runs; the Toggle VR Preview menu item's check mark.
  ValueListenable<bool> get vrPreview => _previewActive;

  /// What the status bar button shows: the active runtime, simulated or
  /// native, and whether the VR preview runs.
  ValueListenable<EditorButtonState> get statusButtonState => _status;

  /// Fires whenever the runtime choice, the tracking origin, the stereo mode
  /// or the VR preview changes.
  Listenable get changes => _revision;

  /// The stereo rendering mode chosen in the settings.
  OpenXrStereoMode get stereoMode => controller.stereoMode;

  set stereoMode(OpenXrStereoMode mode) => controller.stereoMode = mode;

  /// Forces the simulated runtime (or goes back to the native one).
  void setForceSimulation(bool force) => controller.setForceSimulation(force);

  /// Moves the tracking space to [origin].
  void setTrackingOrigin(OpenXrTrackingOrigin origin) => controller.setTrackingOrigin(origin);

  /// Starts or stops the VR preview session; returns whether it runs now.
  bool toggleVrPreview() => controller.toggleVrPreview();

  /// Re-reads the runtime and updates the status button and [changes].
  void refreshStatus() => controller.refreshStatus();

  /// The runtime and session status as JSON (the `get_status` MCP tool).
  Map<String, Object?> statusJson() => controller.statusJson();

  void _mirror() {
    _previewActive.value = controller.isVrPreviewActive;
    _status.value = _buttonStateOf(controller.statusButtonState.value);
    _revision.value++;
  }

  static EditorButtonState _buttonStateOf(PluginButtonStateSpec s) => EditorButtonState(
        label: s.label,
        tooltip: s.tooltip,
        icon: LucideIcons.glasses,
        tone: EditorTone.values.byName(s.tone),
        active: s.active,
        badge: s.badge,
      );

  /// Shows the runtime diagnostic: a dialog with a [ctx], else the OpenXR panel.
  void _showDiagnostic(BuildContext? ctx) {
    if (ctx == null) {
      _context?.panels.show(panelId);
      return;
    }
    showOpenXrMessageDialog(ctx,
        title: 'OpenXR Runtime Diagnostic', message: controller.diagnosticText, closeLabel: 'OK');
  }

  void _showSettings(BuildContext? ctx) {
    if (ctx == null) {
      _context?.panels.show(panelId);
      return;
    }
    showOpenXrSettingsDialog(ctx, plugin: this);
  }

  void _showAbout(BuildContext? ctx) {
    if (ctx == null) {
      _context?.panels.show(panelId);
      return;
    }
    showOpenXrMessageDialog(ctx, title: friendlyName, message: aboutText, closeLabel: 'Close');
  }

  EditorCommand get _checkRuntimeCommand => EditorCommand(
        id: 'tools.lumina_plugin_openxr.checkRuntime',
        label: 'Check OpenXR Runtime',
        icon: LucideIcons.search,
        canExecute: () => true,
        execute: _showDiagnostic,
      );

  EditorCommand get _togglePreviewCommand => EditorCommand(
        id: 'tools.lumina_plugin_openxr.togglePreview',
        label: 'Toggle VR Preview',
        icon: LucideIcons.glasses,
        canExecute: () => true,
        execute: (_) => toggleVrPreview(),
      );

  EditorCommand get _settingsCommand => EditorCommand(
        id: 'tools.lumina_plugin_openxr.settings',
        label: 'OpenXR Settings',
        icon: LucideIcons.settings,
        canExecute: () => true,
        execute: _showSettings,
      );

  @override
  void register(LuminaEditorContext context) {
    _context = context;
    final level = context is LuminaEditorHostContext ? context.level : null;
    controller.log = level == null ? null : (message, lvl) => level.log(message, level: lvl, source: 'OpenXR');
    refreshStatus();

    context.registerMenuItem('Plugins/OpenXR/Check Runtime', _checkRuntimeCommand,
        options: const EditorMenuItemOptions(section: 'status'));

    context.registerMenuItem('Plugins/OpenXR/Toggle VR Preview', _togglePreviewCommand,
        options: EditorMenuItemOptions(section: 'run', checked: _previewActive));

    context.registerMenuItem('Plugins/OpenXR/OpenXR Settings', _settingsCommand,
        options: const EditorMenuItemOptions(section: 'settings'));

    context.registerMenuItem(
      'Plugins/OpenXR/About $friendlyName',
      EditorCommand(
        id: 'tools.lumina_plugin_openxr.about',
        label: 'About $friendlyName',
        canExecute: () => true,
        execute: _showAbout,
      ),
      options: const EditorMenuItemOptions(section: 'about'),
    );

    // Status bar button: live runtime / preview state, a menu on click.
    context.registerSlotButton(
      EditorSlotButton(
        id: 'openxr.status_badge',
        slot: EditorSlot.statusBarRight,
        state: _status,
        command: EditorCommand(
          id: 'tools.lumina_plugin_openxr.statusBadgeClick',
          label: 'OpenXR Status',
          canExecute: () => true,
          execute: _showDiagnostic,
        ),
        menu: [
          EditorCommand(
            id: 'tools.lumina_plugin_openxr.statusMenu.checkRuntime',
            label: 'Check OpenXR Runtime',
            icon: LucideIcons.search,
            canExecute: () => true,
            execute: _showDiagnostic,
          ),
          EditorCommand(
            id: 'tools.lumina_plugin_openxr.statusMenu.togglePreview',
            label: 'Toggle VR Preview',
            icon: LucideIcons.glasses,
            canExecute: () => true,
            execute: (_) => toggleVrPreview(),
          ),
          EditorCommand(
            id: 'tools.lumina_plugin_openxr.statusMenu.settings',
            label: 'OpenXR Settings',
            icon: LucideIcons.settings,
            canExecute: () => true,
            execute: _showSettings,
          ),
        ],
      ),
    );

    // MCP tool for AI agents.
    context.mcp.registerTool(controller.statusTool);
  }

  @override
  void unregister(LuminaEditorContext context) {
    controller.shutdown();
    _previewActive.value = false;
    _context = null;
  }
}
