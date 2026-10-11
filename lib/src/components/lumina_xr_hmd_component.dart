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

  /// Updates the HMD pose from an OpenXR pose (metres). Lumina's runtime has
  /// OpenXR's axes (Y up, -Z forward, +X right) in centimetres.
  void updatePoseFromOpenXr(Vector3 openXrPosition, Quaternion openXrOrientation) {
    location = OpenXrSpaceConverter.openXrToRuntimePosition(openXrPosition);
    rotation = OpenXrSpaceConverter.openXrToRuntimeRotation(openXrOrientation);
    _recalculateEyeOffsets();
  }

  /// Updates the HMD pose directly in Lumina runtime space (centimetres, Y up).
  void updatePoseLumina(Vector3 luminaLocation, Quaternion luminaRotation) {
    location = luminaLocation;
    rotation = luminaRotation;
    _recalculateEyeOffsets();
  }

  void _recalculateEyeOffsets() {
    final halfIpdCm = (interPupillaryDistance * 100.0) / 2.0;
    // +X is right in the runtime; rotateVector applies the rotation (Quaternion.rotate applies its inverse).
    final rightDir = rotation.rotateVector(Vector3(1.0, 0.0, 0.0));
    _leftEyeLocation.setFrom(location - (rightDir * halfIpdCm));
    _rightEyeLocation.setFrom(location + (rightDir * halfIpdCm));
  }
}
