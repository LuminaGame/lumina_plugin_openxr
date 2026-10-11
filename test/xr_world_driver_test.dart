import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/lumina.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// A gameplay component that reads the head in its tick.
class _HeadReader extends LuminaActorComponent {
  _HeadReader(this.origin);
  final LuminaXROriginActor origin;
  final List<double> seenHeights = [];

  @override
  void onTick(double deltaTime) => seenHeights.add(origin.hmdComponent.location.y);
}

class _NoRenderer implements OpenXrEyeRenderer {
  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) => true;
}

void main() {
  test("a component reading the head in onTick sees this frame's pose", () {
    final world = LuminaWorld(worldType: LuminaWorldType.game);
    final origin = LuminaXROriginActor();
    final reader = _HeadReader(origin);
    origin.addComponent(reader);
    world.beginPlay();
    world.spawnActorImmediately(origin);

    final simulator = SimulatedOpenXrBackend();
    final pacer = OpenXrSimulatedPacer(simulator, automatic: false);
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: _NoRenderer());
    LuminaXRWorldDriver(world: world, origin: origin).attach(loop);
    loop.start();
    final heights = [1.50, 1.62, 1.71];
    for (final h in heights) {
      simulator.headPosition = vm.Vector3(0, h, 0);
      pacer.tick();
    }
    // Centimetres, runtime axes: the head of the frame being ticked, not the previous one.
    expect(reader.seenHeights.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(reader.seenHeights[i], closeTo(heights[i] * 100, 1e-6));
    }
    expect(origin.hmdComponent.interPupillaryDistance, closeTo(simulator.interPupillaryDistance, 1e-9));
  });
}
