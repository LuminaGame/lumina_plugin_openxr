// OpenXR frame loop smoke: the simulated headset paces frames, the head turns,
// and the same renderer a headset uses (multiview, both eyes in one pass)
// draws a barrel and an AC unit from test-assets into an external two-layer
// image on the desktop GPU. Both eyes side by side, with per-frame CPU and
// GPU times in the metrics.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_filament/filament.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:lumina_smoke/lumina_smoke.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const _name = 'OpenXR frame loop smoke both eyes of a barrel and an AC unit as the simulated head turns';

void main() {
  const eyeWidth = 768; // the simulated eyes' fields of view are about square
  const eyeHeight = 768;
  const fps = 30.0;

  test(_name, () {
    SmokeArtifacts.resetRecordedAssets();
    final offscreen = ExternalVulkanOffscreen.create(
        width: eyeWidth, height: eyeHeight, layers: 2, multiview: true, srgb: true);
    if (offscreen == null) return markTestSkipped('no Vulkan device');
    final engine = FilamentEngine.createOnExternalVulkan(offscreen.context,
        config: const EngineConfig(stereoscopicType: StereoscopicType.multiview, stereoscopicEyeCount: 2));
    if (engine == null || !engine.isStereoSupported(StereoscopicType.multiview)) {
      engine?.dispose();
      offscreen.dispose();
      return markTestSkipped('no multiview engine');
    }
    final swapChain = FilamentSwapChain.external(engine, offscreen.provider)!;
    final renderer = OpenXrFilamentRenderer.onSwapChain(engine, swapChain, width: eyeWidth, height: eyeHeight);
    renderer.renderer.setClearOptions(r: 0.04, g: 0.05, b: 0.09, a: 1);
    final sun = engine.createEntity();
    LightBuilder(LightType.directional)
      ..color(1.0, 0.97, 0.92)
      ..intensity(100000)
      ..direction(0.4, -1.0, -0.6)
      ..build(engine, sun);
    renderer.scene.addEntity(sun);
    final materials = FilamentMaterialProvider.ubershader(engine);
    final loader = FilamentAssetLoader.create(engine: engine, materialProvider: materials);
    final assets = <FilamentAsset>[];
    // Placed 1.4 m in front of the standing head (LOCAL_FLOOR, metres).
    for (final (file, x) in [('Props/Barrels/fuel_barrel_red.glb', -0.3), ('Props/AC_units/roof_aircon_unit_150x150_a.glb', 0.35)]) {
      final path = '${SmokeArtifacts.testAssetsDir.path}/$file';
      SmokeArtifacts.recordAsset(path);
      final asset = loader.createAsset(File(path).readAsBytesSync())!;
      final resources = FilamentResourceLoader.create(engine: engine)..registerDefaultProviders(engine);
      resources.loadResources(asset);
      resources.dispose();
      asset.addToScene(renderer.scene);
      final box = asset.getBoundingBox();
      final scale = 0.5 / (box.max - box.min).length;
      final center = box.center;
      final m = vm.Matrix4.translationValues(x, 1.3, -1.4)
        ..multiply(vm.Matrix4.diagonal3Values(scale, scale, scale))
        ..multiply(vm.Matrix4.translationValues(-center.x, -center.y, -center.z));
      FilamentTransformManager(engine).setTransform(asset.rootEntity, m.storage);
      assets.add(asset);
    }

    final simulator = SimulatedOpenXrBackend()..headPosition = vm.Vector3(0, 1.6, 0);
    final pacer = OpenXrSimulatedPacer(simulator, period: Duration(microseconds: (1e6 / fps).round()), automatic: false);
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: renderer)..start();
    final frames = SmokeArtifacts.framesForSeconds(fps);
    final pngs = <Uint8List>[];
    final cpuMs = <double>[];
    final gpuMs = <double>[];
    try {
      for (var f = 0; f < frames; f++) {
        final t = f / fps;
        simulator.setHeadLookAngles(0.35 * math.sin(t * 0.9), 0.12 * math.sin(t * 1.7));
        final before = loop.renderedFrames;
        for (var attempt = 0; attempt < 200 && loop.renderedFrames == before; attempt++) {
          pacer.tick();
          if (loop.renderedFrames == before) sleep(const Duration(milliseconds: 4));
        }
        expect(loop.renderedFrames, before + 1, reason: 'frame $f rendered');
        engine.flushAndWait();
        cpuMs.add(loop.history.last.cpu.inMicroseconds / 1000);
        final info = renderer.renderer.getFrameInfoHistory(1);
        if (info.isNotEmpty && info.first.gpuFrameDuration > 0) gpuMs.add(info.first.gpuFrameDuration / 1e6);
        final image = offscreen.events.lastWhere((e) => e.present).index;
        final left = offscreen.readPixels(image, layer: 0)!;
        final right = offscreen.readPixels(image, layer: 1)!;
        pngs.add(SmokeArtifacts.encodePng(eyeWidth * 2, eyeHeight, _sideBySide(left, right, eyeWidth, eyeHeight)));
      }
      expect(renderer.multiview, isTrue);
      SmokeArtifacts.saveVideoFromPngFrames(_name, pngs, fps: fps);
      SmokeArtifacts.saveScreenshot(_name, pngs[pngs.length ~/ 2]);
      double mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
      SmokeArtifacts.annotate(_name, {
        'metrics': {
          'frames': frames,
          'cpu_frame_ms_mean': double.parse(mean(cpuMs).toStringAsFixed(3)),
          'cpu_frame_ms_max': double.parse(cpuMs.reduce(math.max).toStringAsFixed(3)),
          'gpu_frame_ms_mean': double.parse(mean(gpuMs).toStringAsFixed(3)),
          'gpu_frames_measured': gpuMs.length,
          'multiview': renderer.multiview,
          'gpu': engine.gpuName,
        },
      });
      // The turning head moves the picture between frames.
      expect(pngs.first, isNot(equals(pngs.last)));
    } finally {
      loop.stop();
      engine.flushAndWait();
      for (final a in assets) {
        a.removeFromScene(renderer.scene);
        loader.destroyAsset(a);
      }
      loader.dispose();
      materials.dispose();
      renderer.scene.removeEntity(sun);
      engine.destroyEntity(sun);
      renderer.dispose();
      swapChain.dispose();
      engine.dispose();
      offscreen.dispose();
      SmokeArtifacts.resetRecordedAssets();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Uint8List _sideBySide(Uint8List left, Uint8List right, int w, int h) {
  final out = Uint8List(w * 2 * h * 4);
  for (var y = 0; y < h; y++) {
    out.setRange(y * w * 8, y * w * 8 + w * 4, left, y * w * 4);
    out.setRange(y * w * 8 + w * 4, (y + 1) * w * 8, right, y * w * 4);
  }
  return out;
}
