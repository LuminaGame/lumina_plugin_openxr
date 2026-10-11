import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

void main() {
  test('the layout is multiview when the engine and the materials can, per eye otherwise', () {
    final multiview = OpenXrStereoLayout.choose(stereoSupported: true, multiviewMaterials: true);
    expect(multiview.multiview, isTrue);
    expect(multiview.views, 1);
    expect(multiview.layers, 2);
    expect(multiview.swapchains, 1);
    for (final layout in [
      OpenXrStereoLayout.choose(stereoSupported: false, multiviewMaterials: true),
      OpenXrStereoLayout.choose(stereoSupported: true, multiviewMaterials: false),
    ]) {
      expect(layout.multiview, isFalse);
      expect(layout.views, 2);
      expect(layout.swapchains, 2);
      expect(layout.layers, 1);
    }
  });
}
