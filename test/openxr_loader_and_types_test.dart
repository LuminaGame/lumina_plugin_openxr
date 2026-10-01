import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

void main() {
  group('OpenXR Types and Loader Tests', () {
    test('XrResult conforms to Khronos specification values', () {
      expect(XrResult.success.value, equals(0));
      expect(XrResult.timeoutExpired.value, equals(1));
      expect(XrResult.sessionLossPending.value, equals(3));
      expect(XrResult.errorValidationFailure.value, equals(-1));
      expect(XrResult.errorRuntimeFailure.value, equals(-2));
      expect(XrResult.errorInitializationFailed.value, equals(-5));
      expect(XrResult.errorInstanceLost.value, equals(-12));

      expect(XrResult.success.isSuccess, isTrue);
      expect(XrResult.success.isFailure, isFalse);
      expect(XrResult.errorRuntimeFailure.isSuccess, isFalse);
      expect(XrResult.errorRuntimeFailure.isFailure, isTrue);
    });

    test('Simulated OpenXR backend initializes and exposes default HMD parameters', () {
      final sim = SimulatedOpenXrBackend();
      expect(sim.isInitialized, isFalse);
      expect(sim.sessionState, equals(OpenXrSessionState.idle));

      final res = sim.initialize();
      expect(res.isSuccess, isTrue);
      expect(sim.isInitialized, isTrue);
      expect(sim.sessionState, equals(OpenXrSessionState.ready));

      expect(sim.systemName, equals('Lumina Virtual OpenXR HMD'));
      expect(sim.recommendedImageRectWidth, equals(2064));
      expect(sim.recommendedImageRectHeight, equals(2208));
      expect(sim.displayRefreshRate, equals(90.0));
      expect(sim.interPupillaryDistance, closeTo(0.064, 0.0001));

      // Left eye view
      final leftView = sim.getLeftEyeView();
      expect(leftView.position.x, closeTo(-0.032, 0.001));
      expect(leftView.fovLeft, lessThan(0));
      expect(leftView.fovRight, greaterThan(0));

      // Right eye view
      final rightView = sim.getRightEyeView();
      expect(rightView.position.x, closeTo(0.032, 0.001));
    });

    test('OpenXrBindings falls back cleanly to simulation mode', () {
      final bindings = OpenXrBindings.instance;
      expect(bindings.activeRuntimeName, isNotEmpty);
      expect(bindings.simulator, isNotNull);

      bindings.setForceSimulation(true);
      expect(bindings.isSimulated, isTrue);
      expect(bindings.activeRuntimeName, equals('Lumina Simulated HMD'));

      final initRes = bindings.initialize();
      expect(initRes.isSuccess, isTrue);
    });
  });
}
