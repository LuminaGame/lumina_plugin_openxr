import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_filament/filament.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

/// Immersive bring-up on a headset: the OpenXR session on the native runtime,
/// Filament on the runtime's Vulkan device rendering both eyes (multiview)
/// into the compositor's swapchain at the headset's rate, turning cubes in
/// front of the user (LOCAL_FLOOR), and the controllers: a cube at each grip
/// whose colour follows grip and trigger, a ray from each aim pose, a haptic
/// pulse when a grip is pressed. Everything is logged
/// (`[openxr_example]` lines; the bridge logs under the logcat tag LuminaOpenXR).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OpenXrErrorReporter.handler = (error, stack, where) => debugPrint('[openxr_example] $where failed: $error');
  runApp(const OpenXrExampleApp());
}

class OpenXrExampleApp extends StatefulWidget {
  const OpenXrExampleApp({super.key});

  @override
  State<OpenXrExampleApp> createState() => _OpenXrExampleAppState();
}

class _Cube {
  _Cube(this.asset, this.position, this.spin);
  final FilamentAsset asset;
  final vm.Vector3 position;
  final double spin;
}

/// Ends every frame empty (no renderer could be made).
class _EmptyRenderer implements OpenXrEyeRenderer {
  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) => false;
}

class _OpenXrExampleAppState extends State<OpenXrExampleApp> {
  final _native = OpenXrBindings.instance.native;
  late final OpenXrSession _session = OpenXrSession(backend: _native)..vulkanDeviceInfo = openXrFilamentDeviceInfo();
  OpenXrFrameLoop? _loop;
  OpenXrFilamentRenderer? _renderer;
  FilamentMaterialProvider? _materials;
  FilamentAssetLoader? _loader;
  final _cubes = <_Cube>[];
  final _origin = LuminaXROriginActor();
  late final OpenXrInputSystem _input = OpenXrInputSystem.forOrigin(_native.input, _origin);
  OpenXrControllerVisuals? _visuals;
  int _pulses = 0;
  final _lights = <int>[];
  Timer? _poll;
  final _lines = <String>[];
  final _clock = Stopwatch()..start();
  int _lastReportMs = 0;
  int _reportedFrames = 0;
  int _reportedRendered = 0;

