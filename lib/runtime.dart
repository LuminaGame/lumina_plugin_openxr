/// The OpenXR runtime library a game imports: the backends (the installed
/// runtime through the native bridge, the simulated headset), the session
/// and its state machine, spaces and conversions, the stereo maths, the
/// Filament bridge and the XR rig components. No editor, plugin-process or
/// editor-API code is reachable from here
/// (`test/runtime_import_graph_test.dart` guards it).
library;

export 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
export 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
export 'package:lumina_plugin_openxr/src/components/lumina_xr_controller_component.dart';
export 'package:lumina_plugin_openxr/src/components/lumina_xr_hmd_component.dart';
export 'package:lumina_plugin_openxr/src/components/lumina_xr_origin_actor.dart';
export 'package:lumina_plugin_openxr/src/ffi/openxr_bindings.dart';
export 'package:lumina_plugin_openxr/src/ffi/openxr_bridge_ffi.dart' show OpenXrFrameCallbackNative;
export 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
export 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
export 'package:lumina_plugin_openxr/src/ffi/simulated_openxr_backend.dart';
export 'package:lumina_plugin_openxr/src/frame/lumina_xr_world_driver.dart';
export 'package:lumina_plugin_openxr/src/frame/openxr_frame_loop.dart';
export 'package:lumina_plugin_openxr/src/frame/openxr_pacers.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_eye_camera.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_filament_bridge.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_filament_renderer.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_stereo_layout.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_stereo_view.dart';
export 'package:lumina_plugin_openxr/src/render/openxr_swapchain.dart';
export 'package:lumina_plugin_openxr/src/session/openxr_runtime_event.dart';
export 'package:lumina_plugin_openxr/src/session/openxr_session.dart';
export 'package:lumina_plugin_openxr/src/session/openxr_session_state_machine.dart';
export 'package:lumina_plugin_openxr/src/session/openxr_space.dart';
export 'package:lumina_plugin_openxr/xr_types.dart';
