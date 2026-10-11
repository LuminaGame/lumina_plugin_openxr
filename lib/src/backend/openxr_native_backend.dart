import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bridge_ffi.dart' as b;
import 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_composition.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_native_input.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';

final _log = Logger('OpenXrNativeBackend');

/// The addresses of the renderer's device-info C functions (flutter_filament's
/// `filament_external_vulkan_device_info_*`; `openXrFilamentDeviceInfo()`
/// supplies them): the bridge creates the Vulkan device with what the
/// renderer needs, without this library depending on the renderer.
class OpenXrVulkanDeviceInfoFunctions {
  const OpenXrVulkanDeviceInfoFunctions({
    required this.create,
    required this.createInfo,
    required this.queueFamily,
    required this.filamentQueueIndex,
    required this.multiview,
    required this.destroy,
  });

  final Pointer<Void> create;
  final Pointer<Void> createInfo;
  final Pointer<Void> queueFamily;
  final Pointer<Void> filamentQueueIndex;
  final Pointer<Void> multiview;
  final Pointer<Void> destroy;
}

/// The Vulkan objects `XR_KHR_vulkan_enable2` created: instance, physical
/// device and device (addresses), the graphics queue family, the renderer's
/// queue and the runtime's queue in it, and whether multiview is enabled.
class OpenXrVulkanDevice {
  const OpenXrVulkanDevice({
    required this.instance,
    required this.physicalDevice,
    required this.device,
    required this.queueFamily,
    required this.rendererQueueIndex,
    required this.runtimeQueueIndex,
    required this.multiview,
  });

  final int instance;
  final int physicalDevice;
  final int device;
  final int queueFamily;
  final int rendererQueueIndex;
  final int runtimeQueueIndex;
  final bool multiview;

  @override
  String toString() => 'OpenXrVulkanDevice(family $queueFamily, renderer queue $rendererQueueIndex, '
      'runtime queue $runtimeQueueIndex, multiview $multiview)';
}

/// The installed OpenXR runtime through the native bridge: the Khronos
/// loader (bundled on Android, the runtime's on desktop), an instance with
/// `XR_KHR_vulkan_enable2`, the Vulkan device Filament adopts, the session
/// and its reference spaces. Every call is guarded: a failure at the native
/// boundary is reported ([OpenXrErrorReporter]) and returned as an
/// [XrResult], never thrown.
class OpenXrNativeBackend implements OpenXrBackend {
  OpenXrNativeBackend();

  final Map<int, int> _spaces = {};

  @override
  late final OpenXrNativeInput input = OpenXrNativeInput(this);
  List<OpenXrViewConfiguration> _views = const [];
  List<int> _blendModes = const [];
  OpenXrVulkanDevice? _vulkan;

  /// The last failure the bridge recorded.
  String get lastError => OpenXrErrorReporter.guard('lastError', () => b.openxr_bridge_last_error().toDartString(), '');

  /// Whether a runtime is registered (desktop) or the broker will be asked (Android).
  static bool get runtimeAvailable =>
      OpenXrErrorReporter.guard('runtimeAvailable', () => b.openxr_bridge_is_runtime_available() == 1, false);

  @override
  bool get isNative => true;

  @override
  String get runtimeName => OpenXrErrorReporter.guard('runtimeName', () => b.openxr_bridge_runtime_name().toDartString(), '');

  @override
  String get systemName => OpenXrErrorReporter.guard('systemName', () => b.openxr_bridge_system_name().toDartString(), '');

  @override
  List<OpenXrViewConfiguration> get viewConfigurations => _views;

  @override
  List<int> get blendModes => _blendModes;

  /// The Vulkan objects [createVulkanDevice] made (for
  /// `FilamentEngine.createOnExternalVulkan`, see `OpenXrFilamentBridge`).
  OpenXrVulkanDevice? get vulkan => _vulkan;

  XrResult _result(String context, int Function() call) {
    final value = OpenXrErrorReporter.guard(context, call, XrResult.errorRuntimeFailure.value);
    final result = XrResult.fromValue(value);
    if (result.isFailure) _log.warning('$context failed: $lastError');
    return result;
  }

