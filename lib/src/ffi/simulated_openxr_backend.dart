import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';

/// Simulated OpenXR runtime backend for development, CI, and testing without physical VR hardware.
///
/// It posts the session state changes a real runtime posts (READY after the
/// instance, SYNCHRONIZED, VISIBLE and FOCUSED after `beginSession`, IDLE
/// after `endSession`, EXITING on shutdown), so a session follows the same
/// event-driven state machine as on a headset.
class SimulatedOpenXrBackend implements OpenXrBackend {
  final List<OpenXrRuntimeEvent> _events = [];

  bool _initialized = false;
  OpenXrSessionState _sessionState = OpenXrSessionState.idle;

  // Headset simulation properties
  @override
  bool get isNative => false;

  @override
  String get runtimeName => 'Lumina Simulated HMD';

  @override
  String get systemName => 'Lumina Virtual OpenXR HMD';
  int get recommendedImageRectWidth => 2064;
  int get recommendedImageRectHeight => 2208;
  double get displayRefreshRate => 90.0;
  double interPupillaryDistance = 0.064; // 64 mm

  // Simulated 6-DOF Head Pose in tracking space (metres, Y-up)
  vm.Vector3 headPosition = vm.Vector3(0.0, 1.70, 0.0); // 1.7m standing height
  vm.Quaternion headOrientation = vm.Quaternion.identity();

  // Simulated Left Hand Controller
  vm.Vector3 leftGripPosition = vm.Vector3(-0.25, 1.2, -0.4);
  vm.Quaternion leftGripOrientation = vm.Quaternion.identity();
  double leftTrigger = 0.0;
  double leftGrip = 0.0;
  vm.Vector2 leftThumbstick = vm.Vector2.zero();
  bool leftPrimaryButton = false;
  bool leftSecondaryButton = false;

  // Simulated Right Hand Controller
  vm.Vector3 rightGripPosition = vm.Vector3(0.25, 1.2, -0.4);
  vm.Quaternion rightGripOrientation = vm.Quaternion.identity();
  double rightTrigger = 0.0;
  double rightGrip = 0.0;
  vm.Vector2 rightThumbstick = vm.Vector2.zero();
  bool rightPrimaryButton = false;
  bool rightSecondaryButton = false;

  // Last received haptic feedback parameters
  double lastHapticAmplitude = 0.0;
  int lastHapticDurationNano = 0;

  bool get isInitialized => _initialized;
  OpenXrSessionState get sessionState => _sessionState;

  @override
  List<OpenXrViewConfiguration> get viewConfigurations => List.filled(
      2,
      OpenXrViewConfiguration(
          recommendedWidth: recommendedImageRectWidth,
          recommendedHeight: recommendedImageRectHeight,
          maxWidth: recommendedImageRectWidth * 2,
          maxHeight: recommendedImageRectHeight * 2));

  @override
  List<int> get blendModes => const [OpenXrBlendMode.opaque, OpenXrBlendMode.alphaBlend];

  void _post(OpenXrSessionState state) {
    _sessionState = state;
    _events.add(OpenXrSessionStateChanged(state));
  }

  XrResult initialize() {
    if (!_initialized) {
      _initialized = true;
      _post(OpenXrSessionState.ready);
    }
    return XrResult.success;
  }

  @override
  XrResult createInstance({String applicationName = 'Lumina', List<String> optionalExtensions = const []}) =>
      initialize();

  @override
  bool extensionEnabled(String extension) => false;

  @override
  OpenXrRuntimeEvent? pollEvent() => _events.isEmpty ? null : _events.removeAt(0);

  @override
  XrResult beginSession() {
    if (!_initialized) return XrResult.errorInitializationFailed;
    _post(OpenXrSessionState.synchronized);
    _post(OpenXrSessionState.visible);
    _post(OpenXrSessionState.focused);
    return XrResult.success;
  }

  @override
  XrResult endSession() {
    if (!_initialized) return XrResult.errorInitializationFailed;
    _post(OpenXrSessionState.idle);
    return XrResult.success;
  }

