import 'dart:ffi';
import 'package:vector_math/vector_math_64.dart' as vm;

/// OpenXR result status codes (Khronos OpenXR 1.0/1.1 Specification).
enum XrResult {
  success(0),
  timeoutExpired(1),
  sessionLossPending(3),
  eventUnavailable(4),
  spaceBoundsUnavailable(7),
  sessionNotFocused(8),
  frameDiscarded(9),
  errorValidationFailure(-1),
  errorRuntimeFailure(-2),
  errorOutOfMemory(-3),
  errorApiVersionUnsupported(-4),
  errorInitializationFailed(-5),
  errorFunctionUnsupported(-6),
  errorFeatureUnsupported(-7),
  errorExtensionNotPresent(-8),
  errorLimitReached(-9),
  errorSizeInsufficient(-10),
  errorHandleInvalid(-11),
  errorInstanceLost(-12),
  errorSessionLost(-13),
  errorPoseInvalid(-14);

  final int value;
  const XrResult(this.value);

  static XrResult fromValue(int val) {
    for (final e in values) {
      if (e.value == val) return e;
    }
    return val >= 0 ? XrResult.success : XrResult.errorRuntimeFailure;
  }

  bool get isSuccess => value >= 0;
  bool get isFailure => value < 0;
}

/// OpenXR session lifecycle states.
enum OpenXrSessionState {
  unknown(0),
  idle(1),
  ready(2),
  synchronized(3),
  visible(4),
  focused(5),
  stopping(6),
  lossPending(7),
  exiting(8);

  final int value;
  const OpenXrSessionState(this.value);
}

/// Tracking reference space origin.
enum OpenXrTrackingOrigin {
  /// Head/eye level tracking space (seated or stationary).
  eyeLevel,

  /// Calibrated floor level tracking space (standing).
  floorLevel,

  /// Calibrated bounded roomscale stage tracking space.
  stage,
}

/// Stereoscopic rendering technique.
enum OpenXrStereoMode {
  /// Filament multiview stereoscopic rendering.
  multiview,

  /// Filament instanced stereoscopic rendering.
  instanced,

  /// Dual independent camera view passes.
  separateViews,
}

/// 3D Vector in OpenXR coordinates (metres, right-handed Y-up).
final class XrVector3f extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double z;

  vm.Vector3 toVector3() => vm.Vector3(x, y, z);
}

/// Quaternion in OpenXR coordinates.
final class XrQuaternionf extends Struct {
  @Float()
  external double x;

  @Float()
  external double y;

  @Float()
  external double z;

  @Float()
  external double w;

  vm.Quaternion toQuaternion() => vm.Quaternion(x, y, z, w);
}

/// 6-DOF Pose in OpenXR coordinates.
final class XrPosef extends Struct {
  external XrQuaternionf orientation;
  external XrVector3f position;
}

/// Field of View in radians (tangent angles from optical axis).
final class XrFovf extends Struct {
  @Float()
  external double angleLeft;

  @Float()
  external double angleRight;

  @Float()
  external double angleUp;

  @Float()
  external double angleDown;
}

/// OpenXR eye view parameters.
final class XrView extends Struct {
  @Int32()
  external int type;

  external Pointer<Void> next;
  external XrPosef pose;
  external XrFovf fov;
}
