import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../lumina_plugin_openxr_plugin.dart';
import 'openxr_settings_view.dart';

/// A dialog with [title], [message] and one close button.
void showOpenXrMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String closeLabel = 'Close',
}) {
  showOverlay<void>(
    context,
    const DialogConfiguration(),
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        PrimaryButton(onPressed: () => closeOverlay<void>(c), child: Text(closeLabel)),
      ],
    ),
  );
}

/// The OpenXR settings dialog for [plugin]; changes update the plugin's
/// status button at once.
void showOpenXrSettingsDialog(BuildContext context, {required LuminaPluginOpenxrPlugin plugin}) {
  showOverlay<void>(
    context,
    const DialogConfiguration(),
    builder: (c) => AlertDialog(
      title: const Text('OpenXR Settings'),
      content: SizedBox(
        width: 500,
        child: OpenXrSettingsView(
          bindings: plugin.bindings,
          session: plugin.session,
          initialStereoMode: plugin.stereoMode,
          onChanged: plugin.refreshStatus,
          onStereoModeChanged: (mode) => plugin.stereoMode = mode,
        ),
      ),
      actions: [
        PrimaryButton(onPressed: () => closeOverlay<void>(c), child: const Text('Close')),
      ],
    ),
  );
}
