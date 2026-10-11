import 'dart:async';
import 'dart:ffi';

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bridge_ffi.dart' show OpenXrFrameCallbackNative;
import 'package:lumina_plugin_openxr/src/ffi/simulated_openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_composition.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_frame_loop.dart';

/// Frames from the bridge's pacer thread: it blocks in `xrWaitFrame`, locates
/// the views for the predicted display time and posts the frame to this
/// isolate through a `NativeCallable.listener`; the isolate never blocks.
/// Frames the runtime does not want rendered are ended empty by the pacer
/// itself; a rendered frame is ended by the renderer's swapchain present.
class OpenXrNativePacer implements OpenXrFramePacer {
  OpenXrNativePacer(this.backend, {this.blendMode = OpenXrBlendMode.opaque});

  final OpenXrNativeBackend backend;
  final int blendMode;
  NativeCallable<OpenXrFrameCallbackNative>? _callable;

  @override
  bool get running => _callable != null;

  @override
  void start(void Function(OpenXrFrame frame) onFrame) {
    if (_callable != null) return;
    final callable = NativeCallable<OpenXrFrameCallbackNative>.listener(
        (int time, int shouldRender, int index) => onFrame(OpenXrFrame(index, time, shouldRender: shouldRender != 0)));
    _callable = callable;
    if (backend.startFrameLoop(callable, blendMode: blendMode).isFailure) {
      callable.close();
      _callable = null;
    }
  }

  @override
  void stop() {
    backend.stopFrameLoop();
    _callable?.close();
    _callable = null;
  }

  @override
  List<OpenXrEyeView> views(OpenXrFrame frame) => backend.frameViews(frame.index);

  @override
  void compose(OpenXrFrameComposition composition) => backend.setFrameComposition(composition);

  @override
  void ended(OpenXrFrame frame, {required bool rendered}) {
    if (!rendered && frame.shouldRender) backend.skipFrame(frame.index);
  }
}

/// Frames from the simulated headset's clock: one every [period] (or each
/// [tick] call, for tests), with the simulator's eyes. [log] records the
/// call order (`begin`, `end`) a runtime would see.
class OpenXrSimulatedPacer implements OpenXrFramePacer {
  OpenXrSimulatedPacer(this.simulator, {this.period = const Duration(microseconds: 13889), this.automatic = true});

  final SimulatedOpenXrBackend simulator;
  final Duration period;

  /// Whether a timer drives the frames; false: [tick] does.
  final bool automatic;

  final List<String> log = [];
  void Function(OpenXrFrame frame)? _onFrame;
  Timer? _timer;
  int _index = 0;
  int _time = 0;

  /// Whether the next frames want rendering (scripted by tests).
  final List<bool> shouldRender = [];

  @override
  bool get running => _onFrame != null;

  @override
  void start(void Function(OpenXrFrame frame) onFrame) {
    _onFrame = onFrame;
    if (automatic) _timer = Timer.periodic(period, (_) => tick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _onFrame = null;
  }

  /// Hands out the next frame (when running).
  void tick() {
    final onFrame = _onFrame;
    if (onFrame == null) return;
    _index++;
    _time += period.inMicroseconds * 1000;
    final render = shouldRender.isEmpty ? true : shouldRender.removeAt(0);
    log.add('begin $_index');
    onFrame(OpenXrFrame(_index, _time, shouldRender: render));
  }

  /// The simulated runtime records what the frames end with.
  @override
  void compose(OpenXrFrameComposition composition) => simulator.compositions.add(composition);

  @override
  List<OpenXrEyeView> views(OpenXrFrame frame) {
    log.add('locateViews ${frame.index}');
    return simulator.locateViews(OpenXrReferenceSpaceType.localFloor, frame.predictedDisplayTime);
  }

  @override
  void ended(OpenXrFrame frame, {required bool rendered}) => log.add('end ${frame.index}${rendered ? '' : ' (empty)'}');
}