  void _log(String line) {
    debugPrint('[openxr_example] $line');
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    _session
      ..onSessionBegan = _startRendering
      ..onSessionEnding = _stopRendering
      ..onExitRequested = (() => _log('the runtime asked the app to quit'))
      ..onInteractionProfileChanged = () {
        _input.refreshInteractionProfiles();
        _log('interaction profiles: left ${_input.interactionProfile(LuminaXRHand.left)}, '
            'right ${_input.interactionProfile(LuminaXRHand.right)}');
      };
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final r = _session.beginSession();
    if (r.isFailure) {
      _log('beginSession failed: ${r.name} (${_native.lastError})');
      return;
    }
    _log('runtime ${_native.runtimeName}, system "${_native.systemName}", '
        'views ${_native.viewConfigurations.join(', ')}, blend ${_native.blendModes.map(OpenXrBlendMode.name).join(', ')}');
    _log('Vulkan: ${_native.vulkan}');
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final event in _session.pollEvents()) {
        _log('event: $event -> session ${_session.state.name}');
      }
    });
  }

  /// The display refresh rate to run at (`--dart-define=XR_REFRESH_RATE=90`), 72 by default.
  static const _refreshRate = int.fromEnvironment('XR_REFRESH_RATE', defaultValue: 72);

  void _startRendering() {
    _log('refresh rates ${_native.displayRefreshRates}, current ${_native.displayRefreshRate} Hz; '
        'requesting $_refreshRate Hz: ${_native.requestDisplayRefreshRate(_refreshRate.toDouble()).name}');
    final renderer = OpenXrFilamentRenderer.create(_native, spaceType: _session.referenceSpaceType);
    if (renderer == null) {
      _log('no renderer (${_native.lastError}); empty frames only');
    } else {
      _renderer = renderer;
      _buildScene(renderer);
      _log('renderer ${renderer.width}x${renderer.height}, multiview ${renderer.multiview}, GPU ${renderer.engine.gpuName}');
    }
    _input.baseSpaceType = _session.referenceSpaceType;
    final inputResult = _input.setup();
    _log('input ${inputResult.name}: profiles suggested ${_native.input.suggestedProfiles.join(', ')}');
    final loop = OpenXrFrameLoop(
      pacer: OpenXrNativePacer(_native, blendMode: OpenXrBlendMode.opaque),
      renderer: renderer ?? _EmptyRenderer(),
      onFrame: _tick,
      input: inputResult.isSuccess ? _input : null,
    );
    _loop = loop;
    loop.start();
    _log('frame loop started: ${loop.running}');
  }

  void _buildScene(OpenXrFilamentRenderer r) {
    final engine = r.engine;
    r.renderer.setClearOptions(r: 0.02, g: 0.03, b: 0.06, a: 1);
    for (final (dir, intensity) in [
      (vm.Vector3(0.4, -1.0, -0.5), 90000.0),
      (vm.Vector3(-0.6, -0.3, 0.7), 30000.0),
    ]) {
      final e = engine.createEntity();
      LightBuilder(LightType.directional)
        ..color(1.0, 0.97, 0.92)
        ..intensity(intensity)
        ..direction(dir.x, dir.y, dir.z)
        ..build(engine, e);
      r.scene.addEntity(e);
      _lights.add(e);
    }
    final materials = FilamentMaterialProvider.ubershader(engine);
    _materials = materials;
    final loader = FilamentAssetLoader.create(engine: engine, materialProvider: materials);
    _loader = loader;
    // One big cube straight ahead at eye height, smaller ones around it.
    final placements = [
      (vm.Vector3(0, 1.3, -1.2), 0.3, [0.9, 0.35, 0.1, 1.0], 0.8),
      (vm.Vector3(-0.6, 1.0, -1.5), 0.15, [0.1, 0.5, 0.9, 1.0], -1.3),
      (vm.Vector3(0.6, 1.0, -1.5), 0.15, [0.2, 0.8, 0.3, 1.0], 1.7),
      (vm.Vector3(0, 0.6, -1.0), 0.12, [0.9, 0.9, 0.9, 1.0], 0.5),
    ];
    for (final (position, size, color, spin) in placements) {
      final asset = loader.createAsset(openXrCubeGlb(size: size, color: color));
      if (asset == null) continue;
      final resources = FilamentResourceLoader.create(engine: engine);
      resources.loadResources(asset);
      resources.dispose();
      asset.addToScene(r.scene);
      _cubes.add(_Cube(asset, position, spin));
    }
    _visuals = OpenXrControllerVisuals.create(engine, r.scene);
  }

  /// The world tick of this example: the cubes turn; every 5 s the frame stats are logged.
  void _tick(double dt, OpenXrFrame frame) {
    final renderer = _renderer;
    if (renderer != null) {
      final t = _clock.elapsedMilliseconds / 1000.0;
      final transforms = FilamentTransformManager(renderer.engine);
      for (final c in _cubes) {
        final m = vm.Matrix4.compose(c.position,
            vm.Quaternion.axisAngle(vm.Vector3(0.3, 1, 0.2).normalized(), t * c.spin), vm.Vector3.all(1));
        transforms.setTransform(c.asset.rootEntity, m.storage);
      }
    }
    final controllers = [_origin.leftController, _origin.rightController];
    _visuals?.update(controllers);
    for (final c in controllers) {
      if (c.gripAxis.justPressed) {
        c.playHapticPulse(amplitude: 0.6, seconds: 0.05);
        _log('pulse ${++_pulses} on ${c.hand.name} (grip ${c.gripAxis.value.toStringAsFixed(2)})');
      }
    }
    final now = _clock.elapsedMilliseconds;
    final loop = _loop;
    if (loop == null || now - _lastReportMs < 5000) return;
    final seconds = (now - _lastReportMs) / 1000.0;
    final history = loop.history;
    final window = history.length > 360 ? history.sublist(history.length - 360) : history;
    final cpuMs = window.isEmpty ? 0.0 : window.fold<double>(0, (a, f) => a + f.cpu.inMicroseconds / 1000) / window.length;
    final stats = _native.frameStats;
    final gpu = renderer?.renderer.getFrameInfoHistory(8) ?? const <FrameInfo>[];
    final measured = gpu.where((f) => f.gpuFrameDuration > 0).toList();
    final gpuMs = measured.isEmpty
        ? 0.0
        : measured.fold<double>(0, (a, f) => a + f.gpuFrameDuration / 1e6) / math.max(1, measured.length);
    _log('frames ${((loop.frames - _reportedFrames) / seconds).toStringAsFixed(1)}/s, '
        'rendered ${((loop.renderedFrames - _reportedRendered) / seconds).toStringAsFixed(1)}/s, '
        'Dart CPU ${cpuMs.toStringAsFixed(2)} ms, GPU ${gpuMs.toStringAsFixed(2)} ms, '
        'period ${(stats.period.inMicroseconds / 1000).toStringAsFixed(2)} ms, total ${stats.frames}, '
        'late ${loop.lateFrames}, missed ${stats.missed}, layers ${_native.renderedFrames}, skipped ${renderer?.skipped ?? 0}');
    for (final c in controllers) {
      _log('${c.hand.name}: tracked ${c.isTracked}, grip ${c.gripAxis.value.toStringAsFixed(2)}, '
          'trigger ${c.triggerAxis.value.toStringAsFixed(2)}, stick (${c.thumbstick.x.toStringAsFixed(2)}, '
          '${c.thumbstick.y.toStringAsFixed(2)}), at ${c.location.storage.map((v) => v.toStringAsFixed(1)).join(', ')} cm, '
          'profile ${_input.interactionProfile(c.hand)}');
    }
    _reportedFrames = loop.frames;
    _reportedRendered = loop.renderedFrames;
    _lastReportMs = now;
  }

  void _stopRendering() {
    _loop?.stop();
    _loop = null;
    final r = _renderer;
    if (r != null) {
      _visuals?.dispose();
      _visuals = null;
      for (final c in _cubes) {
        c.asset.removeFromScene(r.scene);
        _loader?.destroyAsset(c.asset);
      }
      _cubes.clear();
      for (final e in _lights) {
        r.scene.removeEntity(e);
        r.engine.destroyEntity(e);
      }
      _lights.clear();
      _loader?.dispose();
      _materials?.dispose();
      r.dispose();
    }
    _renderer = null;
    _log('rendering stopped');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _session.endSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(children: [for (final l in _lines) Text(l, style: const TextStyle(fontSize: 12))]),
        ),
      );
}