  @override
  XrResult createInstance({String applicationName = 'Lumina', List<String> optionalExtensions = const []}) {
    var r = _result('openxr_bridge_initialize', () => b.openxr_bridge_initialize() == 0 ? 0 : XrResult.errorRuntimeFailure.value);
    if (r.isFailure) return r;
    r = _result('openxr_bridge_initialize_loader_android', b.openxr_bridge_initialize_loader_android);
    if (r.isFailure) return r;
    r = _result('openxr_bridge_create_instance', () => using((arena) => b.openxr_bridge_create_instance(
        applicationName.toNativeUtf8(allocator: arena), optionalExtensions.join(',').toNativeUtf8(allocator: arena))));
    if (r.isFailure) return r;
    r = _result('openxr_bridge_get_system', b.openxr_bridge_get_system);
    if (r.isFailure) return r;
    _views = OpenXrErrorReporter.guard('views', _readViews, const <OpenXrViewConfiguration>[]);
    _blendModes = OpenXrErrorReporter.guard('blendModes', () => using((arena) {
      final out = arena<Uint32>(8);
      final n = b.openxr_bridge_blend_modes(out, 8);
      return [for (var i = 0; i < n && i < 8; i++) out[i]];
    }), const <int>[]);
    return r;
  }

  List<OpenXrViewConfiguration> _readViews() => using((arena) {
        final n = b.openxr_bridge_view_count();
        final values = arena<Uint32>(5);
        return [
          for (var i = 0; i < n; i++)
            if (b.openxr_bridge_view_configuration(i, values, values + 1, values + 2, values + 3, values + 4) >= 0)
              OpenXrViewConfiguration(
                recommendedWidth: values[0],
                recommendedHeight: values[1],
                maxWidth: values[2],
                maxHeight: values[3],
                recommendedSamples: values[4],
              ),
        ];
      });

  @override
  bool extensionEnabled(String extension) => OpenXrErrorReporter.guard(
      'extensionEnabled', () => using((arena) => b.openxr_bridge_extension_enabled(extension.toNativeUtf8(allocator: arena))), false);

  /// The Vulkan instance and device through `XR_KHR_vulkan_enable2`, created
  /// with what Filament needs (multiview when [multiview] and supported),
  /// with a queue for the runtime and one for Filament.
  XrResult createVulkanDevice(OpenXrVulkanDeviceInfoFunctions info, {bool multiview = true}) {
    final r = _result('openxr_bridge_create_vulkan_device', () => using((arena) {
      final out = arena<b.OpenXrBridgeVulkan>();
      final result = b.openxr_bridge_create_vulkan_device(
        multiview,
        info.create,
        info.createInfo,
        info.queueFamily,
        info.filamentQueueIndex,
        info.multiview,
        info.destroy,
        out,
      );
      if (result >= 0) {
        _vulkan = OpenXrVulkanDevice(
          instance: out.ref.instance.address,
          physicalDevice: out.ref.physicalDevice.address,
          device: out.ref.device.address,
          queueFamily: out.ref.queueFamily,
          rendererQueueIndex: out.ref.filamentQueueIndex,
          runtimeQueueIndex: out.ref.runtimeQueueIndex,
          multiview: out.ref.multiview,
        );
      }
      return result;
    }));
    return r;
  }

  /// `xrCreateSession` with the Vulkan binding.
  XrResult createSession() => _result('openxr_bridge_create_session', b.openxr_bridge_create_session);

  @override
  OpenXrRuntimeEvent? pollEvent() => OpenXrErrorReporter.guard('pollEvent', () => using((arena) {
        final out = arena<b.OpenXrBridgeEvent>();
        final r = b.openxr_bridge_poll_event(out);
        if (r != 1) return null;
        return OpenXrRuntimeEvent.fromNative(
            kind: out.ref.kind,
            state: out.ref.state,
            time: out.ref.time,
            value: out.ref.value,
            spaceType: out.ref.spaceType,
            structureType: out.ref.structureType,
            payload: out.ref.payload);
      }), null);

  @override
  XrResult beginSession() => _result('openxr_bridge_begin_session', b.openxr_bridge_begin_session);

  @override
  XrResult endSession() => _result('openxr_bridge_end_session', b.openxr_bridge_end_session);

  @override
  XrResult requestExitSession() => _result('openxr_bridge_request_exit_session', b.openxr_bridge_request_exit_session);

  /// The bridge's id of reference space [type] ([OpenXrReferenceSpaceType]),
  /// created on first use; null when the runtime refuses it.
  int? space(int type) {
    final known = _spaces[type];
    if (known != null) return known;
    final id = OpenXrErrorReporter.guard('createReferenceSpace', () => b.openxr_bridge_create_reference_space(type), -1);
    if (id <= 0) return null;
    return _spaces[type] = id;
  }

