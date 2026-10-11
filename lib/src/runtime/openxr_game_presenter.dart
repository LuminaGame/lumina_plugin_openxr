import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_origin_actor.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_frame_loop.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_pacers.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_system.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_controller_visuals.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_filament_bridge.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_filament_renderer.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_session.dart';

final _log = Logger('OpenXrGamePresenter');

/// What an immersive game session is made of, handed to every
/// [OpenXrGameExtension] (MetaXR's passthrough binds the world's
/// passthrough components and adds its layer to [loop]).
class OpenXrGameSession {
  OpenXrGameSession({
    required this.backend,
    required this.session,
    required this.renderer,
    required this.loop,
    required this.game,
    required this.origin,
    required this.input,
  });

  final OpenXrNativeBackend backend;
  final OpenXrSession session;
  final OpenXrFilamentRenderer renderer;
  final OpenXrFrameLoop loop;
  final LuminaGame game;
  final LuminaXROriginActor origin;
  final OpenXrInputSystem input;

  LuminaWorld? get world => game.world;
}

/// A runtime module's part of every immersive game session.
abstract class OpenXrGameExtension {
  /// The session's frame loop is about to start.
  void attach(OpenXrGameSession session);

  /// After every world tick (new actors may have spawned).
  void onFrame(OpenXrGameSession session) {}

  /// The session is ending.
  void detach(OpenXrGameSession session);
}

/// The frame numbers an immersive session reports every [OpenXrGamePresenter.reportInterval].
class OpenXrGameFrameReport {
  const OpenXrGameFrameReport({
    required this.framesPerSecond,
    required this.renderedPerSecond,
    required this.cpuMs,
    required this.gpuMs,
    required this.periodMs,
    required this.totalFrames,
    required this.lateFrames,
    required this.missedFrames,
  });

  final double framesPerSecond;
  final double renderedPerSecond;

  /// The Dart frame (input, world tick) on the UI isolate, mean ms.
  final double cpuMs;

  /// Filament's GPU frame time, mean ms (0 when the driver gives none).
  final double gpuMs;
  final double periodMs;
  final int totalFrames;
  final int lateFrames;
  final int missedFrames;

  /// Late frames as a share of the frames the loop ran.
  double get lateShare => totalFrames == 0 ? 0 : lateFrames / totalFrames;

  @override
  String toString() => 'frames ${framesPerSecond.toStringAsFixed(1)}/s, rendered ${renderedPerSecond.toStringAsFixed(1)}/s, '
      'Dart CPU ${cpuMs.toStringAsFixed(2)} ms, GPU ${gpuMs.toStringAsFixed(2)} ms, period ${periodMs.toStringAsFixed(2)} ms, '
      'total $totalFrames, late $lateFrames (${(lateShare * 100).toStringAsFixed(2)} %), missed $missedFrames';
}

/// Presents a Lumina game in the headset: an OpenXR session on the native
/// runtime, Filament on the runtime's Vulkan device rendering both eyes
/// into the compositor's swapchain, the game's world mounted on that engine
/// and ticked by the XR frame loop (not by Flutter's vsync), the XR origin
/// and its controllers driven by the runtime. Flutter shows only a status
/// line meanwhile.
///
/// The XR origin is the world's [LuminaXROriginActor] when it has one, else
/// one is spawned and follows the possessed pawn (the player's place in the
/// level). The controllers become grabbers of every [LuminaPoseGrabInteractor]
/// in the world, and the XR keys reach the world's input.
class OpenXrGamePresenter extends StatefulWidget {
  const OpenXrGamePresenter({super.key, required this.game, required this.levelName, this.refreshRate = 72, this.multiview = true});

  final LuminaGame game;
  final String levelName;

  /// The display refresh rate asked of the headset (Hz).
  final int refreshRate;
  final bool multiview;

  /// The runtime modules' parts of every session (MetaXR adds passthrough).
  static final List<OpenXrGameExtension> extensions = [];

  /// How often the frame numbers are logged (logcat tag `flutter`,
  /// `[lumina_xr]` lines) and reported to [onReport].
  static Duration reportInterval = const Duration(seconds: 5);

  /// Receives every frame report (tests, an on-screen readout).
  static void Function(OpenXrGameFrameReport report)? onReport;

  @override
  State<OpenXrGamePresenter> createState() => _OpenXrGamePresenterState();
}

