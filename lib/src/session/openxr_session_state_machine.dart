import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';

/// What the application must do after a runtime event.
enum OpenXrSessionAction {
  /// `xrBeginSession` (the session became READY), then start the frame loop.
  beginSession,

  /// Stop the frame loop, then `xrEndSession` (STOPPING).
  endSession,

  /// Destroy the session and the instance; create them again later
  /// (LOSS_PENDING, or the instance is about to be lost).
  recreateInstance,

  /// Destroy everything and tell the application to quit (EXITING).
  quit,
}

/// The OpenXR session lifecycle as the specification defines it:
/// `IDLE → READY → (begin) → SYNCHRONIZED → VISIBLE → FOCUSED → … →
/// STOPPING → (end) → IDLE`, plus `LOSS_PENDING` and `EXITING`. Every state
/// change comes from a runtime event ([onEvent]); this class only decides
/// what the application does about it, so it is tested by replaying recorded
/// event sequences.
class OpenXrSessionStateMachine {
  OpenXrSessionState _state = OpenXrSessionState.idle;
  bool _running = false;
  final List<OpenXrSessionState> _history = [];

  /// The last state the runtime reported.
  OpenXrSessionState get state => _state;

  /// Every state reported so far, in order.
  List<OpenXrSessionState> get history => List.unmodifiable(_history);

  /// Between a successful `xrBeginSession` and `xrEndSession`: the frame loop
  /// must run (the runtime reaches SYNCHRONIZED only through it).
  bool get sessionRunning => _running;

  /// Whether frames are shown: VISIBLE or FOCUSED.
  bool get visible => _state == OpenXrSessionState.visible || _state == OpenXrSessionState.focused;

  /// Whether input reaches the application: FOCUSED.
  bool get focused => _state == OpenXrSessionState.focused;

  /// The actions [event] calls for, in order.
  List<OpenXrSessionAction> onEvent(OpenXrRuntimeEvent event) {
    switch (event) {
      case OpenXrSessionStateChanged(:final state):
        _state = state;
        _history.add(state);
        switch (state) {
          case OpenXrSessionState.ready:
            return _running ? const [] : const [OpenXrSessionAction.beginSession];
          case OpenXrSessionState.stopping:
            return _running ? const [OpenXrSessionAction.endSession] : const [];
          case OpenXrSessionState.lossPending:
            _running = false;
            return const [OpenXrSessionAction.recreateInstance];
          case OpenXrSessionState.exiting:
            _running = false;
            return const [OpenXrSessionAction.quit];
          default:
            return const [];
        }
      case OpenXrInstanceLossPending():
        _running = false;
        return const [OpenXrSessionAction.recreateInstance];
      default:
        return const [];
    }
  }

  /// `xrBeginSession` succeeded.
  void sessionBegan() => _running = true;

  /// `xrEndSession` was called.
  void sessionEnded() => _running = false;

  /// Back to IDLE after the instance was torn down.
  void reset() {
    _state = OpenXrSessionState.idle;
    _running = false;
  }
}
