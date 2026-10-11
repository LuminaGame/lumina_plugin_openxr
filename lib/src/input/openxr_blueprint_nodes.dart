import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:lumina_plugin_openxr/src/components/lumina_xr_controller_component.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_system.dart';

/// The XR controller functions the Blueprint nodes call. The controllers
/// are the ones of the [OpenXrInputSystem] registered in the actor's world;
/// without one a node reads an untracked, released controller and a pulse
/// does nothing. [hand] is `Left` or `Right` (any case).
abstract final class OpenXrBlueprintFunctions {
  static LuminaXRControllerComponent? controller(LuminaActor self, String hand) {
    final system = self.world?.getSubsystem<OpenXrInputSystem>();
    if (system == null) return null;
    return system.controller(hand.trim().toLowerCase() == 'right' ? LuminaXRHand.right : LuminaXRHand.left);
  }

  static Map<String, Object?> _transform(Vector3 location, Quaternion rotation) =>
      LuminaBlueprintFunctionLibrary.makeTransform(LuminaBlueprintFunctionLibrary.toAuthoring(location),
          LuminaBlueprintFunctionLibrary.fromControlRotation(luminaPawnQuaternionToEuler(rotation)), Vector3.all(1));

  /// The grip pose in the world (authoring axes, cm).
  static Map<String, Object?> gripTransform(LuminaActor self, String hand) {
    final c = controller(self, hand);
    return c == null ? _transform(Vector3.zero(), Quaternion.identity()) : _transform(c.worldLocation, c.worldRotation);
  }

  /// The aim (pointing) pose in the world (authoring axes, cm).
  static Map<String, Object?> aimTransform(LuminaActor self, String hand) {
    final c = controller(self, hand);
    return c == null
        ? _transform(Vector3.zero(), Quaternion.identity())
        : _transform(c.aimWorldLocation, c.aimWorldRotation);
  }

  static double gripValue(LuminaActor self, String hand) => controller(self, hand)?.gripAxis.value ?? 0.0;

  static double triggerValue(LuminaActor self, String hand) => controller(self, hand)?.triggerAxis.value ?? 0.0;

  static bool isTracked(LuminaActor self, String hand) => controller(self, hand)?.isTracked ?? false;

  /// A haptic pulse on the controller (the runtime's vibration).
  static void playHapticPulse(LuminaActor self, String hand, double amplitude, double seconds, double frequency) =>
      controller(self, hand)?.playHapticPulse(amplitude: amplitude, seconds: seconds, frequencyHz: frequency);
}

/// The XR Blueprint nodes: Get Controller Grip / Aim Transform, Get Grip /
/// Trigger Value, Play Haptic Pulse, Is Controller Tracked.
abstract final class OpenXrBlueprintNodes {
  static const _category = 'XR|Controllers';
  static const _color = 0xFF00897B;
  static const _library = 'package:lumina_plugin_openxr/runtime.dart';
  static const _hand = LuminaBlueprintPinSpec('hand', 'Hand', LuminaPinType.name, defaultValue: 'Left');

  static const gripTransformId = 'openxr_get_controller_grip_transform';
  static const aimTransformId = 'openxr_get_controller_aim_transform';
  static const gripValueId = 'openxr_get_grip_value';
  static const triggerValueId = 'openxr_get_trigger_value';
  static const playHapticPulseId = 'openxr_play_haptic_pulse';
  static const isTrackedId = 'openxr_is_controller_tracked';

  static const ids = [gripTransformId, aimTransformId, gripValueId, triggerValueId, playHapticPulseId, isTrackedId];

  static LuminaBlueprintNodeSpec _pure(String id, String title, LuminaPinType type, String tooltip,
          {List<String> keywords = const []}) =>
      LuminaBlueprintNodeSpec(
        id: id,
        title: title,
        category: _category,
        kind: LuminaBlueprintNodeKind.pure,
        headerColor: _color,
        keywords: ['xr', 'vr', 'controller', ...keywords],
        tooltip: tooltip,
        inputs: const [_hand],
        outputs: [LuminaBlueprintPinSpec('return_value', 'Return Value', type)],
      );

  static LuminaBlueprintCallShape _call(String method) =>
      LuminaBlueprintCallShape('OpenXrBlueprintFunctions.$method', const ['hand'],
          self: true, library: _library, outputs: const ['return_value']);