  /// [space] located in [base] (both [OpenXrReferenceSpaceType]s) at [time].
  ({vm.Vector3 position, vm.Quaternion orientation, int flags})? locateSpace(int space, int base, int time) {
    final s = this.space(space);
    final bs = this.space(base);
    if (s == null || bs == null) return null;
    return OpenXrErrorReporter.guard('locateSpace', () => using((arena) {
      final out = arena<b.OpenXrBridgePose>();
      if (b.openxr_bridge_locate_space(s, bs, time, out) < 0) return null;
      return (position: _position(out.ref), orientation: _orientation(out.ref), flags: out.ref.flags);
    }), null);
  }

  @override
  List<OpenXrEyeView> locateViews(int baseSpace, int displayTime) {
    final base = space(baseSpace);
    if (base == null) return const [];
    return OpenXrErrorReporter.guard('locateViews', () => using((arena) {
      final out = arena<b.OpenXrBridgeView>(4);
      final count = arena<Uint32>();
      final flags = arena<Uint64>();
      if (b.openxr_bridge_locate_views(base, displayTime, out, 4, count, flags) < 0) return const <OpenXrEyeView>[];
      return [
        for (var i = 0; i < count.value && i < 4; i++)
          OpenXrEyeView(
            position: _position(out[i].pose),
            orientation: _orientation(out[i].pose),
            angleLeft: out[i].angleLeft,
            angleRight: out[i].angleRight,
            angleUp: out[i].angleUp,
            angleDown: out[i].angleDown,
          ),
      ];
    }), const <OpenXrEyeView>[]);
  }

  static vm.Vector3 _position(b.OpenXrBridgePose p) => vm.Vector3(p.position[0], p.position[1], p.position[2]);

  static vm.Quaternion _orientation(b.OpenXrBridgePose p) =>
      vm.Quaternion(p.orientation[0], p.orientation[1], p.orientation[2], p.orientation[3]);

  /// Starts the native frame loop (a pacer thread around `xrWaitFrame`);
  /// [onFrame] runs on this isolate after each wait.
  XrResult startFrameLoop(NativeCallable<b.OpenXrFrameCallbackNative>? onFrame, {int blendMode = OpenXrBlendMode.opaque}) =>
      _result('openxr_bridge_frame_loop_start',
          () => b.openxr_bridge_frame_loop_start(onFrame?.nativeFunction ?? nullptr, blendMode));

  void stopFrameLoop() => OpenXrErrorReporter.guard('stopFrameLoop', b.openxr_bridge_frame_loop_stop, null);

  /// The swapchain formats the runtime offers (VkFormat values), preferred first.
  List<int> get swapchainFormats => OpenXrErrorReporter.guard('swapchainFormats', () => using((arena) {
        final out = arena<Int64>(32);
        final n = b.openxr_bridge_swapchain_formats(out, 32);
        return [for (var i = 0; i < n && i < 32; i++) out[i]];
      }), const <int>[]);

  /// The compositor swapchain the renderer draws into ([layers] 2: one
  /// multiview image, layer i = eye i).
  XrResult createSwapchain({required int width, required int height, required int layers, required int format}) =>
      _result('openxr_bridge_create_swapchain', () => b.openxr_bridge_create_swapchain(width, height, layers, format));

  /// The swapchain as a flutter_filament external swapchain provider
  /// (`filament_external_swapchain_provider*`), owned by the bridge.
  Pointer<Void> get swapchainProvider =>
      OpenXrErrorReporter.guard('swapchainProvider', b.openxr_bridge_swapchain_provider, nullptr);

  void destroySwapchain() => OpenXrErrorReporter.guard('destroySwapchain', b.openxr_bridge_destroy_swapchain, null);

  /// Hands the frames the runtime wants rendered to the renderer (views located
  /// in reference space [spaceType]); false goes back to empty frames.
  XrResult setRenderer(bool render, int spaceType) {
    final id = space(spaceType);
    if (id == null) return XrResult.errorHandleInvalid;
    return _result('openxr_bridge_frame_loop_set_renderer', () => b.openxr_bridge_frame_loop_set_renderer(render, id));
  }

