import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' as vm;

/// Stereoscopic view configuration containing eye pose, FOV, and asymmetric projection matrix.
class OpenXrStereoView {
  final vm.Vector3 eyePosition;
  final vm.Quaternion eyeOrientation;
  final double angleLeft;
  final double angleRight;
  final double angleUp;
  final double angleDown;

  OpenXrStereoView({
    required this.eyePosition,
    required this.eyeOrientation,
    required this.angleLeft,
    required this.angleRight,
    required this.angleUp,
    required this.angleDown,
  });

  /// Computes the exact asymmetric perspective projection matrix for this eye view.
  vm.Matrix4 createProjectionMatrix({double nearPlane = 0.05, double farPlane = 1000.0}) {
    final tanLeft = math.tan(angleLeft);
    final tanRight = math.tan(angleRight);
    final tanDown = math.tan(angleDown);
    final tanUp = math.tan(angleUp);

    final tanWidth = tanRight - tanLeft;
    final tanHeight = tanUp - tanDown;

    final m = vm.Matrix4.zero();
    m.setEntry(0, 0, 2.0 / tanWidth);
    m.setEntry(1, 1, 2.0 / tanHeight);
    m.setEntry(0, 2, (tanRight + tanLeft) / tanWidth);
    m.setEntry(1, 2, (tanUp + tanDown) / tanHeight);
    m.setEntry(2, 2, -(farPlane + nearPlane) / (farPlane - nearPlane));
    m.setEntry(3, 2, -1.0);
    m.setEntry(2, 3, -(2.0 * farPlane * nearPlane) / (farPlane - nearPlane));
    return m;
  }

  /// The eye's view matrix: the inverse of its pose (rotation, then
  /// translation), so the eye position maps to the origin. vector_math is
  /// column-major: the translation lives in column 3 (`setEntry(row, 3, …)`).
  vm.Matrix4 createViewMatrix() {
    final rotation = eyeOrientation.asRotationMatrix();
    final inverse = rotation.transposed();
    final t = inverse.transformed(-eyePosition);
    final m = vm.Matrix4.identity()..setRotation(inverse);
    m.setEntry(0, 3, t.x);
    m.setEntry(1, 3, t.y);
    m.setEntry(2, 3, t.z);
    return m;
  }

  /// The eye's model matrix (its pose): the inverse of [createViewMatrix].
  vm.Matrix4 createModelMatrix() => vm.Matrix4.compose(eyePosition, eyeOrientation, vm.Vector3.all(1));
}
