// Runs lumina_plugin_openxr's smoke tests (desktop GPU, the simulated headset)
// and writes `build/smoke_report.html`, linking the PNGs and videos in
// `build/smoke_artifacts/vulkan/`.
//
//   dart run tool/smoke_report.dart test/smoke/openxr_frame_loop_smoke_test.dart --no-dashboard
//
// The runner, the report and every flag are lumina_smoke's
// (`package:lumina_smoke/report.dart`).
import 'package:lumina_smoke/report.dart';

/// The plugin's report configuration.
const SmokeReportConfig openXrSmokeConfig = SmokeReportConfig(
  title: 'OpenXR Plugin Test Report',
  tag: 'lumina_plugin_openxr',
  dashboardTitle: 'OpenXR Smoke Tests',
  categories: TestCategories([
    ('input', ['input']),
    ('frame_loop', ['frame_loop', 'openxr']),
  ]),
  categoryNote: 'Every PNG and video is linked from build/smoke_artifacts/, not embedded.',
  failingCategoriesFirst: true,
  backends: [
    SmokeBackend('vulkan', environment: {'FILAMENT_SMOKE_BACKEND': 'vulkan'}),
  ],
);

Future<void> main(List<String> args) => smokeReportMain(args, openXrSmokeConfig);
