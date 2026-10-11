// ignore_for_file: non_constant_identifier_names
/// The native bridge's C API (`src/openxr_bridge_c.h`), resolved from the
/// `openxr_bridge` code asset the hook builds.
@DefaultAsset('package:lumina_plugin_openxr/openxr_bridge.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int32 Function()>()
external int openxr_bridge_is_runtime_available();

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> openxr_bridge_get_active_runtime_path();

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> openxr_bridge_get_active_runtime_name();

@Native<Int32 Function()>()
external int openxr_bridge_initialize();

@Native<Void Function()>()
external void openxr_bridge_shutdown();

@Native<Bool Function()>()
external bool openxr_bridge_loader_loaded();

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> openxr_bridge_last_error();

@Native<Int32 Function()>()
external int openxr_bridge_initialize_loader_android();

@Native<Bool Function()>()
external bool openxr_bridge_has_android_activity();

@Native<Int32 Function(Pointer<Utf8>, Pointer<Utf8>)>()
external int openxr_bridge_create_instance(Pointer<Utf8> applicationName, Pointer<Utf8> optionalExtensions);

@Native<Bool Function(Pointer<Utf8>)>()
external bool openxr_bridge_extension_enabled(Pointer<Utf8> name);

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> openxr_bridge_runtime_name();

@Native<Uint64 Function()>()
external int openxr_bridge_runtime_version();

@Native<Int32 Function()>()
external int openxr_bridge_get_system();

@Native<Pointer<Utf8> Function()>()
external Pointer<Utf8> openxr_bridge_system_name();

@Native<Uint32 Function()>()
external int openxr_bridge_view_count();

@Native<Int32 Function(Uint32, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>)>()
external int openxr_bridge_view_configuration(int index, Pointer<Uint32> recommendedWidth,
    Pointer<Uint32> recommendedHeight, Pointer<Uint32> maxWidth, Pointer<Uint32> maxHeight,
    Pointer<Uint32> recommendedSamples);

@Native<Uint32 Function(Pointer<Uint32>, Uint32)>()
external int openxr_bridge_blend_modes(Pointer<Uint32> out, int capacity);

/// `openxr_bridge_vulkan`.
final class OpenXrBridgeVulkan extends Struct {
  external Pointer<Void> instance;
  external Pointer<Void> physicalDevice;
  external Pointer<Void> device;
  @Uint32()
  external int queueFamily;
  @Uint32()
  external int filamentQueueIndex;
  @Uint32()
  external int runtimeQueueIndex;
  @Bool()
  external bool multiview;
}

@Native<
    Int32 Function(Bool, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>,
        Pointer<OpenXrBridgeVulkan>)>()
external int openxr_bridge_create_vulkan_device(
    bool multiview,
    Pointer<Void> infoCreate,
    Pointer<Void> infoCreateInfo,
    Pointer<Void> infoQueueFamily,
    Pointer<Void> infoFilamentQueue,
    Pointer<Void> infoMultiview,
    Pointer<Void> infoDestroy,
    Pointer<OpenXrBridgeVulkan> out);

@Native<Int32 Function()>()
external int openxr_bridge_create_session();

/// `openxr_bridge_event`.
final class OpenXrBridgeEvent extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int state;
  @Int64()
  external int time;
  @Float()
  external double value;
  @Int32()
  external int spaceType;
}

@Native<Int32 Function(Pointer<OpenXrBridgeEvent>)>()
external int openxr_bridge_poll_event(Pointer<OpenXrBridgeEvent> out);

@Native<Int32 Function()>()
external int openxr_bridge_begin_session();

@Native<Int32 Function()>()
external int openxr_bridge_end_session();

@Native<Int32 Function()>()
external int openxr_bridge_request_exit_session();

@Native<Int32 Function()>()
external int openxr_bridge_destroy_session();

@Native<Int32 Function()>()
external int openxr_bridge_destroy_instance();

@Native<Int64 Function(Int32)>()
external int openxr_bridge_create_reference_space(int type);

@Native<Void Function(Int64)>()
external void openxr_bridge_destroy_space(int space);

/// `openxr_bridge_pose`.
final class OpenXrBridgePose extends Struct {
  @Array(3)
  external Array<Float> position;
  @Array(4)
  external Array<Float> orientation;
  @Uint64()
  external int flags;
}

@Native<Int32 Function(Int64, Int64, Int64, Pointer<OpenXrBridgePose>)>()
external int openxr_bridge_locate_space(int space, int base, int time, Pointer<OpenXrBridgePose> out);

/// `openxr_bridge_view`.
final class OpenXrBridgeView extends Struct {
  external OpenXrBridgePose pose;
  @Float()
  external double angleLeft;
  @Float()
  external double angleRight;
  @Float()
  external double angleUp;
  @Float()
  external double angleDown;
}

@Native<Int32 Function(Int64, Int64, Pointer<OpenXrBridgeView>, Uint32, Pointer<Uint32>, Pointer<Uint64>)>()
external int openxr_bridge_locate_views(int base, int time, Pointer<OpenXrBridgeView> out, int capacity,
    Pointer<Uint32> count, Pointer<Uint64> viewStateFlags);

/// `openxr_bridge_frame_callback`.
typedef OpenXrFrameCallbackNative = Void Function(Int64 predictedDisplayTime, Int32 shouldRender, Int64 frame);

@Native<Int32 Function(Pointer<NativeFunction<OpenXrFrameCallbackNative>>, Int32)>()
external int openxr_bridge_frame_loop_start(Pointer<NativeFunction<OpenXrFrameCallbackNative>> onFrame, int blendMode);

@Native<Void Function()>()
external void openxr_bridge_frame_loop_stop();

@Native<Bool Function()>()
external bool openxr_bridge_frame_loop_running();

@Native<Void Function(Pointer<Int64>, Pointer<Int64>, Pointer<Int64>, Pointer<Int64>)>()
external void openxr_bridge_frame_loop_stats(
    Pointer<Int64> frames, Pointer<Int64> emptyFrames, Pointer<Int64> missedFrames, Pointer<Int64> predictedPeriod);

@Native<Int64 Function()>()
external int openxr_bridge_last_predicted_display_time();

@Native<Int64 Function(Pointer<Int64>, Uint32)>()
external int openxr_bridge_swapchain_formats(Pointer<Int64> out, int capacity);

@Native<Int32 Function(Uint32, Uint32, Uint32, Int64)>()
external int openxr_bridge_create_swapchain(int width, int height, int arraySize, int format);

@Native<Pointer<Void> Function()>()
external Pointer<Void> openxr_bridge_swapchain_provider();

@Native<Void Function()>()
external void openxr_bridge_destroy_swapchain();

@Native<Int32 Function(Bool, Int64)>()
external int openxr_bridge_frame_loop_set_renderer(bool render, int space);

@Native<Uint32 Function(Int64, Pointer<OpenXrBridgeView>, Uint32)>()
external int openxr_bridge_frame_views(int frame, Pointer<OpenXrBridgeView> out, int capacity);

@Native<Void Function(Int64)>()
external void openxr_bridge_skip_frame(int frame);

@Native<Int64 Function()>()
external int openxr_bridge_rendered_frames();

@Native<Uint32 Function(Pointer<Float>, Uint32)>()
external int openxr_bridge_display_refresh_rates(Pointer<Float> out, int capacity);

@Native<Float Function()>()
external double openxr_bridge_display_refresh_rate();

@Native<Int32 Function(Float)>()
external int openxr_bridge_request_display_refresh_rate(double hz);
