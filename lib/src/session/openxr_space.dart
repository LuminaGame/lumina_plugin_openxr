import 'package:vector_math/vector_math_64.dart' as vm;
import '../ffi/openxr_types.dart';

/// Coordinate space conversions between OpenXR (metres, right-handed Y-up)
/// and Lumina engine storage (centimetres, right-handed Z-up).
class OpenXrSpaceConverter {
  static const double metersToCentimeters = 100.0;
  static const double centimetersToMeters = 0.01;

  /// Converts an OpenXR position vector (metres, X-right, Y-up, Z-back)
  /// into Lumina world coordinates (centimetres, X-forward, Y-right, Z-up).
  static vm.Vector3 openXrToLuminaPosition(vm.Vector3 pos) {
    // OpenXR: X = right, Y = up, Z = back (-Z is forward)
    // Lumina: X = forward, Y = right, Z = up
    return vm.Vector3(
      -pos.z * metersToCentimeters,
      pos.x * metersToCentimeters,
      pos.y * metersToCentimeters,
    );
  }

  /// Converts a Lumina world position (centimetres, X-forward, Y-right, Z-up)
  /// into OpenXR tracking space coordinates (metres, X-right, Y-up, Z-back).
  static vm.Vector3 luminaToOpenXrPosition(vm.Vector3 pos) {
    return vm.Vector3(
      pos.y * centimetersToMeters,
      pos.z * centimetersToMeters,
      -pos.x * centimetersToMeters,
    );
  }

  /// Converts an OpenXR orientation quaternion into a Lumina rotation quaternion.
  static vm.Quaternion openXrToLuminaRotation(vm.Quaternion rot) {
    // Coordinate frame change matrix:
    // [ 0  0 -1 ]
    // [ 1  0  0 ]
    // [ 0  1  0 ]
    final mat = rot.asRotationMatrix();
    final transformed = vm.Matrix3(
      -mat.entry(2, 2), -mat.entry(2, 0), -mat.entry(2, 1),
      mat.entry(0, 2),  mat.entry(0, 0),  mat.entry(0, 1),
      mat.entry(1, 2),  mat.entry(1, 0),  mat.entry(1, 1),
    );
    return vm.Quaternion.fromRotation(transformed);
  }
}

/// Represents an OpenXR Reference Space (VIEW, LOCAL, STAGE).
class OpenXrReferenceSpace {
  final OpenXrTrackingOrigin originType;
  vm.Vector3 offsetPosition = vm.Vector3.zero();
  vm.Quaternion offsetOrientation = vm.Quaternion.identity();

  OpenXrReferenceSpace({required this.originType});

  /// Translates the reference space origin.
  void setOffset(vm.Vector3 position, vm.Quaternion orientation) {
    offsetPosition = position;
    offsetOrientation = orientation;
  }
}
