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

  /// Computes the eye view matrix (inverse of eye transform).
  vm.Matrix4 createViewMatrix() {
    final rotMat = eyeOrientation.asRotationMatrix();
    final transMat = rotMat.transposed();
    final double tx = transMat.entry(0, 0) * -eyePosition.x +
        transMat.entry(0, 1) * -eyePosition.y +
        transMat.entry(0, 2) * -eyePosition.z;
    final double ty = transMat.entry(1, 0) * -eyePosition.x +
        transMat.entry(1, 1) * -eyePosition.y +
        transMat.entry(1, 2) * -eyePosition.z;
    final double tz = transMat.entry(2, 0) * -eyePosition.x +
        transMat.entry(2, 1) * -eyePosition.y +
        transMat.entry(2, 2) * -eyePosition.z;

    final m = vm.Matrix4.identity();
    m.setEntry(0, 0, rotMat.entry(0, 0));
    m.setEntry(1, 0, rotMat.entry(1, 0));
    m.setEntry(2, 0, rotMat.entry(2, 0));

    m.setEntry(0, 1, rotMat.entry(0, 1));
    m.setEntry(1, 1, rotMat.entry(1, 1));
    m.setEntry(2, 1, rotMat.entry(2, 1));

    m.setEntry(0, 2, rotMat.entry(0, 2));
    m.setEntry(1, 2, rotMat.entry(1, 2));
    m.setEntry(2, 2, rotMat.entry(2, 2));

    m.setEntry(3, 0, tx);
    m.setEntry(3, 1, ty);
    m.setEntry(3, 2, tz);
    return m;
  }
}
