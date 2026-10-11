import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/xr_types.dart';

void main() {
  test('grip 0.2 → 0.75 → 0.5 → 0.25: pressed at 0.75, still held at 0.5, released at 0.25', () {
    final grip = OpenXrAxisState();
    final seen = <(double, bool, bool, bool)>[];
    for (final v in [0.2, 0.75, 0.5, 0.25]) {
      grip.update(v);
      seen.add((v, grip.isPressed, grip.justPressed, grip.justReleased));
    }
    expect(seen, [
      (0.2, false, false, false),
      (0.75, true, true, false),
      (0.5, true, false, false),
      (0.25, false, false, true),
    ]);
  });

  test('a value between the thresholds never toggles', () {
    final trigger = OpenXrAxisState();
    for (final v in [0.69, 0.31, 0.5, 0.65]) {
      trigger.update(v);
      expect(trigger.isPressed, isFalse, reason: '$v');
    }
    trigger.update(0.71);
    for (final v in [0.31, 0.5, 0.69]) {
      trigger.update(v);
      expect(trigger.isPressed, isTrue, reason: '$v');
    }
  });
}
