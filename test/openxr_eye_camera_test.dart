import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  OpenXrEyeView eye(double x) => OpenXrEyeView(
        position: vm.Vector3(x, 1.6, 0),
        orientation: vm.Quaternion.identity(),
        angleLeft: -0.942,
        angleRight: 0.698,
        angleUp: 0.733,
        angleDown: -0.942,
      );

  test('the projection carries the asymmetric field of view (OpenXR formula)', () {
    final camera = OpenXrEyeCamera.fromViews([eye(-0.0315)], near: 0.05, far: 100).single;
    final l = math.tan(-0.942), r = math.tan(0.698), u = math.tan(0.733), d = math.tan(-0.942);
    // XrMatrix4x4f_CreateProjectionFov (OpenGL clip space).
    expect(camera.projection.entry(0, 0), closeTo(2 / (r - l), 1e-6));
    expect(camera.projection.entry(1, 1), closeTo(2 / (u - d), 1e-6));
    expect(camera.projection.entry(0, 2), closeTo((r + l) / (r - l), 1e-6));
    expect(camera.projection.entry(1, 2), closeTo((u + d) / (u - d), 1e-6));
    expect(camera.projection.entry(3, 2), -1);
  });

  test('the eyes are 6.3 cm apart in Lumina units', () {
    final cameras = OpenXrEyeCamera.fromViews([eye(-0.0315), eye(0.0315)], unitsPerMetre: 100);
    final left = cameras[0].model.getTranslation();
    final right = cameras[1].model.getTranslation();
    expect(left.distanceTo(right), closeTo(6.3, 1e-9));
    expect(left.y, closeTo(160, 1e-9));
  });

  test('the culling projection encloses both eyes', () {
    final views = [
      eye(-0.0315),
      OpenXrEyeView(
        position: vm.Vector3(0.0315, 1.6, 0),
        orientation: vm.Quaternion.identity(),
        angleLeft: -0.698,
        angleRight: 0.942,
        angleUp: 0.733,
        angleDown: -0.942,
      ),
    ];
    final culling = OpenXrEyeCamera.cullingProjection(views);
    final l = math.tan(-0.942), r = math.tan(0.942);
    expect(culling.entry(0, 0), closeTo(2 / (r - l), 1e-6));
    expect(culling.entry(0, 2), closeTo(0, 1e-6));
  });

  test('the camera sits at the head (culling looks where the eyes look); the eyes are relative to it', () {
    final views = [eye(-0.0315), eye(0.0315)];
    final head = OpenXrEyeCamera.head(views, unitsPerMetre: 100);
    expect(head.getTranslation(), vm.Vector3(0, 160, 0));
    final cameras = OpenXrEyeCamera.fromViews(views, unitsPerMetre: 100);
    final left = OpenXrEyeCamera.relativeTo(head, cameras[0].model);
    expect(left.getTranslation().x, closeTo(-3.15, 1e-9));
    expect(left.getTranslation().y, closeTo(0, 1e-9));
    // Head times relative eye is the eye again.
    final back = head.multiplied(left);
    for (var i = 0; i < 16; i++) {
      expect(back.storage[i], closeTo(cameras[0].model.storage[i], 1e-9));
    }
  });
}