  /// The views of [frame] as the pacer located them for its predicted display
  /// time (empty when that frame is gone or untracked).
  List<OpenXrEyeView> frameViews(int frame) => OpenXrErrorReporter.guard('frameViews', () => using((arena) {
        final out = arena<b.OpenXrBridgeView>(2);
        final n = b.openxr_bridge_frame_views(frame, out, 2);
        return [
          for (var i = 0; i < n; i++)
            OpenXrEyeView(
              position: _position(out[i].pose),
              orientation: _orientation(out[i].pose),
              angleLeft: out[i].angleLeft,
              angleRight: out[i].angleRight,
              angleUp: out[i].angleUp,
              angleDown: out[i].angleDown,
            ),
        ];
      }), const <OpenXrEyeView>[]);

  /// The renderer will not render [frame]: the bridge ends it empty.
  void skipFrame(int frame) => OpenXrErrorReporter.guard('skipFrame', () => b.openxr_bridge_skip_frame(frame), null);

  /// The display refresh rates (Hz) the headset offers (XR_FB_display_refresh_rate).
  List<double> get displayRefreshRates => OpenXrErrorReporter.guard('displayRefreshRates', () => using((arena) {
        final out = arena<Float>(16);
        final n = b.openxr_bridge_display_refresh_rates(out, 16);
        return [for (var i = 0; i < n && i < 16; i++) out[i]];
      }), const <double>[]);

  /// The current display refresh rate (Hz), 0 when unknown.
  double get displayRefreshRate =>
      OpenXrErrorReporter.guard('displayRefreshRate', b.openxr_bridge_display_refresh_rate, 0.0);

  /// Asks the runtime for [hz] (one of [displayRefreshRates]).
  XrResult requestDisplayRefreshRate(double hz) =>
      _result('openxr_bridge_request_display_refresh_rate', () => b.openxr_bridge_request_display_refresh_rate(hz));

  /// The loader's `xrGetInstanceProcAddr` (for another plugin's native code), or null.
  Pointer<Void> get instanceProcAddr =>
      OpenXrErrorReporter.guard('instanceProcAddr', b.openxr_bridge_get_instance_proc_addr, nullptr);

  /// The `XrInstance` / `XrSession` handles (0 when there is none).
  int get instanceHandle => OpenXrErrorReporter.guard('instanceHandle', b.openxr_bridge_instance_handle, 0);
  int get sessionHandle => OpenXrErrorReporter.guard('sessionHandle', b.openxr_bridge_session_handle, 0);

  /// The layers every frame submits around the projection layer, and its flags.
  void setFrameComposition(OpenXrFrameComposition composition) => OpenXrErrorReporter.guard('setFrameComposition', () {
        using((arena) {
          Pointer<Pointer<Void>> list(List<OpenXrCompositionLayer> layers) {
            final out = arena<Pointer<Void>>(layers.isEmpty ? 1 : layers.length);
            for (var i = 0; i < layers.length; i++) {
              out[i] = Pointer<Void>.fromAddress(layers[i].address);
            }
            return out;
          }

          b.openxr_bridge_set_frame_layers(list(composition.before), composition.before.length, list(composition.after),
              composition.after.length, composition.projectionFlags);
          b.openxr_bridge_set_environment_blend_mode(composition.environmentBlendMode);
        });
      }, null);

  /// Frames ended with a projection layer.
  int get renderedFrames => OpenXrErrorReporter.guard('renderedFrames', b.openxr_bridge_rendered_frames, 0);

  /// Frames waited, ended empty, missed by the renderer, and the predicted display period.
  ({int frames, int empty, int missed, Duration period}) get frameStats =>
      OpenXrErrorReporter.guard('frameStats', () => using((arena) {
        final v = arena<Int64>(4);
        b.openxr_bridge_frame_loop_stats(v, v + 1, v + 2, v + 3);
        return (frames: v[0], empty: v[1], missed: v[2], period: Duration(microseconds: v[3] ~/ 1000));
      }), (frames: 0, empty: 0, missed: 0, period: Duration.zero));

  /// Destroys the session (its spaces, the frame loop) only.
  void destroySession() {
    _spaces.clear();
    input.forget();
    OpenXrErrorReporter.guard('destroySession', b.openxr_bridge_destroy_session, 0);
  }

  @override
  void destroy() {
    _spaces.clear();
    input.forget(instance: true);
    _vulkan = null;
    OpenXrErrorReporter.guard('destroy', () {
      b.openxr_bridge_destroy_session();
      b.openxr_bridge_destroy_instance();
    }, null);
  }
}
