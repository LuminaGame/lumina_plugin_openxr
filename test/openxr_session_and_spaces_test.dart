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
      // The simulated runtime posts READY, then SYNCHRONIZED, VISIBLE and FOCUSED once the session began.
      expect(session.state, equals(OpenXrSessionState.focused));
      expect(session.machine.history,
          [OpenXrSessionState.ready, OpenXrSessionState.synchronized, OpenXrSessionState.visible, OpenXrSessionState.focused]);

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
      // In Lumina's authoring axes (LuminaAxes) forward is +Y, 100 cm
      expect(luminaForward.x, closeTo(0.0, 0.001));
      expect(luminaForward.y, closeTo(100.0, 0.001));
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

    test('the action states track button, axis, and vector2 inputs', () {
      // Trigger axis
      final trigger = OpenXrAxisState();
      expect(trigger.value, equals(0.0));
      trigger.update(0.85);
      expect(trigger.value, closeTo(0.85, 0.001));
      expect(trigger.delta, closeTo(0.85, 0.001));

      // Button press
      final primary = OpenXrButtonState();
      expect(primary.isPressed, isFalse);
      primary.update(true);
      expect(primary.isPressed, isTrue);
      expect(primary.justPressed, isTrue);

      primary.update(true);
      expect(primary.justPressed, isFalse);

      // Thumbstick
      final stick = OpenXrVector2State()..update(-0.5, 0.75);
      expect(stick.x, closeTo(-0.5, 0.001));
      expect(stick.y, closeTo(0.75, 0.001));
    });
  });
}
