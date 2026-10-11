import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_bindings.dart';

/// OpenXR's haptic constants.
abstract final class OpenXrHaptics {
  /// `XR_MIN_HAPTIC_DURATION`: the shortest pulse the device can play.
  static const minDuration = -1;

  /// `XR_FREQUENCY_UNSPECIFIED`: the runtime picks the frequency.
  static const frequencyUnspecified = 0.0;
}

/// A located controller pose in the base space (metres, OpenXR axes).
class OpenXrPose {
  OpenXrPose(vm.Vector3 position, vm.Quaternion orientation)
      : position = position.clone(),
        orientation = orientation.clone();

  final vm.Vector3 position;
  final vm.Quaternion orientation;
}

/// One hand's input after `xrSyncActions`: its poses at the frame's
/// predicted display time (null when not tracked) and its action states.
class OpenXrControllerSample {
  OpenXrControllerSample({
    this.grip,
    this.aim,
    this.gripValue = 0,
    this.triggerValue = 0,
    this.triggerTouched = false,
    vm.Vector2? thumbstick,
    this.thumbstickClick = false,
    this.primary = false,
    this.secondary = false,
    this.menu = false,
  }) : thumbstick = thumbstick ?? vm.Vector2.zero();

  /// The grip pose, null when the controller is not tracked.
  final OpenXrPose? grip;

  /// The aim (pointing) pose, null when not tracked.
  final OpenXrPose? aim;

  final double gripValue;
  final double triggerValue;
  final bool triggerTouched;
  final vm.Vector2 thumbstick;
  final bool thumbstickClick;

  /// X on the left controller, A on the right.
  final bool primary;

  /// Y on the left controller, B on the right.
  final bool secondary;

  /// The menu button (left controller).
  final bool menu;

  bool get tracked => grip != null;
}

/// The input side of a runtime: the action set and its bindings, the
/// per-frame sync, haptics and the current interaction profile. The native
/// bridge ([OpenXrBackend.input] of the native backend) and the simulated
/// headset implement it.
abstract interface class OpenXrInputBackend {
  /// Creates the action set and actions of [bindings], suggests each profile
  /// whose extension the instance has (a profile the runtime refuses is
  /// skipped), attaches them to the session and creates the grip and aim
  /// spaces. Needs a session.
  XrResult setupInput(OpenXrInputBindings bindings);

  /// Whether [setupInput] succeeded.
  bool get inputReady;

  /// The profiles [setupInput] suggested.
  List<String> get suggestedProfiles;

  /// `xrSyncActions`, then both hands (left, right) with their poses located
  /// in [baseSpaceType] at [displayTime] (ns). Null before [setupInput].
  List<OpenXrControllerSample>? syncInput(int baseSpaceType, int displayTime);

  /// A vibration on [hand]: [amplitude] 0..1, [durationNs]
  /// ([OpenXrHaptics.minDuration] for the shortest), [frequency] Hz
  /// ([OpenXrHaptics.frequencyUnspecified]).
  XrResult applyHaptic(LuminaXRHand hand,
      {required double amplitude, required int durationNs, double frequency = OpenXrHaptics.frequencyUnspecified});

  XrResult stopHaptic(LuminaXRHand hand);

  /// The interaction profile the runtime uses for [hand]
  /// (`/interaction_profiles/meta/touch_controller_plus`), or "".
  String interactionProfile(LuminaXRHand hand);
}
