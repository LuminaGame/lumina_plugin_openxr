import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

/// The session lifecycle follows the runtime's events: these are the
/// sequences a runtime posts, replayed through the event decoder and the
/// state machine.
void main() {
  /// Decodes `(kind, state)` pairs the way the bridge reports them.
  List<OpenXrRuntimeEvent> decode(List<(int, int)> raw) =>
      [for (final (kind, state) in raw) OpenXrRuntimeEvent.fromNative(kind: kind, state: state)];

  test('READY begins the session once; the frame loop runs from there, input from FOCUSED', () {
    final machine = OpenXrSessionStateMachine();
    final actions = <OpenXrSessionAction>[];
    // The order a Quest 3S (Horizon OS 2.7, runtime Oculus 207.298) posted after xrCreateSession:
    // LOCAL_FLOOR and STAGE change pending, IDLE, READY; then, with the frame loop running,
    // SYNCHRONIZED, VISIBLE, FOCUSED.
    final recorded = [
      OpenXrRuntimeEvent.fromNative(kind: 3, spaceType: OpenXrReferenceSpaceType.localFloor),
      OpenXrRuntimeEvent.fromNative(kind: 3, spaceType: OpenXrReferenceSpaceType.stage),
      ...decode(const [(1, 1), (1, 2), (1, 3), (1, 4), (1, 5)]),
    ];
    for (final event in recorded) {
      final a = machine.onEvent(event);
      actions.addAll(a);
      if (a.contains(OpenXrSessionAction.beginSession)) machine.sessionBegan();
      if (machine.state == OpenXrSessionState.synchronized) {
        expect(machine.sessionRunning, isTrue, reason: 'the frame loop must run to reach SYNCHRONIZED');
        expect(machine.visible, isFalse);
      }
    }
    expect(actions, [OpenXrSessionAction.beginSession]);
    expect(machine.state, OpenXrSessionState.focused);
    expect(machine.visible, isTrue);
    expect(machine.focused, isTrue);
    expect(machine.history, [
      OpenXrSessionState.idle,
      OpenXrSessionState.ready,
      OpenXrSessionState.synchronized,
      OpenXrSessionState.visible,
      OpenXrSessionState.focused,
    ]);
  });

  test('STOPPING ends a running session, and a second READY begins it again', () {
    final machine = OpenXrSessionStateMachine()
      ..onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.ready))
      ..sessionBegan();
    for (final s in [
      OpenXrSessionState.synchronized,
      OpenXrSessionState.visible,
      OpenXrSessionState.focused,
      OpenXrSessionState.visible,
      OpenXrSessionState.synchronized,
    ]) {
      expect(machine.onEvent(OpenXrSessionStateChanged(s)), isEmpty);
    }
    expect(machine.onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.stopping)),
        [OpenXrSessionAction.endSession]);
    machine.sessionEnded();
    expect(machine.onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.idle)), isEmpty);
    expect(machine.onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.ready)),
        [OpenXrSessionAction.beginSession]);
  });

  test('LOSS_PENDING and an instance loss tear the instance down for a later recreate', () {
    final machine = OpenXrSessionStateMachine()
      ..onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.ready))
      ..sessionBegan();
    expect(machine.onEvent(OpenXrRuntimeEvent.fromNative(kind: 1, state: 7)), [OpenXrSessionAction.recreateInstance]);
    expect(machine.sessionRunning, isFalse);
    expect(machine.onEvent(OpenXrRuntimeEvent.fromNative(kind: 2, time: 123)), [OpenXrSessionAction.recreateInstance]);
  });

  test('EXITING tells the application to quit', () {
    final machine = OpenXrSessionStateMachine();
    expect(machine.onEvent(OpenXrRuntimeEvent.fromNative(kind: 1, state: 8)), [OpenXrSessionAction.quit]);
  });

  test('other events change no state', () {
    final machine = OpenXrSessionStateMachine();
    for (final event in [
      OpenXrRuntimeEvent.fromNative(kind: 3, spaceType: OpenXrReferenceSpaceType.localFloor),
      OpenXrRuntimeEvent.fromNative(kind: 4),
      OpenXrRuntimeEvent.fromNative(kind: 6, value: 72),
    ]) {
      expect(machine.onEvent(event), isEmpty);
    }
    expect(machine.state, OpenXrSessionState.idle);
    expect(OpenXrRuntimeEvent.fromNative(kind: 6, value: 72), isA<OpenXrDisplayRefreshRateChanged>());
  });

  test('a session on the simulated runtime follows the same events', () {
    final simulator = SimulatedOpenXrBackend();
    final session = OpenXrSession(backend: simulator);
    var began = 0;
    session.onSessionBegan = () => began++;
    expect(session.beginSession().isSuccess, isTrue);
    expect(began, 1);
    expect(session.state, OpenXrSessionState.focused);
    simulator.requestExitSession();
    session.pollEvents();
    expect(session.machine.sessionRunning, isFalse, reason: 'STOPPING ended the session');
  });
}
