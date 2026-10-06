import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'openxr_types.dart';
import 'simulated_openxr_backend.dart';

final _log = Logger('OpenXrBindings');

typedef _IsRuntimeAvailableC = Int32 Function();
typedef _IsRuntimeAvailableDart = int Function();

typedef _GetActiveRuntimeStringC = Pointer<Utf8> Function();
typedef _GetActiveRuntimeStringDart = Pointer<Utf8> Function();

typedef _InitializeC = Int32 Function();
typedef _InitializeDart = int Function();

typedef _ShutdownC = Void Function();
typedef _ShutdownDart = void Function();

/// Unified OpenXR Native and Simulated bindings manager.
class OpenXrBindings {
  static final OpenXrBindings instance = OpenXrBindings._();

  DynamicLibrary? _bridgeLib;
  bool _forceSimulation = false;
  final SimulatedOpenXrBackend _simulator = SimulatedOpenXrBackend();

  OpenXrBindings._() {
    _tryLoadNativeBridge();
  }

  void _tryLoadNativeBridge() {
    try {
      if (Platform.isWindows) {
        _bridgeLib = DynamicLibrary.open('openxr_bridge.dll');
      } else if (Platform.isLinux) {
        _bridgeLib = DynamicLibrary.open('libopenxr_bridge.so');
      } else if (Platform.isMacOS) {
        _bridgeLib = DynamicLibrary.open('libopenxr_bridge.dylib');
      }
    } catch (e) {
      // Library not built or not found in search path; will use simulated runtime.
      _bridgeLib = null;
      _log.fine('Native OpenXR bridge not loaded ($e), falling back to simulated runtime');
    }
  }

  /// The underlying simulated backend.
  SimulatedOpenXrBackend get simulator => _simulator;

  /// Whether simulated runtime is currently forced or active.
  bool get isSimulated => _forceSimulation || !isNativeRuntimeAvailable;

  /// Toggles simulation mode manually.
  void setForceSimulation(bool force) {
    _forceSimulation = force;
  }

  /// Whether a native OpenXR loader and active runtime was detected on the host system.
  bool get isNativeRuntimeAvailable {
    final lib = _bridgeLib;
    if (lib == null) return false;
    try {
      final func = lib.lookupFunction<_IsRuntimeAvailableC, _IsRuntimeAvailableDart>('openxr_bridge_is_runtime_available');
      return func() == 1;
    } catch (e, stack) {
      _log.warning('Failed to query native OpenXR bridge runtime status', e);
      LuminaPluginCrashReporter.reportCrash(
        e,
        stack,
        plugin: 'lumina_plugin_openxr',
        context: 'isNativeRuntimeAvailable: openxr_bridge_is_runtime_available',
      );
      return false;
    }
  }

  /// Active runtime name (e.g. "Meta Quest / Oculus Link", "SteamVR", or "Lumina Simulated HMD").
  String get activeRuntimeName {
    if (_forceSimulation) return 'Lumina Simulated HMD';
    final lib = _bridgeLib;
    if (lib != null) {
      try {
        final func = lib.lookupFunction<_GetActiveRuntimeStringC, _GetActiveRuntimeStringDart>('openxr_bridge_get_active_runtime_name');
        final ptr = func();
        if (ptr != nullptr) {
          final str = ptr.toDartString();
          if (str.isNotEmpty && str != 'None') return str;
        }
      } catch (e, stack) {
        _log.warning('Failed to get active OpenXR runtime name', e);
        LuminaPluginCrashReporter.reportCrash(
          e,
          stack,
          plugin: 'lumina_plugin_openxr',
          context: 'activeRuntimeName: openxr_bridge_get_active_runtime_name',
        );
      }
    }
    return isNativeRuntimeAvailable ? 'OpenXR Native Runtime' : 'Lumina Simulated HMD';
  }

  /// Path to the active runtime manifest JSON if known.
  String get activeRuntimePath {
    if (_forceSimulation) return 'internal://simulated';
    final lib = _bridgeLib;
    if (lib != null) {
      try {
        final func = lib.lookupFunction<_GetActiveRuntimeStringC, _GetActiveRuntimeStringDart>('openxr_bridge_get_active_runtime_path');
        final ptr = func();
        if (ptr != nullptr) {
          return ptr.toDartString();
        }
      } catch (e, stack) {
        _log.warning('Failed to get active OpenXR runtime path', e);
        LuminaPluginCrashReporter.reportCrash(
          e,
          stack,
          plugin: 'lumina_plugin_openxr',
          context: 'activeRuntimePath: openxr_bridge_get_active_runtime_path',
        );
      }
    }
    return '';
  }

  /// Initializes the OpenXR instance.
  XrResult initialize() {
    if (isSimulated) {
      return _simulator.initialize();
    }

    final lib = _bridgeLib;
    if (lib != null) {
      try {
        final func = lib.lookupFunction<_InitializeC, _InitializeDart>('openxr_bridge_initialize');
        final res = func();
        return res == 0 ? XrResult.success : XrResult.errorInitializationFailed;
      } catch (e, stack) {
        _log.warning('Native OpenXR bridge initialization failed, falling back to simulator', e);
        LuminaPluginCrashReporter.reportCrash(
          e,
          stack,
          plugin: 'lumina_plugin_openxr',
          context: 'initialize: openxr_bridge_initialize',
        );
      }
    }
    return _simulator.initialize();
  }

  /// Shuts down the OpenXR instance.
  void shutdown() {
    if (isSimulated) {
      _simulator.shutdown();
      return;
    }
    final lib = _bridgeLib;
    if (lib != null) {
      try {
        final func = lib.lookupFunction<_ShutdownC, _ShutdownDart>('openxr_bridge_shutdown');
        func();
      } catch (e, stack) {
        _log.warning('Native OpenXR bridge shutdown failed', e);
        LuminaPluginCrashReporter.reportCrash(
          e,
          stack,
          plugin: 'lumina_plugin_openxr',
          context: 'shutdown: openxr_bridge_shutdown',
        );
      }
    }
    _simulator.shutdown();
  }
}
