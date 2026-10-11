import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  test('the view matrix maps the eye position to the origin', () {
    // An eye at (0.032, 1.7, 0) m looking down -Z (identity orientation).
    final view = OpenXrStereoView(
      eyePosition: vm.Vector3(0.032, 1.7, 0),
      eyeOrientation: vm.Quaternion.identity(),
      angleLeft: -0.8,
      angleRight: 0.8,
      angleUp: 0.8,
      angleDown: -0.8,
    ).createViewMatrix();
    final eye = view.transform3(vm.Vector3(0.032, 1.7, 0));
    expect(eye.length, closeTo(0, 1e-9));
    // A point one metre in front of the eye is one metre down -Z in eye space.
    final ahead = view.transform3(vm.Vector3(0.032, 1.7, -1));
    expect(ahead.z, closeTo(-1, 1e-9));
    expect(ahead.x, closeTo(0, 1e-9));
  });

  test('a turned eye: the view matrix is the inverse of the eye pose', () {
    final pose = OpenXrStereoView(
      eyePosition: vm.Vector3(-0.4, 1.6, 0.3),
      eyeOrientation: vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.7),
      angleLeft: -0.8,
      angleRight: 0.8,
      angleUp: 0.8,
      angleDown: -0.8,
    );
    final product = pose.createViewMatrix().multiplied(pose.createModelMatrix());
    final identity = vm.Matrix4.identity();
    for (var i = 0; i < 16; i++) {
      expect(product.storage[i], closeTo(identity.storage[i], 1e-9));
    }
  });
}
