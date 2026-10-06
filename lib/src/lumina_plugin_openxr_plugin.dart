import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'ffi/openxr_bindings.dart';
import 'ffi/openxr_types.dart';
import 'render/openxr_filament_bridge.dart';
import 'session/openxr_session.dart';
import 'ui/openxr_dialogs.dart';

/// Khronos OpenXR plugin for Lumina Studio.
///
/// Its contributions are data (menu items, a status bar slot button with a
/// menu, an MCP tool), so in Lumina Studio it runs in its own process
/// through [LuminaPluginOpenxrProcess]: every OpenXR loader call happens
/// there. Commands that run without a `BuildContext` (always the case in
/// the plugin process) open the declarative OpenXR panel instead of a
/// dialog.
class LuminaPluginOpenxrPlugin extends LuminaEditorPlugin {
  static const String friendlyName = 'OpenXR Support';
  static const String version = '0.1.0';

  /// The OpenXR panel the plugin process registers
  /// (`PluginProcessViewPanel`); commands run without a `BuildContext` show it.
  static const String panelId = 'panel.lumina_plugin_openxr.status';

  final OpenXrBindings bindings = OpenXrBindings.instance;
  late final OpenXrSession session;
  late final OpenXrFilamentBridge filamentBridge;

  final ValueNotifier<bool> _previewActive = ValueNotifier(false);
  late final ValueNotifier<EditorButtonState> _status = ValueNotifier(_statusOf());
  final ValueNotifier<int> _revision = ValueNotifier(0);
  OpenXrStereoMode _stereoMode = OpenXrStereoMode.instanced;
  EditorLevelAccess? _level;
  LuminaEditorContext? _context;

  LuminaPluginOpenxrPlugin() {
    session = OpenXrSession(bindings: bindings);
    filamentBridge = OpenXrFilamentBridge();
  }

  @override
  String get pluginName => 'lumina_plugin_openxr';

  bool get isVrPreviewActive => _previewActive.value;

  /// Whether the VR preview runs; the Toggle VR Preview menu item's check mark.
  ValueListenable<bool> get vrPreview => _previewActive;

  /// What the status bar button shows: the active runtime, simulated or
  /// native, and whether the VR preview runs.
  ValueListenable<EditorButtonState> get statusButtonState => _status;

  /// Fires whenever the runtime choice, the tracking origin, the stereo mode
  /// or the VR preview changes.
  Listenable get changes => _revision;

  /// The stereo rendering mode chosen in the settings.
  OpenXrStereoMode get stereoMode => _stereoMode;

  set stereoMode(OpenXrStereoMode mode) {
    if (mode == _stereoMode) return;
    _stereoMode = mode;
    refreshStatus();
  }

  /// Forces the simulated runtime (or goes back to the native one).
  void setForceSimulation(bool force) {
    bindings.setForceSimulation(force);
    refreshStatus();
  }

  /// Moves the tracking space to [origin].
  void setTrackingOrigin(OpenXrTrackingOrigin origin) {
    session.setTrackingOrigin(origin);
    refreshStatus();
  }

  /// Starts or stops the VR preview session; returns whether it runs now.
  bool toggleVrPreview() {
    try {
      if (_previewActive.value) {
        session.endSession();
        _previewActive.value = false;
      } else {
        final result = session.beginSession();
        _previewActive.value = result.isSuccess;
        if (result.isFailure) {
          _level?.log('VR Preview could not start: ${result.name} (${bindings.activeRuntimeName})',
              level: 'error', source: 'OpenXR');
        }
      }
      _level?.log('VR Preview ${_previewActive.value ? "started" : "stopped"} (${bindings.activeRuntimeName})',
          level: 'info', source: 'OpenXR');
    } catch (e, stack) {
      reportCrash(e, stack, context: 'Toggle VR Preview');
    }
    refreshStatus();
    return _previewActive.value;
  }

  /// Re-reads the runtime and updates the status button and [changes].
  void refreshStatus() {
    _status.value = _statusOf();
    _revision.value++;
  }

  EditorButtonState _statusOf() {
    final simulated = bindings.isSimulated;
    final name = bindings.activeRuntimeName;
    final preview = _previewActive.value;
    return EditorButtonState(
      label: simulated ? 'XR (Sim)' : 'XR: $name',
      tooltip: 'OpenXR runtime: $name${simulated ? ' (simulated)' : ''}'
          '${preview ? ' · VR Preview running' : ''}',
      icon: LucideIcons.glasses,
      tone: preview ? EditorTone.success : (simulated ? EditorTone.neutral : EditorTone.primary),
      active: preview,
      badge: preview ? '●' : null,
    );
  }

  /// Shows the runtime diagnostic: a dialog with a [ctx], else the OpenXR panel.
  void _showDiagnostic(BuildContext? ctx) {
    if (ctx == null) {
      _context?.panels.show(panelId);
      return;
    }
    final status = bindings.isNativeRuntimeAvailable
        ? 'Active Native Runtime: ${bindings.activeRuntimeName}\nPath: ${bindings.activeRuntimePath}'
        : 'No physical OpenXR runtime active. Using internal Simulated HMD backend for development.';
    showOpenXrMessageDialog(ctx, title: 'OpenXR Runtime Diagnostic', message: status, closeLabel: 'OK');
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

  /// The About text, shown in the About dialog and the OpenXR panel.
  static const String aboutText = 'Khronos OpenXR 1.0/1.1 runtime management, stereoscopic rendering bridge for '
      'Filament, and XR origin/controller tracking components.\nVersion: $version';

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
    if (context is LuminaEditorHostContext) {
      _level = context.level;
    }
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
    context.mcp.registerTool(
      McpTool(
        name: 'get_status',
        description: 'Returns OpenXR runtime diagnostic details and tracking session status.',
        inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
        risk: McpToolRisk.readOnly,
        groups: const {McpToolGroups.plugin},
        handler: (args) async => McpToolResult.json(statusJson()),
      ),
    );
  }

  /// The runtime and session status as JSON (the `get_status` MCP tool).
  Map<String, Object?> statusJson() => {
        'active_runtime': bindings.activeRuntimeName,
        'manifest_path': bindings.activeRuntimePath,
        'is_simulated': bindings.isSimulated,
        'native_runtime_available': bindings.isNativeRuntimeAvailable,
        'session_state': session.state.name,
        'tracking_origin': session.trackingOrigin.name,
        'stereo_mode': _stereoMode.name,
        'vr_preview_active': _previewActive.value,
      };

  @override
  void unregister(LuminaEditorContext context) {
    session.endSession();
    _previewActive.value = false;
    _level = null;
    _context = null;
  }
}
