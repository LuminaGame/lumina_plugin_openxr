import 'package:flutter_filament/filament.dart';
import 'package:lumina_core/lumina_core.dart' show LuminaQuaternionRotation;
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/components/lumina_xr_controller_component.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_cube_glb.dart';

class _HandVisual {
  _HandVisual(this.cube, this.ray);
  final FilamentAsset cube;
  final FilamentAsset ray;
}

/// Debug visuals for the two controllers in a Filament scene: a cube at each
/// grip pose and a ray along each aim pose. The cube's colour follows the
/// grip (towards green) and the trigger (towards white); the ray turns
/// yellow while the trigger is pressed. An untracked controller's visuals
/// are hidden. Built from generated glTF cubes with the ubershader materials
/// (multiview capable).
class OpenXrControllerVisuals {
  OpenXrControllerVisuals._(this.engine, this.scene, this._loader, this._materials, this._hands, this.unitsPerMetre);

  /// Creates the visuals in [scene]. [unitsPerMetre] is the scene's unit
  /// (the renderer's; 1 for metres).
  factory OpenXrControllerVisuals.create(FilamentEngine engine, FilamentScene scene,
      {double unitsPerMetre = 1, double cubeSize = 0.06, double rayLength = 1.0}) {
    final materials = FilamentMaterialProvider.ubershader(engine);
    final loader = FilamentAssetLoader.create(engine: engine, materialProvider: materials);
    final resources = FilamentResourceLoader.create(engine: engine);
    FilamentAsset load(double size) {
      final asset = loader.createAsset(openXrCubeGlb(size: size, color: const [0.8, 0.8, 0.8, 1]))!;
      resources.loadResources(asset);
      asset.addToScene(scene);
      return asset;
    }

    final hands = {
      for (final hand in LuminaXRHand.values) hand: _HandVisual(load(cubeSize * unitsPerMetre), load(unitsPerMetre)),
    };
    resources.dispose();
    return OpenXrControllerVisuals._(engine, scene, loader, materials, hands, unitsPerMetre)
      .._rayLength = rayLength
      .._rayThickness = 0.008;
  }

  final FilamentEngine engine;
  final FilamentScene scene;
  final FilamentAssetLoader _loader;
  final FilamentMaterialProvider _materials;
  final Map<LuminaXRHand, _HandVisual> _hands;
  final double unitsPerMetre;
  double _rayLength = 1;
  double _rayThickness = 0.006;

  /// The base colours of the left and right cubes (linear RGB).
  static const baseColors = {LuminaXRHand.left: [0.1, 0.35, 0.9], LuminaXRHand.right: [0.9, 0.35, 0.1]};

  /// The cube colour for [grip] and [trigger] (0..1) on [hand].
  static List<double> cubeColor(LuminaXRHand hand, double grip, double trigger) {
    final base = baseColors[hand]!;
    const green = [0.1, 0.9, 0.2];
    return [
      for (var i = 0; i < 3; i++) () {
        final g = base[i] + (green[i] - base[i]) * grip.clamp(0.0, 1.0);
        return g + (1 - g) * 0.8 * trigger.clamp(0.0, 1.0);
      }(),
    ];
  }

  /// Puts the visuals on [controllers]' world poses (Lumina centimetres,
  /// scaled to [unitsPerMetre]).
  void update(Iterable<LuminaXRControllerComponent> controllers) {
    final transforms = FilamentTransformManager(engine);
    final renderables = FilamentRenderableManager(engine);
    final cm = unitsPerMetre / 100;
    final hidden = vm.Matrix4.diagonal3Values(0, 0, 0);
    for (final c in controllers) {
      final v = _hands[c.hand]!;
      if (!c.isTracked) {
        transforms.setTransform(v.cube.rootEntity, hidden.storage);
        transforms.setTransform(v.ray.rootEntity, hidden.storage);
        continue;
      }
      final grip = vm.Matrix4.compose(c.worldLocation * cm, c.worldRotation, vm.Vector3.all(1));
      transforms.setTransform(v.cube.rootEntity, grip.storage);
      // The ray: a thin box from the aim origin along its −Z.
      final rotation = c.aimWorldRotation;
      final start = c.aimWorldLocation * cm;
      final centre = start + rotation.rotateVector(vm.Vector3(0, 0, -_rayLength * unitsPerMetre / 2));
      final ray = vm.Matrix4.compose(centre, rotation, vm.Vector3(_rayThickness, _rayThickness, _rayLength));
      transforms.setTransform(v.ray.rootEntity, ray.storage);
      final color = cubeColor(c.hand, c.gripAxis.value, c.triggerAxis.value);
      _setColor(renderables, v.cube, [...color, 1]);
      _setColor(renderables, v.ray, c.triggerAxis.isPressed ? const [1.0, 0.85, 0.1, 1] : const [0.9, 0.9, 0.9, 1]);
    }
  }

  static void _setColor(FilamentRenderableManager renderables, FilamentAsset asset, List<double> rgba) {
    for (final e in asset.renderableEntities) {
      renderables.getMaterialInstanceAt(e, 0)?.setFloat4('baseColorFactor', rgba[0], rgba[1], rgba[2], rgba[3]);
    }
  }

  void dispose() {
    for (final v in _hands.values) {
      for (final a in [v.cube, v.ray]) {
        a.removeFromScene(scene);
        _loader.destroyAsset(a);
      }
    }
    _hands.clear();
    _loader.dispose();
    _materials.dispose();
  }
}
