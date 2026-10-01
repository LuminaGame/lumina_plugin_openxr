import 'package:logging/logging.dart';
import 'package:vector_math/vector_math_64.dart' as vm;
import '../ffi/openxr_bindings.dart';
import '../ffi/openxr_types.dart';
import 'openxr_space.dart';

final _log = Logger('OpenXrSession');

/// Manages an active OpenXR session and its reference spaces.
class OpenXrSession {
  final OpenXrBindings _bindings;
  OpenXrSessionState _state = OpenXrSessionState.idle;
  OpenXrTrackingOrigin _trackingOrigin = OpenXrTrackingOrigin.floorLevel;
  late final OpenXrReferenceSpace _currentSpace;

  OpenXrSession({OpenXrBindings? bindings})
      : _bindings = bindings ?? OpenXrBindings.instance {
    _currentSpace = OpenXrReferenceSpace(originType: _trackingOrigin);
  }

  OpenXrSessionState get state => _state;
  OpenXrTrackingOrigin get trackingOrigin => _trackingOrigin;
  OpenXrReferenceSpace get currentSpace => _currentSpace;

  /// Changes tracking origin between FloorLevel, EyeLevel, and Stage.
  void setTrackingOrigin(OpenXrTrackingOrigin origin) {
    _trackingOrigin = origin;
    _currentSpace.offsetPosition.setZero();
    _currentSpace.offsetOrientation = vm.Quaternion.identity();
    _log.info('OpenXR tracking origin set to $origin');
  }

  /// Begins the OpenXR session.
  XrResult beginSession() {
    final res = _bindings.initialize();
    if (res.isFailure) return res;

    if (_bindings.isSimulated) {
      final simRes = _bindings.simulator.beginSession();
      if (simRes.isSuccess) {
        _state = OpenXrSessionState.focused;
      }
      return simRes;
    }

    _state = OpenXrSessionState.focused;
    return XrResult.success;
  }

  /// Ends the OpenXR session.
  XrResult endSession() {
    if (_bindings.isSimulated) {
      _bindings.simulator.endSession();
    }
    _state = OpenXrSessionState.stopping;
    return XrResult.success;
  }

  /// Ticks frame lifecycle and queries runtime events.
  void pollEvents() {
    if (_bindings.isSimulated) {
      _state = _bindings.simulator.sessionState;
    }
  }
}
