import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../ffi/openxr_bindings.dart';
import '../ffi/openxr_types.dart';
import '../session/openxr_session.dart';

/// Settings panel for OpenXR configuration.
class OpenXrSettingsView extends StatefulWidget {
  final OpenXrBindings bindings;
  final OpenXrSession session;

  const OpenXrSettingsView({
    super.key,
    required this.bindings,
    required this.session,
  });

  @override
  State<OpenXrSettingsView> createState() => _OpenXrSettingsViewState();
}

class _OpenXrSettingsViewState extends State<OpenXrSettingsView> {
  late OpenXrTrackingOrigin _origin;
  late OpenXrStereoMode _stereoMode;
  late bool _forceSimulation;

  @override
  void initState() {
    super.initState();
    _origin = widget.session.trackingOrigin;
    _stereoMode = OpenXrStereoMode.instanced;
    _forceSimulation = widget.bindings.isSimulated && !widget.bindings.isNativeRuntimeAvailable;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('OpenXR Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Configure Khronos OpenXR runtime, tracking spaces, and stereoscopic rendering parameters.'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active Runtime Status', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Runtime: ${widget.bindings.activeRuntimeName}'),
                  const SizedBox(height: 4),
                  Text(
                    'Manifest: ${widget.bindings.activeRuntimePath.isEmpty ? "None detected" : widget.bindings.activeRuntimePath}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Force Simulated Runtime'),
                      Switch(
                        value: _forceSimulation,
                        onChanged: (val) {
                          setState(() {
                            _forceSimulation = val;
                            widget.bindings.setForceSimulation(val);
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tracking & Stereoscopic', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  const Text('Tracking Origin Mode:'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final mode in OpenXrTrackingOrigin.values) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: mode == _origin
                              ? PrimaryButton(
                                  onPressed: () {},
                                  child: Text(mode.name),
                                )
                              : OutlineButton(
                                  onPressed: () {
                                    setState(() {
                                      _origin = mode;
                                      widget.session.setTrackingOrigin(mode);
                                    });
                                  },
                                  child: Text(mode.name),
                                ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Stereo Rendering Mode:'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final mode in OpenXrStereoMode.values) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: mode == _stereoMode
                              ? PrimaryButton(
                                  onPressed: () {},
                                  child: Text(mode.name),
                                )
                              : OutlineButton(
                                  onPressed: () {
                                    setState(() {
                                      _stereoMode = mode;
                                    });
                                  },
                                  child: Text(mode.name),
                                ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
