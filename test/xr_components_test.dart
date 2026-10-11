import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  group('XR Components and Origin Actor Tests', () {
    test('LuminaXROriginActor initializes with HMD and Left/Right controller components', () {
      final origin = LuminaXROriginActor(
        location: Vector3(100.0, 200.0, 0.0),
        trackingOrigin: OpenXrTrackingOrigin.floorLevel,
      );

      expect(origin.hmdComponent, isNotNull);
      expect(origin.leftController, isNotNull);
      expect(origin.rightController, isNotNull);

      expect(origin.leftController.hand, equals(LuminaXRHand.left));
      expect(origin.rightController.hand, equals(LuminaXRHand.right));
      expect(origin.trackingOrigin, equals(OpenXrTrackingOrigin.floorLevel));
    });

    test('LuminaXRHMDComponent computes eye offsets from IPD and updates pose', () {
      final hmd = LuminaXRHMDComponent(
        interPupillaryDistance: 0.064, // 64mm
        location: Vector3(0.0, 170.0, 0.0), // 170 cm eye height (runtime: Y up)
      );

      // In the runtime +X is right. Half-IPD is 3.2 cm.
      expect(hmd.leftEyeLocation.x, closeTo(-3.2, 0.01));
      expect(hmd.rightEyeLocation.x, closeTo(3.2, 0.01));
      expect(hmd.leftEyeLocation.y, closeTo(170.0, 0.01));
      expect(hmd.rightEyeLocation.y, closeTo(170.0, 0.01));

      // Update pose from OpenXR coordinates (0, 1.8m, 0)
      hmd.updatePoseFromOpenXr(Vector3(0.0, 1.8, 0.0), Quaternion.identity());
      expect(hmd.location.y, closeTo(180.0, 0.01));
      expect(hmd.leftEyeLocation.y, closeTo(180.0, 0.01));

      // Turned 90 degrees left (about +Y): the head faces -X and its right is -Z.
      hmd.updatePoseFromOpenXr(Vector3(0.0, 1.8, 0.0), Quaternion.axisAngle(Vector3(0, 1, 0), 1.5707963267948966));
      expect(hmd.rightEyeLocation.z, closeTo(-3.2, 0.01));
      expect(hmd.rightEyeLocation.x, closeTo(0, 0.01));
    });

    test('LuminaXRControllerComponent records pose and triggers haptic pulse', () {
      final controller = LuminaXRControllerComponent(hand: LuminaXRHand.right);
      expect(controller.hand.isRight, isTrue);

      // Update pose from OpenXR: (0.2m, 1.2m, -0.4m)
      controller.updatePoseFromOpenXr(
        openXrGripPos: Vector3(0.2, 1.2, -0.4),
        openXrGripRot: Quaternion.identity(),
      );

      // The runtime has OpenXR's axes in centimetres.
      expect(controller.location.x, closeTo(20.0, 0.01));
      expect(controller.location.y, closeTo(120.0, 0.01));
      expect(controller.location.z, closeTo(-40.0, 0.01));

      // Play haptic pulse
      controller.playHapticPulse(amplitude: 0.75, durationMicroseconds: 50000);
      expect(controller.lastHapticPulse, isNotNull);
      expect(controller.lastHapticPulse!.amplitude, closeTo(0.75, 0.001));
      expect(controller.lastHapticPulse!.durationMicroseconds, equals(50000));
    });
  });
}