  @override
  XrResult requestExitSession() {
    if (!_initialized) return XrResult.errorInitializationFailed;
    _post(OpenXrSessionState.stopping);
    return XrResult.success;
  }

  @override
  List<OpenXrEyeView> locateViews(int baseSpace, int displayTime) {
    final left = getLeftEyeView();
    final right = getRightEyeView();
    return [
      for (final v in [left, right])
        OpenXrEyeView(
            position: v.position,
            orientation: v.orientation,
            angleLeft: v.fovLeft,
            angleRight: v.fovRight,
            angleUp: v.fovUp,
            angleDown: v.fovDown),
    ];
  }

  XrResult shutdown() {
    if (_initialized) _post(OpenXrSessionState.exiting);
    _initialized = false;
    return XrResult.success;
  }

  @override
  void destroy() {
    shutdown();
    _events.clear();
  }

  /// Calculates Left eye view pose and FOV.
  ({vm.Vector3 position, vm.Quaternion orientation, double fovLeft, double fovRight, double fovUp, double fovDown})
  getLeftEyeView() {
    final halfIpd = interPupillaryDistance / 2.0;
    final eyeOffset = headOrientation.rotate(vm.Vector3(-halfIpd, 0.0, 0.0));
    return (
      position: headPosition + eyeOffset,
      orientation: headOrientation,
      fovLeft: -0.85, // ~49 deg nasal
      fovRight: 0.90, // ~52 deg temporal
      fovUp: 0.85,
      fovDown: -0.85,
    );
  }

  /// Calculates Right eye view pose and FOV.
  ({vm.Vector3 position, vm.Quaternion orientation, double fovLeft, double fovRight, double fovUp, double fovDown})
  getRightEyeView() {
    final halfIpd = interPupillaryDistance / 2.0;
    final eyeOffset = headOrientation.rotate(vm.Vector3(halfIpd, 0.0, 0.0));
    return (
      position: headPosition + eyeOffset,
      orientation: headOrientation,
      fovLeft: -0.90, // ~52 deg temporal
      fovRight: 0.85, // ~49 deg nasal
      fovUp: 0.85,
      fovDown: -0.85,
    );
  }

  /// Applies simulated head rotation in pitch/yaw (radians).
  void setHeadLookAngles(double yawRad, double pitchRad) {
    headOrientation = vm.Quaternion.axisAngle(vm.Vector3(0.0, 1.0, 0.0), yawRad) *
        vm.Quaternion.axisAngle(vm.Vector3(1.0, 0.0, 0.0), pitchRad);
  }

  /// Injects simulated controller motion.
  void setControllerPose({
    required bool isLeft,
    required vm.Vector3 position,
    required vm.Quaternion orientation,
  }) {
    if (isLeft) {
      leftGripPosition = position;
      leftGripOrientation = orientation;
    } else {
      rightGripPosition = position;
      rightGripOrientation = orientation;
    }
  }

  /// Injects simulated controller button inputs.
  void setControllerInputs({
    required bool isLeft,
    double trigger = 0.0,
    double grip = 0.0,
    vm.Vector2? thumbstick,
    bool primaryButton = false,
    bool secondaryButton = false,
  }) {
    if (isLeft) {
      leftTrigger = trigger;
      leftGrip = grip;
      if (thumbstick != null) leftThumbstick = thumbstick;
      leftPrimaryButton = primaryButton;
      leftSecondaryButton = secondaryButton;
    } else {
      rightTrigger = trigger;
      rightGrip = grip;
      if (thumbstick != null) rightThumbstick = thumbstick;
      rightPrimaryButton = primaryButton;
      rightSecondaryButton = secondaryButton;
    }
  }

  /// Simulates receiving haptic feedback pulse.
  void applyHapticFeedback({required double amplitude, required int durationNano}) {
    lastHapticAmplitude = amplitude;
    lastHapticDurationNano = durationNano;
  }
}