  /// Registers the nodes once (a game's runtime start; `OpenXrInputSystem.attachTo` calls it).
  static void register() {
    if (LuminaBlueprintFunctionRegistry.entry(gripTransformId) != null) return;
    String hand(Map<String, Object?> i) => i['hand'] as String? ?? 'Left';
    double number(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

    LuminaBlueprintFunctionRegistry.register(
      _pure(gripTransformId, 'Get Controller Grip Transform', LuminaPinType.transform,
          'The controller\'s grip pose in the world at this frame\'s predicted display time.', keywords: ['pose', 'hand']),
      (c, i) => {'return_value': OpenXrBlueprintFunctions.gripTransform(c.self, hand(i))},
      call: _call('gripTransform'),
    );
    LuminaBlueprintFunctionRegistry.register(
      _pure(aimTransformId, 'Get Controller Aim Transform', LuminaPinType.transform,
          'The controller\'s pointing pose in the world (its forward is the ray).', keywords: ['pose', 'ray', 'point']),
      (c, i) => {'return_value': OpenXrBlueprintFunctions.aimTransform(c.self, hand(i))},
      call: _call('aimTransform'),
    );
    LuminaBlueprintFunctionRegistry.register(
      _pure(gripValueId, 'Get Grip Value', LuminaPinType.float, 'How far the grip (squeeze) is pressed, 0 to 1.',
          keywords: ['squeeze', 'grab']),
      (c, i) => {'return_value': OpenXrBlueprintFunctions.gripValue(c.self, hand(i))},
      call: _call('gripValue'),
    );
    LuminaBlueprintFunctionRegistry.register(
      _pure(triggerValueId, 'Get Trigger Value', LuminaPinType.float, 'How far the trigger is pressed, 0 to 1.',
          keywords: ['select', 'index']),
      (c, i) => {'return_value': OpenXrBlueprintFunctions.triggerValue(c.self, hand(i))},
      call: _call('triggerValue'),
    );
    LuminaBlueprintFunctionRegistry.register(
      _pure(isTrackedId, 'Is Controller Tracked', LuminaPinType.boolean, 'Whether the runtime tracks the controller now.'),
      (c, i) => {'return_value': OpenXrBlueprintFunctions.isTracked(c.self, hand(i))},
      call: _call('isTracked'),
    );
    LuminaBlueprintFunctionRegistry.register(
      const LuminaBlueprintNodeSpec(
        id: playHapticPulseId,
        title: 'Play Haptic Pulse',
        category: _category,
        kind: LuminaBlueprintNodeKind.impure,
        headerColor: _color,
        keywords: ['xr', 'vr', 'controller', 'vibrate', 'rumble', 'haptics'],
        tooltip: 'Vibrates the controller: amplitude 0 to 1, for seconds (0: the shortest pulse), '
            'at frequency Hz (0: the runtime picks).',
        inputs: [
          LuminaBlueprintPinSpec('exec_in', 'Exec In', LuminaPinType.exec),
          _hand,
          LuminaBlueprintPinSpec('amplitude', 'Amplitude', LuminaPinType.float, defaultValue: 1.0),
          LuminaBlueprintPinSpec('seconds', 'Seconds', LuminaPinType.float, defaultValue: 0.05),
          LuminaBlueprintPinSpec('frequency', 'Frequency', LuminaPinType.float, defaultValue: 0.0),
        ],
        outputs: [LuminaBlueprintPinSpec('exec_out', 'Exec Out', LuminaPinType.exec)],
      ),
      (c, i) {
        OpenXrBlueprintFunctions.playHapticPulse(
            c.self, hand(i), number(i['amplitude'], 1.0), number(i['seconds'], 0.05), number(i['frequency'], 0.0));
        return const {};
      },
      call: const LuminaBlueprintCallShape('OpenXrBlueprintFunctions.playHapticPulse',
          ['hand', 'amplitude', 'seconds', 'frequency'],
          self: true, library: _library),
    );
  }

  /// Removes the nodes (tests).
  static void unregister() {
    for (final id in ids) {
      LuminaBlueprintFunctionRegistry.unregister(id);
    }
  }
}
