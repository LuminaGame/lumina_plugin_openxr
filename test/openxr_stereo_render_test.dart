import 'package:flutter_filament/flutter_filament.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

void main() {
  group('OpenXR Stereoscopic Render Tests', () {
    test('OpenXrStereoView generates asymmetric projection matrix without NaN or Inf', () {
      final leftEyeView = OpenXrStereoView(
        eyePosition: vm.Vector3(-0.032, 1.7, 0.0),
        eyeOrientation: vm.Quaternion.identity(),
        angleLeft: -0.85, // radians (~49 deg)
        angleRight: 0.90, // radians (~52 deg)
        angleUp: 0.85,
        angleDown: -0.85,
      );

      final projMat = leftEyeView.createProjectionMatrix(nearPlane: 0.1, farPlane: 1000.0);
      expect(projMat, isNotNull);

      // Verify matrix values are finite
      for (var i = 0; i < 16; i++) {
        expect(projMat.storage[i].isNaN, isFalse);
        expect(projMat.storage[i].isInfinite, isFalse);
      }

      // In asymmetric projection, row 0 column 2 (a02) encodes nasal/temporal asymmetry
      // Since |angleRight| != |angleLeft|, a02 != 0
      final a02 = projMat.entry(0, 2);
      expect(a02.abs(), greaterThan(0.001));

      // View matrix should be valid
      final viewMat = leftEyeView.createViewMatrix();
      expect(viewMat.entry(3, 0), closeTo(0.032, 0.001)); // inverse translation
    });

    test('OpenXrFilamentBridge maps stereo mode to Filament StereoscopicType properly', () {
      final bridge = OpenXrFilamentBridge(stereoMode: OpenXrStereoMode.instanced);
      expect(bridge.filamentStereoType, equals(StereoscopicType.instanced));

      bridge.stereoMode = OpenXrStereoMode.multiview;
      expect(bridge.filamentStereoType, equals(StereoscopicType.multiview));

      bridge.stereoMode = OpenXrStereoMode.separateViews;
      expect(bridge.filamentStereoType, equals(StereoscopicType.none));
    });
  });
}
