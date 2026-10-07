import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_process/testing.dart';

/// The packages the process part (the library declaring
/// LuminaPluginOpenxrProcess and everything it imports from this package)
/// imports directly: the process API, the OpenXR loader bridge's FFI helpers,
/// logging and the pose math.
const allowed = {'ffi', 'logging', 'lumina_plugin_process', 'vector_math'};

/// The packages among them that tie the process part to Flutter, each with
/// the reason. Empty: the process part could run as a plain `dart` program.
const flutterBound = <String, String>{};

void main() {
  test('the process part imports only its recorded packages', () {
    final reach = PluginProcessReach.ofPlugin(Directory.current);
    expect(reach.directPackages, allowed, reason: reach.ownLibraries.join('\n'));
  });
  test('the process part reaches Flutter only through its recorded packages', () {
    final reach = PluginProcessReach.ofPlugin(Directory.current);
    expect(reach.directFlutterPackages, flutterBound.keys.toSet(), reason: reach.describeFlutter());
    if (flutterBound.isEmpty) expect(reach.flutterPackages, isEmpty, reason: reach.describeFlutter());
  });
}
