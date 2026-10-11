import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

class _Renderer implements OpenXrEyeRenderer, OpenXrTransparencyAware {
  bool transparent = false;

  @override
  set transparentBackground(bool value) => transparent = value;

  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) => true;
}

class _Underlay implements OpenXrLayerContributor {
  bool on = true;

  @override
  List<OpenXrCompositionLayer> layersBefore(int displayTime) => on ? const [OpenXrCompositionLayer('underlay', 0x1000)] : const [];

  @override
  List<OpenXrCompositionLayer> layersAfter(int displayTime) => const [];

  @override
  int get projectionLayerFlags =>
      on ? OpenXrCompositionLayerFlags.blendTextureSourceAlpha | OpenXrCompositionLayerFlags.unpremultipliedAlpha : 0;

  @override
  int? get environmentBlendMode => null;

  @override
  bool get transparentBackground => on;
}

void main() {
  test('a contributor\'s layer goes under the projection layer, with the alpha flags and a transparent clear', () {
    final sim = SimulatedOpenXrBackend()..initialize();
    final pacer = OpenXrSimulatedPacer(sim, automatic: false);
    final renderer = _Renderer();
    final underlay = _Underlay();
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: renderer)
      ..layerContributors.add(underlay)
      ..start();
    pacer.tick();
    expect(sim.submittedLayers, ['underlay', 'projection']);
    expect(sim.compositions.last.projectionFlags, 0x6);
    expect(renderer.transparent, isTrue);
    pacer.tick();
    expect(sim.compositions, hasLength(1), reason: 'an unchanged composition is not handed over again');
    underlay.on = false;
    pacer.tick();
    expect(sim.submittedLayers, ['projection']);
    expect(renderer.transparent, isFalse);
    loop.stop();
  });

  test('requested extensions are asked for at instance creation; the simulator enables the offered ones', () {
    OpenXrExtensionRequests.add('XR_FB_passthrough');
    addTearDown(() => OpenXrExtensionRequests.remove('XR_FB_passthrough'));
    expect(OpenXrExtensionRequests.all, contains('XR_FB_passthrough'));
    final sim = SimulatedOpenXrBackend()..offeredExtensions.add('XR_FB_passthrough');
    expect(sim.extensionEnabled('XR_FB_passthrough'), isTrue);
  });

  test('another plugin\'s event reaches the session listeners with its type and payload', () {
    final event = OpenXrRuntimeEvent.fromNative(kind: 0, structureType: 1000118030, payload: 4);
    expect(event, isA<OpenXrOtherEvent>());
    expect((event as OpenXrOtherEvent).structureType, 1000118030);
    expect(event.payload, 4);
  });
}
