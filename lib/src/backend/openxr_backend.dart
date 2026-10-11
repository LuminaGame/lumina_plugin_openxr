import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_backend.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';

/// One view of the primary stereo configuration: the image size the runtime
/// recommends and allows.
class OpenXrViewConfiguration {
  const OpenXrViewConfiguration({
    required this.recommendedWidth,
    required this.recommendedHeight,
    required this.maxWidth,
    required this.maxHeight,
    this.recommendedSamples = 1,
  });

  final int recommendedWidth;
  final int recommendedHeight;
  final int maxWidth;
  final int maxHeight;
  final int recommendedSamples;

  @override
  String toString() => '${recommendedWidth}x$recommendedHeight (max ${maxWidth}x$maxHeight)';
}

/// A located eye: pose in the base space (metres, OpenXR axes) and field of
/// view (radians, left and down negative).
class OpenXrEyeView {
  const OpenXrEyeView({
    required this.position,
    required this.orientation,
    required this.angleLeft,
    required this.angleRight,
    required this.angleUp,
    required this.angleDown,
  });

  final vm.Vector3 position;
  final vm.Quaternion orientation;
  final double angleLeft;
  final double angleRight;
  final double angleUp;
  final double angleDown;
}

/// `XrEnvironmentBlendMode`.
abstract final class OpenXrBlendMode {
  static const opaque = 1;
  static const additive = 2;
  static const alphaBlend = 3;

  static String name(int mode) => switch (mode) {
        opaque => 'OPAQUE',
        additive => 'ADDITIVE',
        alphaBlend => 'ALPHA_BLEND',
        _ => 'blend mode $mode',
      };
}

/// `XrReferenceSpaceType`.
abstract final class OpenXrReferenceSpaceType {
  static const view = 1;
  static const local = 2;
  static const stage = 3;
  static const localFloor = 1000426000;
}

/// An OpenXR runtime: the real one through the native bridge
/// ([OpenXrNativeBackend]) or the simulated headset
/// ([SimulatedOpenXrBackend], the editor and CI default). Either way the
/// session follows the events [pollEvent] returns.
abstract interface class OpenXrBackend {
  /// True for a real runtime.
  bool get isNative;

  /// The runtime's name ("Oculus", "SteamVR", "Lumina Simulated HMD").
  String get runtimeName;

  /// The headset's name (`XrSystemProperties::systemName`).
  String get systemName;

  /// The views of the primary stereo configuration.
  List<OpenXrViewConfiguration> get viewConfigurations;

  /// `XrEnvironmentBlendMode` values the runtime offers, preferred first.
  List<int> get blendModes;

  /// Loader, instance and system. [optionalExtensions] are enabled when the
  /// runtime offers them.
  XrResult createInstance({String applicationName = 'Lumina', List<String> optionalExtensions = const []});

  /// Whether the instance was created with [extension].
  bool extensionEnabled(String extension);

  /// The next runtime event, or null when none is waiting.
  OpenXrRuntimeEvent? pollEvent();

  XrResult beginSession();
  XrResult endSession();
  XrResult requestExitSession();

  /// The two eyes in [baseSpace] (an [OpenXrReferenceSpaceType]) at [displayTime] (ns).
  List<OpenXrEyeView> locateViews(int baseSpace, int displayTime);

  /// The controllers: actions, bindings, per-frame sync, haptics.
  OpenXrInputBackend get input;

  /// Destroys the session and the instance.
  void destroy();
}
