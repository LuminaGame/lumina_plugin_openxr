import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart';
import '../input/openxr_action_state.dart';
import '../session/openxr_space.dart';
import 'lumina_xr_hand.dart';

/// Scene component managing motion controller tracking, inputs, and haptics.
class LuminaXRControllerComponent extends LuminaSceneComponent {
  final LuminaXRHand hand;
  bool isTracked = true;

  // Aim pose (pointing ray for UI interaction)
  final Vector3 aimLocation = Vector3.zero();
  Quaternion aimRotation = Quaternion.identity();

  // Analog input states
  final OpenXrAxisState trigger = OpenXrAxisState();
  final OpenXrAxisState grip = OpenXrAxisState();
  final OpenXrVector2State thumbstick = OpenXrVector2State();

  // Digital button states
  final OpenXrButtonState primaryButton = OpenXrButtonState();
  final OpenXrButtonState secondaryButton = OpenXrButtonState();
  final OpenXrButtonState menuButton = OpenXrButtonState();

  // Last triggered haptic pulse
  OpenXrHapticFeedback? lastHapticPulse;

  LuminaXRControllerComponent({
    super.key,
    required this.hand,
    super.location,
    super.rotation,
  });

  /// Updates controller grip and aim poses from raw OpenXR tracking vectors.
  void updatePoseFromOpenXr({
    required Vector3 openXrGripPos,
    required Quaternion openXrGripRot,
    Vector3? openXrAimPos,
    Quaternion? openXrAimRot,
  }) {
    location = OpenXrSpaceConverter.openXrToLuminaPosition(openXrGripPos);
    rotation = OpenXrSpaceConverter.openXrToLuminaRotation(openXrGripRot);

    if (openXrAimPos != null && openXrAimRot != null) {
      aimLocation.setFrom(OpenXrSpaceConverter.openXrToLuminaPosition(openXrAimPos));
      aimRotation = OpenXrSpaceConverter.openXrToLuminaRotation(openXrAimRot);
    } else {
      aimLocation.setFrom(location);
      aimRotation = rotation;
    }
  }

  /// Plays a haptic vibration pulse on this controller.
  void playHapticPulse({
    double amplitude = 1.0,
    int durationMicroseconds = 25000,
    double frequencyHz = 160.0,
  }) {
    lastHapticPulse = OpenXrHapticFeedback(
      amplitude: amplitude,
      durationMicroseconds: durationMicroseconds,
      frequencyHz: frequencyHz,
    );
  }
}
