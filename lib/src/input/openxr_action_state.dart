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

/// Single-axis analog trigger/grip input state [0.0..1.0].
class OpenXrAxisState {
  double value = 0.0;
  double previousValue = 0.0;

  double get delta => value - previousValue;

  void update(double newValue) {
    previousValue = value;
    value = newValue.clamp(0.0, 1.0);
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

/// Haptic vibration pulse configuration.
class OpenXrHapticFeedback {
  final double amplitude;
  final int durationMicroseconds;
  final double frequencyHz;

  const OpenXrHapticFeedback({
    this.amplitude = 1.0,
    this.durationMicroseconds = 25000, // 25ms default pulse
    this.frequencyHz = 160.0,
  });
}
