import 'package:lumina_plugin_process/lumina_plugin_process.dart';

import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/process/openxr_controller.dart';

/// The OpenXR panel: the editor panel Widget Blueprint the plugin ships as
/// content ([asset]), run by the editor's Blueprint VM. No Dart builds it;
/// this names what the process addresses in it and the texts it keeps
/// current there.
///
/// Its graph calls the process's `status`, `setForceSimulation`,
/// `setTrackingOrigin`, `setStereoMode` and `toggleVrPreview` methods and
/// listens to [statusEvent]; the process patches the status texts of every
/// open instance ([statusOps]) whenever the runtime, the settings or the VR
/// preview change.
abstract final class OpenXrPanel {
  /// The panel's asset path in the plugin: the address of
  /// `PluginProcessContext.patchPanel` and `openEditorPanel`. Renaming the
  /// asset changes it.
  static const String asset = 'content/Editor/EPW_OpenXR.lmas';

  /// The event carrying `statusJson()` after every change (the panel's
  /// `On Plugin Process Event`).
  static const String statusEvent = 'openxr.status';

  /// Element names in the panel.
  static const String runtimeName = 'RuntimeName';
  static const String manifestPath = 'ManifestPath';
  static const String runtimeKind = 'RuntimeKind';
  static const String forceSimulation = 'ForceSimulation';
  static const String trackingOrigin = 'TrackingOrigin';
  static const String stereoMode = 'StereoMode';
  static const String sessionState = 'SessionState';
  static const String togglePreview = 'TogglePreview';
  static const String about = 'About';

  /// The elements the process patches, each with its element type.
  static const Map<String, String> patchedElements = {
    runtimeName: 'text',
    manifestPath: 'text',
    runtimeKind: 'text',
    sessionState: 'text',
  };

  static String runtimeNameText(OpenXrController openxr) => 'Runtime: ${openxr.bindings.activeRuntimeName}';

  static String manifestText(OpenXrController openxr) {
    final path = openxr.bindings.activeRuntimePath;
    return 'Manifest: ${path.isEmpty ? 'None detected' : path}';
  }

  static String runtimeKindText(OpenXrController openxr) {
    final b = openxr.bindings;
    if (!b.isSimulated) return 'Native OpenXR runtime';
    return b.isNativeRuntimeAvailable
        ? 'Simulated HMD (forced; a native runtime is installed)'
        : 'No physical OpenXR runtime active: using the simulated HMD for development.';
  }

  static String sessionText(OpenXrController openxr) =>
      'Session: ${openxr.session.state.name}${openxr.isVrPreviewActive ? ' (preview running)' : ''}';

  /// The status texts as `host.panelState` operations.
  static List<PluginPanelStateOp> statusOps(OpenXrController openxr) => [
        PluginPanelStateOp(runtimeName, {'text': runtimeNameText(openxr)}),
        PluginPanelStateOp(manifestPath, {'text': manifestText(openxr)}),
        PluginPanelStateOp(runtimeKind, {'text': runtimeKindText(openxr)}),
        PluginPanelStateOp(sessionState, {'text': sessionText(openxr)}),
      ];

  /// The Tracking Origin Mode labels the panel shows.
  static String originLabel(OpenXrTrackingOrigin o) => switch (o) {
        OpenXrTrackingOrigin.eyeLevel => 'Eye level (seated)',
        OpenXrTrackingOrigin.floorLevel => 'Floor level (standing)',
        OpenXrTrackingOrigin.stage => 'Stage (room scale)',
      };

  /// The Stereo Rendering Mode labels the panel shows.
  static String stereoLabel(OpenXrStereoMode m) => switch (m) {
        OpenXrStereoMode.multiview => 'Multiview',
        OpenXrStereoMode.instanced => 'Instanced',
        OpenXrStereoMode.separateViews => 'Separate views',
      };
}
