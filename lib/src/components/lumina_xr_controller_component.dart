import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_action_state.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_space.dart';

/// Where a controller's haptic pulses go: the runtime (set by
/// `OpenXrInputSystem`), or nowhere before one is attached.
typedef LuminaXRHapticSink = void Function(LuminaXRHand hand, OpenXrHapticFeedback pulse);

/// A tracked motion controller under the XR origin: its grip pose (this
/// component's transform, runtime axes, cm), its aim pose, the grip,
/// trigger, thumbstick and button states, and haptics.
///
/// `OpenXrInputSystem` writes it every frame with the poses located at the
/// frame's predicted display time, before the world ticks. It is a
/// [LuminaGrabber], so the pose grab interaction takes it as it takes the
/// mouse in Play-In-Editor.
class LuminaXRControllerComponent extends LuminaSceneComponent implements LuminaGrabber {
  final LuminaXRHand hand;

  /// Whether the runtime tracks the controller now. An untracked controller
  /// keeps its last pose.
  @override
  bool isTracked = true;

  /// The aim pose (the pointing ray) relative to the XR origin, like the grip.
  final Vector3 aimLocation = Vector3.zero();
  Quaternion aimRotation = Quaternion.identity();

  /// Grip (squeeze) and trigger values with pressed / released hysteresis
  /// (press above 0.7, release below 0.3).
  final OpenXrAxisState gripAxis = OpenXrAxisState();
  final OpenXrAxisState triggerAxis = OpenXrAxisState();
  final OpenXrVector2State thumbstick = OpenXrVector2State();

  /// X / A.
  final OpenXrButtonState primaryButton = OpenXrButtonState();

  /// Y / B.
  final OpenXrButtonState secondaryButton = OpenXrButtonState();
  final OpenXrButtonState menuButton = OpenXrButtonState();
  final OpenXrButtonState thumbstickButton = OpenXrButtonState();
  bool triggerTouched = false;

  /// The last haptic pulse played.
  OpenXrHapticFeedback? lastHapticPulse;

  /// Receives the pulses (the runtime's haptics); null records only.
  LuminaXRHapticSink? hapticSink;

  LuminaXRControllerComponent({
    super.key,
    required this.hand,
    super.location,
    super.rotation,
  });

  /// Sets the grip (and aim) pose from OpenXR values (metres, OpenXR axes,
  /// relative to the tracking origin). Without an aim pose the aim follows
  /// the grip.
  void updatePoseFromOpenXr({
    required Vector3 openXrGripPos,
    required Quaternion openXrGripRot,
    Vector3? openXrAimPos,
    Quaternion? openXrAimRot,
  }) {
    // Lumina's runtime has OpenXR's axes, in centimetres.
    location = OpenXrSpaceConverter.openXrToRuntimePosition(openXrGripPos);
    rotation = OpenXrSpaceConverter.openXrToRuntimeRotation(openXrGripRot);

    if (openXrAimPos != null && openXrAimRot != null) {
      aimLocation.setFrom(OpenXrSpaceConverter.openXrToRuntimePosition(openXrAimPos));
      aimRotation = OpenXrSpaceConverter.openXrToRuntimeRotation(openXrAimRot);
    } else {
      aimLocation.setFrom(location);
      aimRotation = rotation;
    }
  }

  /// Plays a haptic pulse: [amplitude] 0..1, [seconds] long (0: the shortest
  /// the device can play), at [frequencyHz] (0: the runtime picks).
  void playHapticPulse({double amplitude = 1.0, double seconds = 0.025, double frequencyHz = 0.0}) {
    final pulse = OpenXrHapticFeedback(amplitude: amplitude.clamp(0.0, 1.0), seconds: seconds, frequencyHz: frequencyHz);
    lastHapticPulse = pulse;
    hapticSink?.call(hand, pulse);
  }

  /// The aim pose in the world (runtime axes, cm).
  Vector3 get aimWorldLocation {
    final parent = parentComponent;
    return parent == null ? aimLocation.clone() : parent.worldLocation + parent.worldRotation.rotateVector(aimLocation);
  }

  Quaternion get aimWorldRotation {
    final parent = parentComponent;
    return parent == null ? aimRotation : parent.worldRotation * aimRotation;
  }

  // --- LuminaGrabber ---------------------------------------------------------

  @override
  String get id => hand.name;

  /// The grip pose in the world with unit scale: this frame's located pose,
  /// unsmoothed.
  @override
  Matrix4 get worldTransform => Matrix4.compose(worldLocation, worldRotation, Vector3.all(1));

  @override
  double get grip => gripAxis.value;

  /// Along the aim pose's forward (−Z).
  @override
  LuminaGrabRay? get ray => LuminaGrabRay(aimWorldLocation, aimWorldRotation.rotateVector(Vector3(0, 0, -1)));

  @override
  void pulse(double amplitude, double seconds) => playHapticPulse(amplitude: amplitude, seconds: seconds);

  /// A controller holds at its grip; nothing to move.
  @override
  void grabbedAt(Vector3 point) {}
}
