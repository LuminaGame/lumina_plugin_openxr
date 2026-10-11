import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

void main() {
  test('playHapticPulse(0.6, 0.05 s, 0) reaches the runtime: amplitude 0.6, 50 000 000 ns, frequency unspecified', () {
    final sim = SimulatedOpenXrBackend()..initialize();
    final origin = LuminaXROriginActor();
    OpenXrInputSystem.forOrigin(sim.input, origin).setup();
    origin.rightController.playHapticPulse(amplitude: 0.6, seconds: 0.05, frequencyHz: 0);
    final pulse = sim.hapticPulses.single;
    expect(pulse.hand, LuminaXRHand.right);
    expect(pulse.amplitude, 0.6);
    expect(pulse.durationNs, 50000000);
    expect(pulse.frequency, OpenXrHaptics.frequencyUnspecified);
  });

  test('a zero duration asks for the shortest pulse; the amplitude is clamped to 0..1', () {
    final sim = SimulatedOpenXrBackend()..initialize();
    final origin = LuminaXROriginActor();
    OpenXrInputSystem.forOrigin(sim.input, origin).setup();
    origin.leftController.playHapticPulse(amplitude: 3, seconds: 0, frequencyHz: 160);
    expect(sim.hapticPulses.single.durationNs, OpenXrHaptics.minDuration);
    expect(sim.hapticPulses.single.amplitude, 1.0);
    expect(sim.hapticPulses.single.frequency, 160);
  });

  test('without an input system the pulse is only recorded', () {
    final controller = LuminaXRControllerComponent(hand: LuminaXRHand.left)..playHapticPulse(amplitude: 0.2);
    expect(controller.lastHapticPulse!.amplitude, 0.2);
  });
}
