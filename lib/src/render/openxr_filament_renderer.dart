import 'dart:ffi';

import 'package:flutter_filament/filament.dart';
import 'package:logging/logging.dart';

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_composition.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_frame_loop.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_eye_camera.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import 'package:lumina_plugin_openxr/src/render/openxr_filament_bridge.dart';

final _log = Logger('OpenXrFilamentRenderer');

/// VkFormat values the swapchain may use, sRGB first: Filament's stereo pass
/// writes linear colour and the compositor image encodes it.
const _preferredFormats = [43 /* R8G8B8A8_SRGB */, 50 /* B8G8R8A8_SRGB */, 37 /* R8G8B8A8_UNORM */, 44 /* B8G8R8A8_UNORM */];

/// Renders a Filament scene into the compositor's swapchain on the runtime's
/// Vulkan device: the engine adopts the device (`createOnExternalVulkan`),
/// the swapchain is the bridge's provider, and both eyes render in one
/// multiview pass into a 2-layer image. The pacer hands each frame over
/// ([renderFrame]); Filament's driver thread begins and ends the OpenXR frame
/// around its acquire and present.
class OpenXrFilamentRenderer implements OpenXrEyeRenderer, OpenXrTransparencyAware {
  OpenXrFilamentRenderer._(this.backend, this.engine, this.swapChain, this.renderer, this.scene, this.view,
      this.cameraEntity, this.camera, this.width, this.height, this.unitsPerMetre);

  /// The native runtime whose swapchain this renders into; null for a
  /// renderer on another swapchain ([onSwapChain]).
  final OpenXrNativeBackend? backend;
  final FilamentEngine engine;
  final FilamentSwapChain swapChain;
  final FilamentRenderer renderer;
  final FilamentScene scene;
  final FilamentView view;
  final int cameraEntity;
  final FilamentCamera camera;
  final int width;
  final int height;

  /// World units per metre (100 for Lumina's centimetres).
  final double unitsPerMetre;

  double near = 0.05;
  double far = 1000;

  /// The XR origin's world transform (world units): the tracking space sits
  /// there, so moving the origin moves the player.
  vm.Matrix4 origin = vm.Matrix4.identity();
  int _frames = 0;
  int _skipped = 0;

  /// Creates the swapchain (the runtime's recommended eye size), the engine on
  /// the runtime's device and a multiview view; then [OpenXrNativeBackend.setRenderer]
  /// hands frames over. Null when something is missing (logged).
  static OpenXrFilamentRenderer? create(OpenXrNativeBackend backend,
      {required int spaceType, double unitsPerMetre = 1, double resolutionScale = 1}) {
    final device = backend.vulkan;
    final views = backend.viewConfigurations;
    if (device == null || views.isEmpty) {
      _log.warning('no Vulkan device or views: start the session first');
      return null;
    }
    final formats = backend.swapchainFormats;
    final format = _preferredFormats.firstWhere(formats.contains, orElse: () => formats.isEmpty ? 43 : formats.first);
    final width = (views.first.recommendedWidth * resolutionScale).round();
    final height = (views.first.recommendedHeight * resolutionScale).round();
    if (backend.createSwapchain(width: width, height: height, layers: 2, format: format).isFailure) return null;
    final engine = FilamentEngine.createOnExternalVulkan(
      openXrFilamentContext(device),
      config: const EngineConfig(stereoscopicType: StereoscopicType.multiview, stereoscopicEyeCount: 2),
    );
    if (engine == null) {
      _log.warning('Filament could not adopt the runtime\'s Vulkan device');
      backend.destroySwapchain();
      return null;
    }
    final provider = backend.swapchainProvider;
    final swapChain = provider == nullptr ? null : FilamentSwapChain.external(engine, provider.cast());
    if (swapChain == null) {
      engine.dispose();
      backend.destroySwapchain();
      return null;
    }
    final renderer = engine.createRenderer();
    final scene = engine.createScene();
    final view = engine.createView();
    final cameraEntity = engine.createEntity();
    final camera = engine.createCamera(cameraEntity);
    view
      ..scene = scene
      ..camera = camera
      ..setViewport(0, 0, width, height)
      ..stereoscopicOptions = const StereoscopicOptions(enabled: true);
    _log.info('rendering ${width}x$height x2 layers, format $format, stereo ${view.isStereoActive(engine)}, '
        'GPU ${engine.gpuName}');
    final result = OpenXrFilamentRenderer._(
        backend, engine, swapChain, renderer, scene, view, cameraEntity, camera, width, height, unitsPerMetre);
    if (backend.setRenderer(true, spaceType).isFailure) {
      result.dispose();
      return null;
    }
    return result;
  }

