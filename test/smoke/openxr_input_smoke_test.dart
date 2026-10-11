// OpenXR input smoke: the simulated headset's controllers move along scripted
// paths and squeeze / pull their grips and triggers; the input system syncs
// them each frame before the tick, the controller visuals put a cube at each
// grip (its colour follows grip and trigger) and a ray along each aim pose,
// and a grip press plays a haptic pulse. Rendered with the headset renderer
// (multiview) into an external two-layer image on the desktop GPU, next to a
// barrel and an AC unit from test-assets. Both eyes side by side.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_filament/filament.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:lumina_smoke/lumina_smoke.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

const _name = 'OpenXR input smoke controller cubes and aim rays follow scripted grips and triggers';

void main() {
  const eyeWidth = 768;
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
    for (final (file, x) in [('Props/Barrels/fuel_barrel_red.glb', -0.45), ('Props/AC_units/roof_aircon_unit_150x150_a.glb', 0.5)]) {
      final path = '${SmokeArtifacts.testAssetsDir.path}/$file';
      SmokeArtifacts.recordAsset(path);
      final asset = loader.createAsset(File(path).readAsBytesSync())!;
      final resources = FilamentResourceLoader.create(engine: engine)..registerDefaultProviders(engine);
      resources.loadResources(asset);
      resources.dispose();
      asset.addToScene(renderer.scene);
      final box = asset.getBoundingBox();
      final scale = 0.45 / (box.max - box.min).length;
      final center = box.center;
      final m = vm.Matrix4.translationValues(x, 1.0, -1.6)
        ..multiply(vm.Matrix4.diagonal3Values(scale, scale, scale))
        ..multiply(vm.Matrix4.translationValues(-center.x, -center.y, -center.z));
      FilamentTransformManager(engine).setTransform(asset.rootEntity, m.storage);
      assets.add(asset);
    }

    final simulator = SimulatedOpenXrBackend()
      ..initialize()
      ..headPosition = vm.Vector3(0, 1.6, 0)
      ..setHeadLookAngles(0, -0.35)
      // Rays pointing slightly up, so they cross the view instead of hiding behind the cubes.
      ..aimPitch = 0.25;
    final origin = LuminaXROriginActor();
    final input = OpenXrInputSystem.forOrigin(simulator.input, origin);
    expect(input.setup(), XrResult.success);
    final visuals = OpenXrControllerVisuals.create(engine, renderer.scene);
    final controllers = [origin.leftController, origin.rightController];
    var pulses = 0;
    final pacer = OpenXrSimulatedPacer(simulator, period: Duration(microseconds: (1e6 / fps).round()), automatic: false);
    final loop = OpenXrFrameLoop(
      pacer: pacer,
      renderer: renderer,
      input: input,
      onFrame: (dt, frame) {
        visuals.update(controllers);
        for (final c in controllers) {
          if (c.gripAxis.justPressed) {
            c.playHapticPulse(amplitude: 0.6, seconds: 0.05);
            pulses++;
          }
        }
      },
    )..start();
    final frames = SmokeArtifacts.framesForSeconds(fps);
    final pngs = <Uint8List>[];
    final cpuMs = <double>[];
    try {
      for (var f = 0; f < frames; f++) {
        final t = f / fps;
        for (final left in [true, false]) {
          final side = left ? -1.0 : 1.0;
          final phase = left ? 0.0 : math.pi;
          final position = vm.Vector3(side * 0.22 + 0.08 * math.sin(t * 1.3 + phase), 1.15 + 0.1 * math.sin(t * 0.9 + phase),
              -0.45 - 0.1 * math.cos(t * 1.1 + phase));
          final orientation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), side * -0.25 + 0.3 * math.sin(t * 0.7 + phase)) *
              vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), 0.2 * math.sin(t * 1.5));
          simulator
            ..setControllerPose(isLeft: left, position: position, orientation: orientation)
            ..setControllerInputs(
              isLeft: left,
              // Grip squeezes about every 3 s, the trigger pulls in between.
              grip: (0.5 + 0.5 * math.sin(t * 2.1 + phase)).clamp(0.0, 1.0),
              trigger: (0.5 + 0.5 * math.sin(t * 1.4 + phase + 1.0)).clamp(0.0, 1.0),
            );
        }
        final before = loop.renderedFrames;
        for (var attempt = 0; attempt < 200 && loop.renderedFrames == before; attempt++) {
          pacer.tick();
          if (loop.renderedFrames == before) sleep(const Duration(milliseconds: 4));
        }
        expect(loop.renderedFrames, before + 1, reason: 'frame $f rendered');
        engine.flushAndWait();
        cpuMs.add(loop.history.last.cpu.inMicroseconds / 1000);
        final image = offscreen.events.lastWhere((e) => e.present).index;
        final left = offscreen.readPixels(image, layer: 0)!;
        final right = offscreen.readPixels(image, layer: 1)!;
        pngs.add(SmokeArtifacts.encodePng(eyeWidth * 2, eyeHeight, _sideBySide(left, right, eyeWidth, eyeHeight)));
      }
      expect(pulses, greaterThan(2), reason: 'each grip press pulses');
      expect(simulator.hapticPulses.length, pulses);
      expect(origin.leftController.isTracked && origin.rightController.isTracked, isTrue);
      SmokeArtifacts.saveVideoFromPngFrames(_name, pngs, fps: fps);
      SmokeArtifacts.saveScreenshot(_name, pngs[pngs.length ~/ 3]);
      double mean(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
      SmokeArtifacts.annotate(_name, {
        'metrics': {
          'frames': frames,
          'input_frames': input.frames,
          'haptic_pulses': pulses,
          'cpu_frame_ms_mean': double.parse(mean(cpuMs).toStringAsFixed(3)),
          'cpu_frame_ms_max': double.parse(cpuMs.reduce(math.max).toStringAsFixed(3)),
          'interaction_profile': input.interactionProfile(LuminaXRHand.left),
          'gpu': engine.gpuName,
        },
      });
      expect(pngs.first, isNot(equals(pngs.last)));
    } finally {
      loop.stop();
      engine.flushAndWait();
      visuals.dispose();
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