class _OpenXrGamePresenterState extends State<OpenXrGamePresenter> {
  final _native = OpenXrBindings.instance.native;
  late final OpenXrSession _session = OpenXrSession(backend: _native)..vulkanDeviceInfo = openXrFilamentDeviceInfo();
  OpenXrFilamentRenderer? _renderer;
  OpenXrFrameLoop? _loop;
  OpenXrGameSession? _gameSession;
  OpenXrControllerVisuals? _visuals;
  LuminaXROriginActor? _origin;
  bool _spawnedOrigin = false;
  final Set<LuminaPoseGrabInteractor> _grabInteractors = {};
  Timer? _poll;
  String _status = 'Starting the OpenXR session…';
  final _clock = Stopwatch()..start();
  int _lastReportMs = 0;
  int _reportedFrames = 0;
  int _reportedRendered = 0;
  bool _mounted = false;

  void _say(String message) {
    debugPrint('[lumina_xr] $message');
    if (mounted) setState(() => _status = message);
  }

  @override
  void initState() {
    super.initState();
    _session
      ..onSessionBegan = _begin
      ..onSessionEnding = _end
      ..onExitRequested = (() => _say('the runtime asked the game to quit'))
      ..onInteractionProfileChanged = () => _gameSession?.input.refreshInteractionProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final r = _session.beginSession();
    if (r.isFailure) {
      _say('OpenXR session failed: ${r.name} (${_native.lastError})');
      return;
    }
    _say('OpenXR runtime ${_native.runtimeName}, "${_native.systemName}"');
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) => _session.pollEvents());
  }

  void _begin() {
    final rate = _native.requestDisplayRefreshRate(widget.refreshRate.toDouble());
    _say('refresh rates ${_native.displayRefreshRates}; asked ${widget.refreshRate} Hz: ${rate.name}');
    final renderer = OpenXrFilamentRenderer.create(_native, spaceType: _session.referenceSpaceType, unitsPerMetre: LuminaUnits.unitsPerMetre);
    if (renderer == null) {
      _say('no renderer: ${_native.lastError}');
      return;
    }
    _renderer = renderer;
    renderer
      ..near = 5
      ..far = 100000;
    if (!widget.game.mountGame(renderer.engine, renderer.scene)) {
      _say('the game could not be mounted');
      return;
    }
    _mounted = true;
    final world = widget.game.world!;
    final origin = world.actors.whereType<LuminaXROriginActor>().firstOrNull ?? _spawnOrigin(world);
    _origin = origin;
    final input = OpenXrInputSystem.forOrigin(_native.input, origin, baseSpaceType: _session.referenceSpaceType)..attachTo(world);
    // The presenter is the game's host: play begins once the origin and the
    // XR input are in the world (no view: the eyes are the XR cameras).
    world.beginPlay();
    final inputResult = input.setup();
    _visuals = OpenXrControllerVisuals.create(renderer.engine, renderer.scene, unitsPerMetre: LuminaUnits.unitsPerMetre);
    final loop = OpenXrFrameLoop(
      pacer: OpenXrNativePacer(_native, blendMode: OpenXrBlendMode.opaque),
      renderer: renderer,
      input: inputResult.isSuccess ? input : null,
    )
      ..onViews = _onViews
      ..onFrame = _onFrame;
    _loop = loop;
    final gameSession = OpenXrGameSession(
        backend: _native, session: _session, renderer: renderer, loop: loop, game: widget.game, origin: origin, input: input);
    _gameSession = gameSession;
    for (final e in OpenXrGamePresenter.extensions) {
      try {
        e.attach(gameSession);
      } catch (error, stack) {
        _log.warning('extension ${e.runtimeType} failed to attach: $error', error, stack);
      }
    }
    loop.start();
    _say('${widget.levelName}: ${renderer.width}x${renderer.height} per eye, multiview ${renderer.multiview}, '
        'GPU ${renderer.engine.gpuName}, input ${inputResult.name}');
  }

  /// An origin for a level that places none: at the player's start, then
  /// following the possessed pawn.
  LuminaXROriginActor _spawnOrigin(LuminaWorld world) {
    final start = world.actors.whereType<LuminaPlayerStart>().firstOrNull;
    final origin = LuminaXROriginActor(
      key: const LuminaObjectKey('xr_origin'),
      location: start?.actorLocation.clone(),
    );
    _spawnedOrigin = true;
    return world.spawnActorImmediately(origin);
  }

  void _onViews(OpenXrFrame frame, List<OpenXrEyeView> views) {
    final origin = _origin;
    if (origin == null || views.length < 2) return;
    final head = (views[0].position + views[1].position) * 0.5;
    origin.hmdComponent.updatePoseFromOpenXr(head, views[0].orientation);
    origin.hmdComponent.interPupillaryDistance = views[0].position.distanceTo(views[1].position);
  }

  void _onFrame(double dt, OpenXrFrame frame) {
    final origin = _origin;
    final renderer = _renderer;
    final world = widget.game.world;
    if (origin == null || renderer == null || world == null) return;
    widget.game.tickGame(dt <= 0 ? 0 : math.min(dt, 0.1));
    // A spawned origin stands where the player's pawn is (yaw only).
    if (_spawnedOrigin) {
      final pawn = LuminaGameplayStatics.getPlayerPawn(world, playerIndex: 0);
      if (pawn != null) {
        origin.actorLocation = pawn.actorLocation.clone();
      }
    }
    // The controllers grab with every grab interaction in the world.
    for (final actor in world.actors) {
      for (final interactor in actor.components.whereType<LuminaPoseGrabInteractor>()) {
        if (_grabInteractors.add(interactor)) {
          interactor
            ..registerGrabber(origin.leftController)
            ..registerGrabber(origin.rightController);
          _say('controllers grab with ${actor.runtimeType}');
        }
      }
    }
    final gameSession = _gameSession;
    if (gameSession != null) {
      for (final e in OpenXrGamePresenter.extensions) {
        e.onFrame(gameSession);
      }
    }
    renderer.origin = vm.Matrix4.compose(origin.actorLocation, origin.actorRotation, vm.Vector3.all(1));
    _visuals?.update([origin.leftController, origin.rightController]);
    _report(renderer);
  }

  void _report(OpenXrFilamentRenderer renderer) {
    final loop = _loop;
    final now = _clock.elapsedMilliseconds;
    if (loop == null || now - _lastReportMs < OpenXrGamePresenter.reportInterval.inMilliseconds) return;
    final seconds = (now - _lastReportMs) / 1000.0;
    final history = loop.history;
    final window = history.length > 360 ? history.sublist(history.length - 360) : history;
    final cpuMs = window.isEmpty ? 0.0 : window.fold<double>(0, (a, f) => a + f.cpu.inMicroseconds / 1000) / window.length;
    final stats = _native.frameStats;
    final gpu = renderer.renderer.getFrameInfoHistory(8);
    final measured = gpu.where((f) => f.gpuFrameDuration > 0).toList();
    final gpuMs = measured.isEmpty ? 0.0 : measured.fold<double>(0, (a, f) => a + f.gpuFrameDuration / 1e6) / measured.length;
    final report = OpenXrGameFrameReport(
      framesPerSecond: (loop.frames - _reportedFrames) / seconds,
      renderedPerSecond: (loop.renderedFrames - _reportedRendered) / seconds,
      cpuMs: cpuMs,
      gpuMs: gpuMs,
      periodMs: stats.period.inMicroseconds / 1000,
      totalFrames: loop.frames,
      lateFrames: loop.lateFrames,
      missedFrames: stats.missed,
    );
    debugPrint('[lumina_xr] $report');
    OpenXrGamePresenter.onReport?.call(report);
    _reportedFrames = loop.frames;
    _reportedRendered = loop.renderedFrames;
    _lastReportMs = now;
  }

  void _end() {
    _loop?.stop();
    final s = _gameSession;
    if (s != null) {
      for (final e in OpenXrGamePresenter.extensions) {
        try {
          e.detach(s);
        } catch (error, stack) {
          _log.warning('extension ${e.runtimeType} failed to detach: $error', error, stack);
        }
      }
    }
    _gameSession = null;
    _loop = null;
    _grabInteractors.clear();
    if (_mounted) {
      widget.game.disposeGame();
      _mounted = false;
    }
    _visuals?.dispose();
    _visuals = null;
    _renderer?.dispose();
    _renderer = null;
    _origin = null;
    _say('session ended');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _session.endSession();
    if (_renderer != null) _end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF000000),
        child: Center(
          child: Text(_status, textDirection: TextDirection.ltr, style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
        ),
      );
}
