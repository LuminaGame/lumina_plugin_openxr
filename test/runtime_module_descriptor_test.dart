import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/lumina.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

/// The descriptor's game side: the runtime module a game's `main()`
/// registers, and what the plugin adds to a Quest build's manifest.
void main() {
  test('the descriptor names the runtime module and the immersive manifest entries', () async {
    final descriptor = await PluginRepository(roots: const []).load(File('lumina_plugin_openxr.lmplugin'));
    final runtime = descriptor.runtimeModules.single;
    expect(runtime.entryLibrary, 'lib/runtime.dart');
    expect(runtime.registrationClass, 'LuminaOpenXrRuntime');
    final android = descriptor.android!;
    expect(android.usesFeatures.single.name, 'android.hardware.vr.headtracking');
    expect(android.usesFeatures.single.required, isTrue);
    expect(android.intentCategories, ['com.oculus.intent.category.VR', 'org.khronos.openxr.intent.category.IMMERSIVE_HMD']);
    expect(android.permissions.map((p) => p.name), ['org.khronos.openxr.permission.OPENXR', 'org.khronos.openxr.permission.OPENXR_SYSTEM']);
    expect(android.queries.join(), contains('org.khronos.openxr.runtime_broker'));
    expect(android.activityAttributes['launchMode'], 'singleTask');
    expect(android.activityAttributes['configChanges'], contains('density'));
  });

  test('register keeps the project settings and registers the XR nodes once', () {
    LuminaOpenXrRuntime.register(const {'xr': 'quest', 'refresh_rate': 90});
    LuminaOpenXrRuntime.register(const {'xr': 'quest', 'refresh_rate': 72});
    expect(LuminaOpenXrRuntime.isRegistered, isTrue);
    expect(LuminaOpenXrRuntime.xrProfile, 'quest');
    expect(LuminaOpenXrRuntime.refreshRate, 72);
    expect(LuminaBlueprintFunctionRegistry.entry(OpenXrBlueprintNodes.gripValueId), isNotNull);
  });
}
