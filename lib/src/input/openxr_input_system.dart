import 'package:logging/logging.dart';
import 'package:lumina/lumina.dart';

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_controller_component.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_origin_actor.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_action_state.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_blueprint_nodes.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_backend.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_bindings.dart';

final _log = Logger('OpenXR.input');

/// The controllers' keys in the project's input (Project Settings binds
/// them like any key).
abstract final class LuminaXRKeys {
  static ({
    LuminaKey grip,
    LuminaKey trigger,
    LuminaKey stickX,
    LuminaKey stickY,
    LuminaKey stickClick,
    LuminaKey primary,
    LuminaKey secondary,
    LuminaKey? menu,
  }) of(LuminaXRHand hand) => hand.isLeft
      ? (
          grip: LuminaKey.xrLeftGrip,
          trigger: LuminaKey.xrLeftTrigger,
          stickX: LuminaKey.xrLeftThumbstickX,
          stickY: LuminaKey.xrLeftThumbstickY,
          stickClick: LuminaKey.xrLeftThumbstickClick,
          primary: LuminaKey.xrLeftX,
          secondary: LuminaKey.xrLeftY,
          menu: LuminaKey.xrLeftMenu,
        )
      : (
          grip: LuminaKey.xrRightGrip,
          trigger: LuminaKey.xrRightTrigger,
          stickX: LuminaKey.xrRightThumbstickX,
          stickY: LuminaKey.xrRightThumbstickY,
          stickClick: LuminaKey.xrRightThumbstickClick,
          primary: LuminaKey.xrRightA,
          secondary: LuminaKey.xrRightB,
          menu: null,
        );
}

/// Feeds the two [LuminaXRControllerComponent]s from the runtime each frame:
/// `xrSyncActions`, the grip and aim poses located at the frame's predicted
/// display time (converted to runtime axes, cm), grip / trigger with
/// hysteresis, thumbstick, buttons and tracking. The same frame's values go
/// to the world's [LuminaInputSubsystem] as the XR keys, and the
/// controllers' haptic pulses go to the runtime.
///
/// Registered as a world subsystem ([attachTo]), the Blueprint XR nodes find
/// it through the world. `OpenXrFrameLoop.input` calls [sync] before the
/// world ticks.
class OpenXrInputSystem extends LuminaWorldSubsystem {
  OpenXrInputSystem({
    required this.backend,
    required this.left,
    required this.right,
    this.baseSpaceType = OpenXrReferenceSpaceType.localFloor,
  }) {
    for (final c in [left, right]) {
      c.hapticSink = _haptic;
    }
  }

  /// The input of [origin]'s two controllers.
  factory OpenXrInputSystem.forOrigin(OpenXrInputBackend backend, LuminaXROriginActor origin,
          {int baseSpaceType = OpenXrReferenceSpaceType.localFloor}) =>
      OpenXrInputSystem(
          backend: backend, left: origin.leftController, right: origin.rightController, baseSpaceType: baseSpaceType);

  final OpenXrInputBackend backend;
  final LuminaXRControllerComponent left;
  final LuminaXRControllerComponent right;

  /// The reference space the poses are located in (the session's).
  int baseSpaceType;

  /// Where the XR keys go; by default the world's input subsystem.
  LuminaInputSubsystem? keys;

  final Map<LuminaXRHand, String> _profiles = {};
  final Set<LuminaKey> _held = {};
  int _frames = 0;

  LuminaXRControllerComponent controller(LuminaXRHand hand) => hand.isLeft ? left : right;

  /// The interaction profile the runtime last reported for [hand].
  String interactionProfile(LuminaXRHand hand) => _profiles[hand] ?? '';

  /// Frames synced.
  int get frames => _frames;

  /// Creates the actions of [bindings] (the shipped ones by default) and
  /// attaches them. Needs a session.
  XrResult setup([OpenXrInputBindings? bindings]) {
    final r = backend.setupInput(bindings ?? OpenXrInputBindings.defaults);
    _log.info('input ${r.name}; profiles suggested: ${backend.suggestedProfiles.join(', ')}');
    return r;
  }

  /// Registers this as [world]'s subsystem (the Blueprint nodes find it) and
  /// sends the XR keys to the world's input.
  void attachTo(LuminaWorld world) {
    OpenXrBlueprintNodes.register();
    world.registerSubsystem<OpenXrInputSystem>(this);
  }

  /// Asks the runtime which interaction profile each hand uses (after an
  /// `INTERACTION_PROFILE_CHANGED` event).
  void refreshInteractionProfiles() {
    for (final hand in LuminaXRHand.values) {
      final profile = backend.interactionProfile(hand);
      if (_profiles[hand] != profile) _log.info('${hand.name} interaction profile: ${profile.isEmpty ? 'none' : profile}');
      _profiles[hand] = profile;
    }
  }

  /// One frame: sync, then the controllers and the keys. [displayTime] is the
  /// frame's predicted display time (ns).
  void sync(int displayTime) {
    final samples = backend.syncInput(baseSpaceType, displayTime);
    if (samples == null || samples.length < 2) return;
    _frames++;
    if (_frames == 1) refreshInteractionProfiles();
    final input = keys ?? world?.getSubsystem<LuminaInputSubsystem>();
    for (final hand in LuminaXRHand.values) {
      final c = controller(hand);
      final s = samples[hand.index];
      apply(c, s);
      if (input != null) _inject(input, hand, c);
    }
  }

  /// Writes [sample] into [c]. An untracked controller keeps its last pose.
  static void apply(LuminaXRControllerComponent c, OpenXrControllerSample sample) {
    final grip = sample.grip;
    c.isTracked = grip != null;
    if (grip != null) {
      final aim = sample.aim;
      c.updatePoseFromOpenXr(
        openXrGripPos: grip.position,
        openXrGripRot: grip.orientation,
        openXrAimPos: aim?.position,
        openXrAimRot: aim?.orientation,
      );
    }
    c.gripAxis.update(sample.gripValue);
    c.triggerAxis.update(sample.triggerValue);
    c.triggerTouched = sample.triggerTouched;
    c.thumbstick.update(sample.thumbstick.x, sample.thumbstick.y);
    c.thumbstickButton.update(sample.thumbstickClick);
    c.primaryButton.update(sample.primary);
    c.secondaryButton.update(sample.secondary);
    c.menuButton.update(sample.menu);
  }

  void _inject(LuminaInputSubsystem input, LuminaXRHand hand, LuminaXRControllerComponent c) {
    final k = LuminaXRKeys.of(hand);
    void analog(LuminaKey key, double value) {
      if (value != 0) input.injectAnalog(key, value);
    }

    void digital(LuminaKey? key, bool down) {
      if (key == null) return;
      if (down && _held.add(key)) input.injectKeyDown(key);
      if (!down && _held.remove(key)) input.injectKeyUp(key);
    }

    analog(k.grip, c.gripAxis.value);
    analog(k.trigger, c.triggerAxis.value);
    analog(k.stickX, c.thumbstick.x);
    analog(k.stickY, c.thumbstick.y);
    digital(k.stickClick, c.thumbstickButton.isPressed);
    digital(k.primary, c.primaryButton.isPressed);
    digital(k.secondary, c.secondaryButton.isPressed);
    digital(k.menu, c.menuButton.isPressed);
  }

  void _haptic(LuminaXRHand hand, OpenXrHapticFeedback pulse) {
    final r = backend.applyHaptic(hand,
        amplitude: pulse.amplitude, durationNs: pulse.durationNanoseconds, frequency: pulse.frequencyHz);
    if (r.isFailure) _log.warning('haptic pulse on ${hand.name}: ${r.name}');
  }
}
