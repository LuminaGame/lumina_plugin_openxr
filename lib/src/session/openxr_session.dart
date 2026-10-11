import 'package:logging/logging.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_composition.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_bindings.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_session_state_machine.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_space.dart';

final _log = Logger('OpenXrSession');

/// An OpenXR session and its reference spaces. The state follows the
/// runtime's events ([pollEvents]); this class carries out what the state
/// machine asks for (begin, end, recreate, quit).
class OpenXrSession {
  OpenXrSession({OpenXrBindings? bindings, OpenXrBackend? backend})
      : _bindings = bindings ?? OpenXrBindings.instance,
        _backendOverride = backend {
    _currentSpace = OpenXrReferenceSpace(originType: _trackingOrigin);
  }

  final OpenXrBindings _bindings;
  final OpenXrBackend? _backendOverride;
  final OpenXrSessionStateMachine machine = OpenXrSessionStateMachine();
  OpenXrTrackingOrigin _trackingOrigin = OpenXrTrackingOrigin.floorLevel;
  late final OpenXrReferenceSpace _currentSpace;
  bool _started = false;

  /// Called after the session began (start the frame loop there) and before
  /// it ends (stop it there).
  void Function()? onSessionBegan;
  void Function()? onSessionEnding;

  /// Called when the runtime asks the application to quit (EXITING).
  void Function()? onExitRequested;

  /// Every polled event goes to these too (another plugin decodes its
  /// extension's events, `OpenXrOtherEvent`).
  final List<void Function(OpenXrRuntimeEvent event)> eventListeners = [];

  /// Called when the runtime switched a hand's interaction profile
  /// (`OpenXrInputSystem.refreshInteractionProfiles`).
  void Function()? onInteractionProfileChanged;

  /// The renderer's device-info functions (`openXrFilamentDeviceInfo()`):
  /// a native session creates its Vulkan device with them. Without them a
  /// native session cannot start.
  OpenXrVulkanDeviceInfoFunctions? vulkanDeviceInfo;

  /// Whether the device is created with multiview (both eyes in one pass).
  bool multiview = true;

  /// The backend this session runs on.
  OpenXrBackend get backend => _backendOverride ?? _bindings.backend;

  OpenXrSessionState get state => machine.state;
  OpenXrTrackingOrigin get trackingOrigin => _trackingOrigin;
  OpenXrReferenceSpace get currentSpace => _currentSpace;

  /// The reference space type of [trackingOrigin].
  int get referenceSpaceType => switch (_trackingOrigin) {
        OpenXrTrackingOrigin.eyeLevel => OpenXrReferenceSpaceType.local,
        OpenXrTrackingOrigin.floorLevel => OpenXrReferenceSpaceType.localFloor,
        OpenXrTrackingOrigin.stage => OpenXrReferenceSpaceType.stage,
      };

  /// Changes the tracking origin between floor level, eye level and stage.
  void setTrackingOrigin(OpenXrTrackingOrigin origin) {
    _trackingOrigin = origin;
    _currentSpace.offsetPosition.setZero();
    _currentSpace.offsetOrientation = vm.Quaternion.identity();
    _log.info('OpenXR tracking origin set to $origin');
  }

  /// Starts the session: the instance (and, natively, the Vulkan device and
  /// the session), then the events the runtime posts move it on; the
  /// simulator's are handled right away.
  XrResult beginSession() {
    try {
      final backend = this.backend;
      var r = backend.createInstance(optionalExtensions: [
        'XR_EXT_local_floor',
        'XR_FB_display_refresh_rate',
        'XR_FB_passthrough',
        'XR_EXT_hand_tracking',
        'XR_FB_composition_layer_alpha_blend',
        // The controller profiles that need an extension (Touch Plus).
        ...OpenXrInputBindings.defaults.extensions,
        // Other plugins' (passthrough, ...).
        ...OpenXrExtensionRequests.all,
      ]);
      if (r.isFailure) return r;
      if (backend is OpenXrNativeBackend) {
        final info = vulkanDeviceInfo;
        if (info == null) {
          _log.warning('a native OpenXR session needs the renderer\'s Vulkan device info (vulkanDeviceInfo)');
          return XrResult.errorInitializationFailed;
        }
        r = backend.createVulkanDevice(info, multiview: multiview);
        if (r.isFailure) return r;
        r = backend.createSession();
        if (r.isFailure) return r;
      }
      _started = true;
      pollEvents();
      return XrResult.success;
    } catch (e, stack) {
      OpenXrErrorReporter.report(e, stack, 'OpenXrSession.beginSession');
      return XrResult.errorInitializationFailed;
    }
  }

  /// Ends the session and destroys it.
  XrResult endSession() {
    try {
      if (machine.sessionRunning) {
        onSessionEnding?.call();
        backend.endSession();
        machine.sessionEnded();
      }
      backend.destroy();
      _bindings.shutdown();
      machine.reset();
      machine.onEvent(const OpenXrSessionStateChanged(OpenXrSessionState.stopping));
      _started = false;
      return XrResult.success;
    } catch (e, stack) {
      OpenXrErrorReporter.report(e, stack, 'OpenXrSession.endSession');
      return XrResult.errorInitializationFailed;
    }
  }

  /// Handles every waiting runtime event; returns them.
  List<OpenXrRuntimeEvent> pollEvents() {
    final handled = <OpenXrRuntimeEvent>[];
    if (!_started) return handled;
    try {
      for (var i = 0; i < 64; i++) {
        final event = backend.pollEvent();
        if (event == null) break;
        handled.add(event);
        if (event is OpenXrInteractionProfileChanged) onInteractionProfileChanged?.call();
        for (final listener in List.of(eventListeners)) {
          listener(event);
        }
        for (final action in machine.onEvent(event)) {
          _perform(action);
        }
      }
    } catch (e, stack) {
      OpenXrErrorReporter.report(e, stack, 'OpenXrSession.pollEvents');
    }
    return handled;
  }

  void _perform(OpenXrSessionAction action) {
    switch (action) {
      case OpenXrSessionAction.beginSession:
        if (backend.beginSession().isSuccess) {
          machine.sessionBegan();
          onSessionBegan?.call();
        }
      case OpenXrSessionAction.endSession:
        onSessionEnding?.call();
        backend.endSession();
        machine.sessionEnded();
      case OpenXrSessionAction.recreateInstance:
        onSessionEnding?.call();
        backend.destroy();
        machine.reset();
        _started = false;
      case OpenXrSessionAction.quit:
        onSessionEnding?.call();
        backend.destroy();
        _started = false;
        onExitRequested?.call();
    }
  }
}
