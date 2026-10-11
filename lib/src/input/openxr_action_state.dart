import 'package:vector_math/vector_math_64.dart' as vm;

/// Supported OpenXR action types.
enum OpenXrActionType {
  booleanInput,
  floatInput,
  vector2Input,
  poseInput,
  vibrationOutput,
}

/// Digital button state (e.g. A/B/X/Y or Menu buttons).
class OpenXrButtonState {
  bool isPressed = false;
  bool isTouched = false;
  bool wasPressed = false;

  bool get justPressed => isPressed && !wasPressed;
  bool get justReleased => !isPressed && wasPressed;

  void update(bool pressed, {bool touched = false}) {
    wasPressed = isPressed;
    isPressed = pressed;
    isTouched = touched;
  }
}

/// Single-axis analog trigger/grip input state [0.0..1.0], with a pressed
/// state through hysteresis: pressed above [pressThreshold], released below
/// [releaseThreshold], unchanged in between (a half-held grip does not
/// flicker).
class OpenXrAxisState {
  OpenXrAxisState({this.pressThreshold = 0.7, this.releaseThreshold = 0.3});

  final double pressThreshold;
  final double releaseThreshold;

  double value = 0.0;
  double previousValue = 0.0;
  bool isPressed = false;
  bool wasPressed = false;

  double get delta => value - previousValue;
  bool get justPressed => isPressed && !wasPressed;
  bool get justReleased => !isPressed && wasPressed;

  void update(double newValue) {
    previousValue = value;
    value = newValue.clamp(0.0, 1.0);
    wasPressed = isPressed;
    if (!isPressed && value > pressThreshold) {
      isPressed = true;
    } else if (isPressed && value < releaseThreshold) {
      isPressed = false;
    }
  }
}

/// Dual-axis thumbstick or touchpad input state [-1.0..1.0].
class OpenXrVector2State {
  vm.Vector2 value = vm.Vector2.zero();
  vm.Vector2 previousValue = vm.Vector2.zero();

  double get x => value.x;
  double get y => value.y;

  void update(double newX, double newY) {
    previousValue.setFrom(value);
    value.x = newX.clamp(-1.0, 1.0);
    value.y = newY.clamp(-1.0, 1.0);
  }
}

/// A haptic vibration pulse: amplitude 0..1, duration in seconds, frequency
/// in Hz (0: the runtime picks it).
class OpenXrHapticFeedback {
  final double amplitude;
  final double seconds;
  final double frequencyHz;

  const OpenXrHapticFeedback({
    this.amplitude = 1.0,
    this.seconds = 0.025,
    this.frequencyHz = 0.0,
  });

  /// The duration in nanoseconds as OpenXR takes it; -1
  /// (`XR_MIN_HAPTIC_DURATION`) for a zero or negative duration.
  int get durationNanoseconds => seconds <= 0 ? -1 : (seconds * 1e9).round();
}
