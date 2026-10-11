import 'dart:collection';

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_composition.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_system.dart';

/// One frame the runtime handed out: its index, the predicted display time
/// (ns) the poses are located for, and whether the runtime wants it rendered.
class OpenXrFrame {
  const OpenXrFrame(this.index, this.predictedDisplayTime, {required this.shouldRender});

  final int index;
  final int predictedDisplayTime;
  final bool shouldRender;
}

/// Where frames come from: the native pacer thread around `xrWaitFrame`
/// ([OpenXrNativePacer]) or the simulated headset's clock
/// ([OpenXrSimulatedPacer]). Calls back on the isolate that started it.
abstract interface class OpenXrFramePacer {
  void start(void Function(OpenXrFrame frame) onFrame);
  void stop();
  bool get running;

  /// The eyes of [frame], located for its predicted display time.
  List<OpenXrEyeView> views(OpenXrFrame frame);

  /// [frame] is done; [rendered] false when nothing was rendered (the pacer
  /// ends it empty, if the renderer has not ended it).
  void ended(OpenXrFrame frame, {required bool rendered});

  /// The layers and blend mode the next frames end with (called when they change).
  void compose(OpenXrFrameComposition composition);
}

/// Renders both eyes of a frame (both in one multiview pass, or one view
/// per eye); false when it could not (the frame is then ended empty).
abstract interface class OpenXrEyeRenderer {
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views);
}

/// Per-frame timing: the CPU time of the frame on this isolate, the frame's
/// interval from the predicted display times, and whether it was late.
class OpenXrFrameTiming {
  const OpenXrFrameTiming({required this.cpu, required this.interval, required this.rendered});
  final Duration cpu;
  final Duration interval;
  final bool rendered;
}

/// The XR frame loop on the UI isolate. The pacer waits for each frame off
/// this isolate; here the views are located and handed to [onViews] (the rig
/// components take this frame's poses), the controllers are synced ([input]:
/// `xrSyncActions`, grip and aim located at the same predicted display
/// time), the world ticks ([onFrame], with the runtime's delta, so gameplay
/// reads current poses) and the renderer draws both eyes. A frame the
/// runtime does not want rendered still syncs, ticks and is ended empty.
class OpenXrFrameLoop {
  OpenXrFrameLoop({required this.pacer, required this.renderer, this.onFrame, this.input, this.historyLength = 600});

  final OpenXrFramePacer pacer;
  final OpenXrEyeRenderer renderer;

  /// The world tick: the delta (s) between predicted display times, and the frame.
  void Function(double deltaSeconds, OpenXrFrame frame)? onFrame;

  /// Called with the views before they are rendered (rig components read them).
  void Function(OpenXrFrame frame, List<OpenXrEyeView> views)? onViews;

  /// The controllers, synced each frame before [onFrame].
  OpenXrInputSystem? input;

  /// Other plugins' composition layers (passthrough, ...), asked every frame.
  final List<OpenXrLayerContributor> layerContributors = [];

  /// The environment blend mode when no contributor asks for another.
  int environmentBlendMode = OpenXrBlendMode.opaque;

  OpenXrFrameComposition _composition = const OpenXrFrameComposition();

  /// What the frames end with now.
  OpenXrFrameComposition get composition => _composition;

  final int historyLength;
  final Queue<OpenXrFrameTiming> _history = Queue();
  final Stopwatch _cpu = Stopwatch();
  int _lastDisplayTime = 0;
  int _frames = 0;
  int _rendered = 0;
  int _late = 0;
  int _shortestInterval = 0;

  /// The last [historyLength] frames.
  List<OpenXrFrameTiming> get history => List.unmodifiable(_history);
  int get frames => _frames;
  int get renderedFrames => _rendered;

  /// Frames whose interval exceeded 1.5 times the shortest one (a display period missed).
  int get lateFrames => _late;

  bool get running => pacer.running;

  void start() => pacer.start(_frame);

  void stop() => pacer.stop();

  void _compose(OpenXrFrame frame) {
    final next = OpenXrFrameComposition.of(layerContributors, frame.predictedDisplayTime, environmentBlendMode: environmentBlendMode);
    if (next == _composition) return;
    _composition = next;
    pacer.compose(next);
    final r = renderer;
    if (r is OpenXrTransparencyAware) (r as OpenXrTransparencyAware).transparentBackground = next.transparentBackground;
  }

  void _frame(OpenXrFrame frame) {
    _cpu
      ..reset()
      ..start();
    final interval = _lastDisplayTime == 0 ? 0 : frame.predictedDisplayTime - _lastDisplayTime;
    if (interval > 0 && (_shortestInterval == 0 || interval < _shortestInterval)) _shortestInterval = interval;
    _lastDisplayTime = frame.predictedDisplayTime;
    final views = frame.shouldRender ? pacer.views(frame) : const <OpenXrEyeView>[];
    if (views.length == 2) onViews?.call(frame, views);
    input?.sync(frame.predictedDisplayTime);
    onFrame?.call(interval / 1e9, frame);
    _compose(frame);
    final rendered = views.length == 2 && renderer.render(frame, views);
    pacer.ended(frame, rendered: rendered);
    _cpu.stop();
    _frames++;
    if (rendered) _rendered++;
    if (_shortestInterval > 0 && interval > _shortestInterval * 1.5) _late++;
    _history.addLast(OpenXrFrameTiming(cpu: _cpu.elapsed, interval: Duration(microseconds: interval ~/ 1000), rendered: rendered));
    while (_history.length > historyLength) {
      _history.removeFirst();
    }
  }
}
