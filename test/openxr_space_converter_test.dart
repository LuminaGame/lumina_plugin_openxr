import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_core/lumina_core.dart' show LuminaAxes;
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  test('an OpenXR position in Lumina runtime and authoring axes', () {
    final xr = vm.Vector3(0.1, 1.6, -0.5);
    // Runtime: the same axes, centimetres.
    final runtime = OpenXrSpaceConverter.openXrToRuntimePosition(xr);
    expect(runtime.x, closeTo(10, 1e-9));
    expect(runtime.y, closeTo(160, 1e-9));
    expect(runtime.z, closeTo(-50, 1e-9));
    // Authoring (Z up, forward +Y), through LuminaAxes: (x, -z, y).
    final authoring = OpenXrSpaceConverter.openXrToLuminaPosition(xr);
    expect(authoring.x, closeTo(10, 1e-9));
    expect(authoring.y, closeTo(50, 1e-9));
    expect(authoring.z, closeTo(160, 1e-9));
    expect((LuminaAxes.location([authoring.x, authoring.y, authoring.z]) - runtime).length, closeTo(0, 1e-9));
    final back = OpenXrSpaceConverter.luminaToOpenXrPosition(authoring);
    expect((back - xr).length, closeTo(0, 1e-9));
  });

  test('a yaw in OpenXR is a turn about authoring +Z', () {
    final yaw = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.5);
    final authoring = OpenXrSpaceConverter.openXrToLuminaRotation(yaw);
    // Up (authoring +Z) stays up; forward (+Y) stays level.
    expect(authoring.rotated(vm.Vector3(0, 0, 1)).z, closeTo(1, 1e-9));
    expect(authoring.rotated(vm.Vector3(0, 1, 0)).z, closeTo(0, 1e-9));
    // The same turn seen in both frames: runtime forward (-Z) maps to authoring forward (+Y).
    final runtimeForward = yaw.rotated(vm.Vector3(0, 0, -1));
    final authoringForward = authoring.rotated(vm.Vector3(0, 1, 0));
    final expected = LuminaAxes.toAuthoringLocation(runtimeForward);
    expect(authoringForward.x, closeTo(expected[0], 1e-9));
    expect(authoringForward.y, closeTo(expected[1], 1e-9));
  });
}
