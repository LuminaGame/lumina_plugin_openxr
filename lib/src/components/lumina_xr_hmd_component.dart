import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_space.dart';

/// Scene component driving camera viewpoint and head tracking transforms from OpenXR HMD pose.
class LuminaXRHMDComponent extends LuminaSceneComponent {
  double interPupillaryDistance = 0.064; // in metres (64 mm default)
  bool isTracked = true;

  final Vector3 _leftEyeLocation = Vector3.zero();
  final Vector3 _rightEyeLocation = Vector3.zero();

  LuminaXRHMDComponent({
    super.key,
    super.location,
    super.rotation,
    this.interPupillaryDistance = 0.064,
  }) {
    _recalculateEyeOffsets();
  }

  Vector3 get leftEyeLocation => _leftEyeLocation;
  Vector3 get rightEyeLocation => _rightEyeLocation;

  /// Updates HMD pose from raw OpenXR tracking vectors (metres, Y-up).
  void updatePoseFromOpenXr(Vector3 openXrPosition, Quaternion openXrOrientation) {
    location = OpenXrSpaceConverter.openXrToLuminaPosition(openXrPosition);
    rotation = OpenXrSpaceConverter.openXrToLuminaRotation(openXrOrientation);
    _recalculateEyeOffsets();
  }

  /// Updates HMD pose directly in Lumina world space (centimetres, Z-up).
  void updatePoseLumina(Vector3 luminaLocation, Quaternion luminaRotation) {
    location = luminaLocation;
    rotation = luminaRotation;
    _recalculateEyeOffsets();
  }

  void _recalculateEyeOffsets() {
    final halfIpdCm = (interPupillaryDistance * 100.0) / 2.0;
    final rightDir = rotation.rotate(Vector3(0.0, 1.0, 0.0)); // +Y is right in Lumina
    _leftEyeLocation.setFrom(location - (rightDir * halfIpdCm));
    _rightEyeLocation.setFrom(location + (rightDir * halfIpdCm));
  }
}
