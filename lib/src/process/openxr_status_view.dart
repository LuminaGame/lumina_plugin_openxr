import 'dart:convert';

import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' show LucideIcons;

import '../ffi/openxr_types.dart';
import '../lumina_plugin_openxr_plugin.dart';

/// The OpenXR panel as a declarative view: runtime status, the runtime
/// choice, tracking and stereo settings, the VR preview and the About text.
/// The editor renders it; the plugin process answers its events.
abstract final class OpenXrStatusView {
  /// The view id (events and updates name it).
  static const String viewId = 'lumina_plugin_openxr.status';

  /// Control ids.
  static const String runtimeName = 'runtimeName';
  static const String manifestPath = 'manifestPath';
  static const String runtimeKind = 'runtimeKind';
  static const String forceSimulation = 'forceSimulation';
  static const String trackingOrigin = 'trackingOrigin';
  static const String stereoMode = 'stereoMode';
  static const String sessionState = 'sessionState';
  static const String togglePreview = 'togglePreview';
  static const String about = 'about';

  /// The panel the process registers, built from [plugin]'s current state.
  static PluginProcessViewPanel panel(LuminaPluginOpenxrPlugin plugin) => PluginProcessViewPanel(
        id: LuminaPluginOpenxrPlugin.panelId,
        title: 'OpenXR',
        icon: pluginIconOf(LucideIcons.glasses),
        dock: 'right',
        initial: spec(plugin),
        onEvent: (event, view) {
          if (handle(plugin, event)) refresh(plugin, view);
        },
      );

  /// The spec for [plugin]'s current state.
  static PluginViewSpec spec(LuminaPluginOpenxrPlugin plugin) {
    final b = plugin.bindings;
    final native = b.isNativeRuntimeAvailable;
    final path = b.activeRuntimePath;
    final preview = plugin.isVrPreviewActive;
    return PluginViewSpec(id: viewId, children: [
      PluginControl.section('runtime', 'Active Runtime', [
        PluginControl.text(runtimeName, 'Runtime: ${b.activeRuntimeName}'),
        PluginControl.text(manifestPath, 'Manifest: ${path.isEmpty ? 'None detected' : path}', style: 'code'),
        PluginControl.text(
          runtimeKind,
          b.isSimulated
              ? (native
                  ? 'Simulated HMD (forced; a native runtime is installed)'
                  : 'No physical OpenXR runtime active: using the simulated HMD for development.')
              : 'Native OpenXR runtime',
          style: 'muted',
        ),
        PluginControl.boolField(forceSimulation, label: 'Force Simulated Runtime', value: b.isSimulationForced),
      ]),
      PluginControl.section('tracking', 'Tracking & Stereoscopic', [
        PluginControl.enumField(
          trackingOrigin,
          label: 'Tracking Origin Mode',
          value: plugin.session.trackingOrigin.name,
          options: [for (final o in OpenXrTrackingOrigin.values) (o.name, _originLabel(o))],
        ),
        PluginControl.enumField(
          stereoMode,
          label: 'Stereo Rendering Mode',
          value: plugin.stereoMode.name,
          options: [for (final m in OpenXrStereoMode.values) (m.name, _stereoLabel(m))],
        ),
      ]),
      PluginControl.section('preview', 'VR Preview', [
        PluginControl.text(sessionState, 'Session: ${plugin.session.state.name}${preview ? ' (preview running)' : ''}'),
        PluginControl.button(togglePreview, preview ? 'Stop VR Preview' : 'Start VR Preview',
            tone: preview ? 'destructive' : 'primary'),
      ]),
      PluginControl.section('aboutSection', 'About ${LuminaPluginOpenxrPlugin.friendlyName}', [
        PluginControl.text(about, LuminaPluginOpenxrPlugin.aboutText, style: 'muted'),
      ], collapsed: true),
    ]);
  }

  /// Sends [plugin]'s current spec to [view] unless it shows that already.
  static void refresh(LuminaPluginOpenxrPlugin plugin, PluginViewHandle view) {
    final next = spec(plugin);
    if (jsonEncode(next.toJson()) != jsonEncode(view.current.toJson())) view.replace(next);
  }

  /// Applies [event] to [plugin]; true when the view must be rebuilt.
  static bool handle(LuminaPluginOpenxrPlugin plugin, PluginViewEvent event) {
    switch ((event.controlId, event.kind)) {
      case (forceSimulation, 'changed'):
        plugin.setForceSimulation(event.value == true);
        return true;
      case (trackingOrigin, 'changed'):
        final origin = OpenXrTrackingOrigin.values.where((o) => o.name == event.value).firstOrNull;
        if (origin == null) return false;
        plugin.setTrackingOrigin(origin);
        return true;
      case (stereoMode, 'changed'):
        final mode = OpenXrStereoMode.values.where((m) => m.name == event.value).firstOrNull;
        if (mode == null) return false;
        plugin.stereoMode = mode;
        return true;
      case (togglePreview, 'pressed'):
        plugin.toggleVrPreview();
        return true;
    }
    return false;
  }

  static String _originLabel(OpenXrTrackingOrigin o) => switch (o) {
        OpenXrTrackingOrigin.eyeLevel => 'Eye level (seated)',
        OpenXrTrackingOrigin.floorLevel => 'Floor level (standing)',
        OpenXrTrackingOrigin.stage => 'Stage (room scale)',
      };

  static String _stereoLabel(OpenXrStereoMode m) => switch (m) {
        OpenXrStereoMode.multiview => 'Multiview',
        OpenXrStereoMode.instanced => 'Instanced',
        OpenXrStereoMode.separateViews => 'Separate views',
      };
}
