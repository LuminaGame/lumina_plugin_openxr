import 'package:lumina_plugin_process/lumina_plugin_process.dart';

import 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_session.dart';

/// Writes a line to the editor's Output Log (`level`: info, warning, error).
typedef OpenXrLog = void Function(String message, String level);

/// The OpenXR plugin's state and actions, in pure Dart: the runtime choice,
/// the tracking origin, the stereo mode, the VR preview session, the status
/// button state and the `get_status` JSON.
///
/// `LuminaPluginOpenxrProcess` serves it to the editor; the in-process
/// `LuminaPluginOpenxrPlugin` wraps it for a Flutter host.
class OpenXrController {
  OpenXrController({OpenXrBindings? bindings}) : bindings = bindings ?? OpenXrBindings.instance {
    session = OpenXrSession(bindings: this.bindings);
    statusButtonState = ObservableValue(_statusOf());
  }

  /// The plugin's name (crash reports and MCP tools carry it).
  static const String pluginName = 'lumina_plugin_openxr';
  static const String friendlyName = 'OpenXR Support';
  static const String version = '0.1.0';

  /// The OpenXR panel (`PluginProcessViewPanel`); commands that would open a
  /// dialog show it.
  static const String panelId = 'panel.lumina_plugin_openxr.status';

  /// The About text, shown in the About dialog and the OpenXR panel.
  static const String aboutText = 'Khronos OpenXR 1.0/1.1 runtime management, stereoscopic rendering bridge for '
      'Filament, and XR origin/controller tracking components.\nVersion: $version';

  /// Lucide icons as protocol data (the editor maps them back to its
  /// bundled constants).
  static const PluginIconSpec glassesIcon = PluginIconSpec(57868, fontFamily: 'LucideIcons', fontPackage: 'shadcn_flutter');
  static const PluginIconSpec searchIcon = PluginIconSpec(57684, fontFamily: 'LucideIcons', fontPackage: 'shadcn_flutter');
  static const PluginIconSpec settingsIcon =
      PluginIconSpec(57687, fontFamily: 'LucideIcons', fontPackage: 'shadcn_flutter');

  final OpenXrBindings bindings;
  late final OpenXrSession session;

  /// Where [toggleVrPreview] logs; null logs nothing.
  OpenXrLog? log;

  final ObservableValue<bool> _previewActive = ObservableValue(false);
  final ChangeEmitter _changes = ChangeEmitter();
  OpenXrStereoMode _stereoMode = OpenXrStereoMode.instanced;

  /// What the status bar button shows: the active runtime, simulated or
  /// native, and whether the VR preview runs.
  late final ObservableValue<PluginButtonStateSpec> statusButtonState;

  bool get isVrPreviewActive => _previewActive.value;

  /// Whether the VR preview runs; the Toggle VR Preview menu item's check mark.
  Observable<bool> get vrPreview => _previewActive;

  /// Fires whenever the runtime choice, the tracking origin, the stereo mode
  /// or the VR preview changes.
  ChangeSignal get changes => _changes;

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
          log?.call('VR Preview could not start: ${result.name} (${bindings.activeRuntimeName})', 'error');
        }
      }
      log?.call('VR Preview ${_previewActive.value ? "started" : "stopped"} (${bindings.activeRuntimeName})', 'info');
    } catch (e, stack) {
      LuminaPluginCrashReporter.reportCrash(e, stack, plugin: pluginName, context: 'Toggle VR Preview');
    }
    refreshStatus();
    return _previewActive.value;
  }

  /// Ends the VR preview session (the plugin is unloading).
  void shutdown() {
    session.endSession();
    _previewActive.value = false;
    log = null;
  }

  /// Re-reads the runtime and updates the status button and [changes].
  void refreshStatus() {
    statusButtonState.value = _statusOf();
    _changes.notifyListeners();
  }

  /// The diagnostic text of the Check Runtime dialog.
  String get diagnosticText => bindings.isNativeRuntimeAvailable
      ? 'Active Native Runtime: ${bindings.activeRuntimeName}\nPath: ${bindings.activeRuntimePath}'
      : 'No physical OpenXR runtime active. Using internal Simulated HMD backend for development.';

  PluginButtonStateSpec _statusOf() {
    final simulated = bindings.isSimulated;
    final name = bindings.activeRuntimeName;
    final preview = _previewActive.value;
    return PluginButtonStateSpec(
      label: simulated ? 'XR (Sim)' : 'XR: $name',
      tooltip: 'OpenXR runtime: $name${simulated ? ' (simulated)' : ''}'
          '${preview ? ' · VR Preview running' : ''}',
      icon: glassesIcon,
      tone: preview ? 'success' : (simulated ? 'neutral' : 'primary'),
      active: preview,
      badge: preview ? '●' : null,
    );
  }

  /// The `get_status` MCP tool, answering [statusJson].
  McpTool get statusTool => McpTool(
        name: 'get_status',
        description: 'Returns OpenXR runtime diagnostic details and tracking session status.',
        inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
        risk: McpToolRisk.readOnly,
        groups: const {McpToolGroups.plugin},
        handler: (args) async => McpToolResult.json(statusJson()),
      );

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
}
