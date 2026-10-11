import 'package:lumina_core/lumina_core.dart' show LuminaAxes, LuminaUnits;
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';

/// Conversions between OpenXR tracking space (metres, right-handed, Y up,
/// -Z forward) and Lumina. Lumina's runtime has the same axes as OpenXR, in
/// centimetres ([LuminaUnits]); its stored (authoring) transforms are Z up,
/// converted only through [LuminaAxes]: authoring `(x, y, z)` = runtime
/// `(x, -z, y)`, so OpenXR forward (-Z) is authoring +Y and up is +Z.
class OpenXrSpaceConverter {
  static const double metersToCentimeters = LuminaUnits.unitsPerMetre;
  static const double centimetersToMeters = 1 / LuminaUnits.unitsPerMetre;

  /// An OpenXR position (m) in Lumina's runtime axes (cm, Y up).
  static vm.Vector3 openXrToRuntimePosition(vm.Vector3 pos) => pos * metersToCentimeters;

  /// A Lumina runtime position (cm) in OpenXR (m).
  static vm.Vector3 runtimeToOpenXrPosition(vm.Vector3 pos) => pos * centimetersToMeters;

  /// An OpenXR position (m) as a Lumina authoring location (cm, Z up), as the
  /// Details panel and level files show it.
  static vm.Vector3 openXrToLuminaPosition(vm.Vector3 pos) {
    final a = LuminaAxes.toAuthoringLocation(openXrToRuntimePosition(pos));
    return vm.Vector3(a[0], a[1], a[2]);
  }

  /// A Lumina authoring location (cm, Z up) in OpenXR (m).
  static vm.Vector3 luminaToOpenXrPosition(vm.Vector3 pos) =>
      runtimeToOpenXrPosition(LuminaAxes.location([pos.x, pos.y, pos.z]));

  /// An OpenXR orientation in Lumina's runtime axes: the same rotation (the
  /// axes agree), normalised.
  static vm.Quaternion openXrToRuntimeRotation(vm.Quaternion rot) => rot.normalized();

  /// An OpenXR orientation expressed in Lumina's authoring axes: the change of
  /// basis runtime -> authoring, (x, y, z) -> (x, -z, y), applied to the rotation.
  static vm.Quaternion openXrToLuminaRotation(vm.Quaternion rot) {
    // Rows: authoring x, y, z in runtime components.
    final basis = vm.Matrix3.columns(vm.Vector3(1, 0, 0), vm.Vector3(0, 0, 1), vm.Vector3(0, -1, 0));
    final m = basis.multiplied(rot.normalized().asRotationMatrix()).multiplied(basis.transposed());
    return vm.Quaternion.fromRotation(m)..normalize();
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
