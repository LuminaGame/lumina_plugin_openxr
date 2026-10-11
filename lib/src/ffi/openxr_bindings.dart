import 'package:ffi/ffi.dart';

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bridge_ffi.dart' as b;
import 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/ffi/simulated_openxr_backend.dart';

/// The runtime choice: the installed OpenXR runtime through the native bridge
/// ([OpenXrNativeBackend]) when there is one, else (or when forced) the
/// simulated headset. Calls into the bridge are guarded: a failure is
/// reported through [OpenXrErrorReporter] and the simulator takes over.
class OpenXrBindings {
  static final OpenXrBindings instance = OpenXrBindings._();

  OpenXrBindings._();

  bool _forceSimulation = false;
  final SimulatedOpenXrBackend _simulator = SimulatedOpenXrBackend();
  OpenXrNativeBackend? _native;

  /// The simulated headset.
  SimulatedOpenXrBackend get simulator => _simulator;

  /// The native backend (created on first use).
  OpenXrNativeBackend get native => _native ??= OpenXrNativeBackend();

  /// The backend in use: native when a runtime is available and simulation
  /// is not forced.
  OpenXrBackend get backend => isSimulated ? _simulator : native;

  /// Whether the simulated runtime is in use.
  bool get isSimulated => _forceSimulation || !isNativeRuntimeAvailable;

  /// Whether [setForceSimulation] forced the simulated runtime.
  bool get isSimulationForced => _forceSimulation;

  /// Forces the simulated runtime even when a native one exists.
  void setForceSimulation(bool force) => _forceSimulation = force;

  /// Whether an OpenXR runtime is registered (desktop) or reachable through
  /// the runtime broker (Android), and the bridge loads.
  bool get isNativeRuntimeAvailable => OpenXrNativeBackend.runtimeAvailable;

  /// The active runtime's name ("SteamVR", "Meta Quest / Oculus Link", ...),
  /// or "Lumina Simulated HMD".
  String get activeRuntimeName {
    if (isSimulated) return _simulator.runtimeName;
    final name = OpenXrErrorReporter.guard(
        'activeRuntimeName: openxr_bridge_get_active_runtime_name', () => b.openxr_bridge_get_active_runtime_name().toDartString(), '');
    return name.isEmpty || name == 'None' ? 'OpenXR Native Runtime' : name;
  }

  /// The active runtime's manifest path, if known.
  String get activeRuntimePath {
    if (_forceSimulation) return 'internal://simulated';
    return OpenXrErrorReporter.guard(
        'activeRuntimePath: openxr_bridge_get_active_runtime_path', () => b.openxr_bridge_get_active_runtime_path().toDartString(), '');
  }

  /// Loads the loader (native) or starts the simulator.
  XrResult initialize() {
    if (isSimulated) return _simulator.initialize();
    final ok = OpenXrErrorReporter.guard('initialize: openxr_bridge_initialize', () => b.openxr_bridge_initialize() == 0, false);
    if (ok) return XrResult.success;
    return _simulator.initialize();
  }

  /// Destroys the native session and instance, or stops the simulator.
  void shutdown() {
    if (!isSimulated) {
      OpenXrErrorReporter.guard('shutdown: openxr_bridge_shutdown', b.openxr_bridge_shutdown, null);
    }
    _simulator.shutdown();
  }
}
