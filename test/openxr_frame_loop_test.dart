import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

/// Records what the loop asks the renderer to do.
class _RecordingRenderer implements OpenXrEyeRenderer {
  _RecordingRenderer(this.log);
  final List<String> log;

  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) {
    log.add('render ${frame.index} (${views.length} eyes)');
    return true;
  }
}

void main() {
  test('each frame: begin, views, tick, render both eyes, end; a frame not to render still ticks and ends empty', () {
    final pacer = OpenXrSimulatedPacer(SimulatedOpenXrBackend(), automatic: false)
      ..shouldRender.addAll([true, true, false, true]);
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: _RecordingRenderer(pacer.log));
    final deltas = <double>[];
    loop
      ..onViews = ((frame, views) => pacer.log.add('views ${frame.index}'))
      ..onFrame = ((dt, frame) {
        deltas.add(dt);
        pacer.log.add('tick ${frame.index}');
      });
    loop.start();
    for (var i = 0; i < 4; i++) {
      pacer.tick();
    }
    expect(pacer.log, [
      'begin 1', 'locateViews 1', 'views 1', 'tick 1', 'render 1 (2 eyes)', 'end 1',
      'begin 2', 'locateViews 2', 'views 2', 'tick 2', 'render 2 (2 eyes)', 'end 2',
      'begin 3', 'tick 3', 'end 3 (empty)',
      'begin 4', 'locateViews 4', 'views 4', 'tick 4', 'render 4 (2 eyes)', 'end 4',
    ]);
    // The delta comes from the predicted display times (13.889 ms apart).
    expect(deltas.skip(1), everyElement(closeTo(0.013889, 1e-6)));
    expect(loop.frames, 4);
    expect(loop.renderedFrames, 3);
    expect(loop.lateFrames, 0);
    expect(loop.history.length, 4);
  });

  test('STOPPING stops the pacer before the next frame', () {
    final simulator = SimulatedOpenXrBackend();
    final pacer = OpenXrSimulatedPacer(simulator, automatic: false);
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: _RecordingRenderer(pacer.log));
    final session = OpenXrSession(backend: simulator)
      ..onSessionBegan = loop.start
      ..onSessionEnding = loop.stop;
    expect(session.beginSession().isSuccess, isTrue);
    expect(loop.running, isTrue);
    pacer.tick();
    simulator.requestExitSession();
    session.pollEvents();
    expect(loop.running, isFalse);
    pacer.tick();
    expect(loop.frames, 1, reason: 'no frame after STOPPING');
  });
}