  /// A renderer on an engine and a swapchain someone else made (the
  /// simulated headset rendering into `ExternalVulkanOffscreen` on desktop):
  /// the same scene, view and eye cameras as on a headset. [dispose] leaves
  /// the engine and the swapchain to their owner.
  static OpenXrFilamentRenderer onSwapChain(FilamentEngine engine, FilamentSwapChain swapChain,
      {required int width, required int height, double unitsPerMetre = 1}) {
    final renderer = engine.createRenderer();
    final scene = engine.createScene();
    final view = engine.createView();
    final cameraEntity = engine.createEntity();
    final camera = engine.createCamera(cameraEntity);
    view
      ..scene = scene
      ..camera = camera
      ..setViewport(0, 0, width, height)
      ..stereoscopicOptions = const StereoscopicOptions(enabled: true);
    return OpenXrFilamentRenderer._(
        null, engine, swapChain, renderer, scene, view, cameraEntity, camera, width, height, unitsPerMetre);
  }

  /// Whether both eyes render in one multiview pass.
  bool get multiview => view.isStereoActive(engine);

  List<double> _clearColor = const [0, 0, 0, 1];
  bool _transparent = false;

  /// The background colour (linear RGBA) while nothing shows through.
  void setClearColor(double r, double g, double b, [double a = 1]) {
    _clearColor = [r, g, b, a];
    _applyClear();
  }

  /// Clear to alpha 0 with a translucent view, so a layer under the
  /// projection layer (a passthrough underlay) shows where nothing is drawn.
  @override
  set transparentBackground(bool value) {
    if (_transparent == value) return;
    _transparent = value;
    view.blendMode = value ? BlendMode.translucent : BlendMode.opaque;
    _applyClear();
  }

  bool get transparentBackground => _transparent;

  void _applyClear() {
    final c = _transparent ? const [0.0, 0.0, 0.0, 0.0] : _clearColor;
    renderer.setClearOptions(r: c[0], g: c[1], b: c[2], a: c[3]);
  }

  /// Frames rendered and skipped so far.
  int get frames => _frames;
  int get skipped => _skipped;

  /// The eye cameras of [frame] (the pacer's located views), or empty.
  List<OpenXrEyeView> viewsOf(int frame) => backend?.frameViews(frame) ?? const [];

  /// Renders [frame] with [views] (the pacer's views of that frame): the
  /// camera's head is the XR [origin], each eye its located pose. Returns
  /// false (the frame is then ended empty) when Filament cannot begin it or
  /// the views are not tracked.
  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) {
    if (views.length != 2) {
      _skipped++;
      return false;
    }
    final eyes = OpenXrEyeCamera.fromViews(views, unitsPerMetre: unitsPerMetre, near: near, far: far);
    // The camera is the head (so culling looks where the eyes look); the eyes
    // are relative to it.
    final head = OpenXrEyeCamera.head(views, unitsPerMetre: unitsPerMetre);
    camera.modelMatrix = origin.multiplied(head);
    for (var i = 0; i < 2; i++) {
      camera.setEyeModelMatrix(i, OpenXrEyeCamera.relativeTo(head, eyes[i].model));
    }
    camera.setCustomEyeProjection([eyes[0].projection, eyes[1].projection],
        OpenXrEyeCamera.cullingProjection(views, near: near, far: far),
        near: near, far: far);
    if (!renderer.beginFrame(swapChain)) {
      _skipped++;
      return false;
    }
    renderer.render(view);
    renderer.endFrame();
    _frames++;
    return true;
  }

  /// Stops handing frames over, then destroys the Filament objects and the
  /// swapchain (before the session goes).
  void dispose() {
    final backend = this.backend;
    backend?.setRenderer(false, OpenXrReferenceSpaceType.local);
    engine.flushAndWait();
    view.dispose();
    scene.dispose();
    camera.dispose();
    engine.destroyEntity(cameraEntity);
    renderer.dispose();
    if (backend == null) return;
    swapChain.dispose();
    engine.dispose();
    backend.destroySwapchain();
  }
}
