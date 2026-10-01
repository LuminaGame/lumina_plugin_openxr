import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  group('OpenXR Session and Spaces Tests', () {
    test('OpenXrSession state machine transitions properly', () {
      final session = OpenXrSession();
      expect(session.state, equals(OpenXrSessionState.idle));
      expect(session.trackingOrigin, equals(OpenXrTrackingOrigin.floorLevel));

      final beginRes = session.beginSession();
      expect(beginRes.isSuccess, isTrue);
      expect(session.state, equals(OpenXrSessionState.focused));

      session.setTrackingOrigin(OpenXrTrackingOrigin.eyeLevel);
      expect(session.trackingOrigin, equals(OpenXrTrackingOrigin.eyeLevel));

      final endRes = session.endSession();
      expect(endRes.isSuccess, isTrue);
      expect(session.state, equals(OpenXrSessionState.stopping));
    });

    test('OpenXrSpaceConverter converts meters Y-up to centimeters Z-up correctly', () {
      // 1 meter forward in OpenXR is (0, 0, -1)
      final openXrForward = vm.Vector3(0.0, 0.0, -1.0);
      final luminaForward = OpenXrSpaceConverter.openXrToLuminaPosition(openXrForward);
      // In Lumina, forward is +X, 100 cm
      expect(luminaForward.x, closeTo(100.0, 0.001));
      expect(luminaForward.y, closeTo(0.0, 0.001));
      expect(luminaForward.z, closeTo(0.0, 0.001));

      // 1.5 meters up in OpenXR is (0, 1.5, 0)
      final openXrUp = vm.Vector3(0.0, 1.5, 0.0);
      final luminaUp = OpenXrSpaceConverter.openXrToLuminaPosition(openXrUp);
      // In Lumina, up is +Z, 150 cm
      expect(luminaUp.x, closeTo(0.0, 0.001));
      expect(luminaUp.y, closeTo(0.0, 0.001));
      expect(luminaUp.z, closeTo(150.0, 0.001));

      // Round-trip
      final roundTrip = OpenXrSpaceConverter.luminaToOpenXrPosition(luminaForward);
      expect(roundTrip.x, closeTo(openXrForward.x, 0.001));
      expect(roundTrip.y, closeTo(openXrForward.y, 0.001));
      expect(roundTrip.z, closeTo(openXrForward.z, 0.001));
    });

    test('OpenXrActionSet tracks button, axis, and vector2 inputs', () {
      final actions = OpenXrActionSet();

      // Trigger axis
      expect(actions.leftTrigger.value, equals(0.0));
      actions.leftTrigger.update(0.85);
      expect(actions.leftTrigger.value, closeTo(0.85, 0.001));
      expect(actions.leftTrigger.delta, closeTo(0.85, 0.001));

      // Button press
      expect(actions.rightPrimary.isPressed, isFalse);
      actions.rightPrimary.update(true);
      expect(actions.rightPrimary.isPressed, isTrue);
      expect(actions.rightPrimary.justPressed, isTrue);

      actions.rightPrimary.update(true);
      expect(actions.rightPrimary.justPressed, isFalse);

      // Thumbstick
      actions.leftThumbstick.update(-0.5, 0.75);
      expect(actions.leftThumbstick.x, closeTo(-0.5, 0.001));
      expect(actions.leftThumbstick.y, closeTo(0.75, 0.001));
    });
  });
}
