import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';

/// Status bar indicator badge for OpenXR active runtime status.
class OpenXrStatusBadge extends StatelessWidget {
  final OpenXrBindings bindings;

  const OpenXrStatusBadge({super.key, required this.bindings});

  @override
  Widget build(BuildContext context) {
    final isNative = bindings.isNativeRuntimeAvailable;
    final isSim = bindings.isSimulated;
    final name = bindings.activeRuntimeName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.glasses, size: 14),
        const SizedBox(width: 6),
        if (isNative && !isSim)
          PrimaryBadge(child: Text('XR: $name'))
        else if (isSim)
          SecondaryBadge(child: Text('XR (Sim): $name'))
        else
          const OutlineBadge(child: Text('XR: Offline')),
      ],
    );
  }
}
