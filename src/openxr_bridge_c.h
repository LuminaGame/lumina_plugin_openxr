#ifndef OPENXR_BRIDGE_C_H
#define OPENXR_BRIDGE_C_H

// The native side of lumina_plugin_openxr: runtime discovery, the OpenXR
// loader (desktop: the system loader; Android: the Khronos loader bundled
// from Maven Central), and a thin client of the OpenXR C API that Dart drives
// through FFI. Every call that talks to the runtime returns its XrResult;
// openxr_bridge_last_error describes the last failure.

#include <stdint.h>
#include <stdbool.h>

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Runtime discovery (desktop) and the loader.

/// Whether an OpenXR runtime is registered (desktop: XR_RUNTIME_JSON or the
/// Windows registry; Android: always 1, the runtime broker decides).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_is_runtime_available(void);
/// The active runtime manifest path, or "".
FFI_PLUGIN_EXPORT const char* openxr_bridge_get_active_runtime_path(void);
/// A readable runtime name ("SteamVR", "Meta Quest / Oculus Link", ...), or "None".
FFI_PLUGIN_EXPORT const char* openxr_bridge_get_active_runtime_name(void);
/// Loads the OpenXR loader library. 0 on success.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_initialize(void);
/// Destroys everything the bridge created and unloads the loader.
FFI_PLUGIN_EXPORT void openxr_bridge_shutdown(void);
/// Whether the loader is loaded and xrGetInstanceProcAddr was found.
FFI_PLUGIN_EXPORT bool openxr_bridge_loader_loaded(void);
/// The last failure, for logs ("" when none).
FFI_PLUGIN_EXPORT const char* openxr_bridge_last_error(void);

// ---------------------------------------------------------------------------
// Instance and system.

/// Android: xrInitializeLoaderKHR with the JavaVM and activity the plugin's
/// Kotlin part handed over (OpenXrPlugin). Returns XR_SUCCESS elsewhere.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_initialize_loader_android(void);
/// Whether the Kotlin plugin has handed the activity over (Android).
FFI_PLUGIN_EXPORT bool openxr_bridge_has_android_activity(void);

/// Creates the XrInstance with XR_KHR_vulkan_enable2 (and
/// XR_KHR_android_create_instance on Android) plus every extension of
/// `optional_extensions` (comma-separated) the runtime offers.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_create_instance(const char* application_name, const char* optional_extensions);
/// Whether the instance was created with [name] enabled.
FFI_PLUGIN_EXPORT bool openxr_bridge_extension_enabled(const char* name);
/// The runtime's name and version as the instance reports them.
FFI_PLUGIN_EXPORT const char* openxr_bridge_runtime_name(void);
FFI_PLUGIN_EXPORT uint64_t openxr_bridge_runtime_version(void);

/// xrGetSystem for a head-mounted display.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_get_system(void);
FFI_PLUGIN_EXPORT const char* openxr_bridge_system_name(void);
/// The recommended and maximum image size of view [index] of the primary
/// stereo configuration, and the view count.
FFI_PLUGIN_EXPORT uint32_t openxr_bridge_view_count(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_view_configuration(uint32_t index, uint32_t* recommended_width,
        uint32_t* recommended_height, uint32_t* max_width, uint32_t* max_height, uint32_t* recommended_samples);
/// The environment blend modes of the primary stereo configuration
/// (XrEnvironmentBlendMode values), most preferred first.
FFI_PLUGIN_EXPORT uint32_t openxr_bridge_blend_modes(uint32_t* out, uint32_t capacity);

// ---------------------------------------------------------------------------
// Vulkan through XR_KHR_vulkan_enable2.

/// flutter_filament's device-info entry points
/// (filament_external_vulkan_device_info_*), passed from Dart so the bridge
/// creates the device with what Filament needs without linking flutter_filament.
typedef void* (*openxr_bridge_device_info_create_fn)(void* instance, void* physical_device, bool multiview,
        const char* const* extra_extensions, uint32_t extra_extension_count);
typedef const void* (*openxr_bridge_device_info_get_fn)(void* info);
typedef uint32_t (*openxr_bridge_device_info_u32_fn)(void* info);
typedef bool (*openxr_bridge_device_info_bool_fn)(void* info);
typedef void (*openxr_bridge_device_info_destroy_fn)(void* info);

typedef struct openxr_bridge_vulkan {
    void* instance;
    void* physical_device;
    void* device;
    uint32_t queue_family;
    /// Filament's queue (1 when the family has two, else 0).
    uint32_t filament_queue_index;
    /// The runtime's queue (the graphics binding's), always 0.
    uint32_t runtime_queue_index;
    bool multiview;
} openxr_bridge_vulkan;

/// xrGetVulkanGraphicsRequirements2KHR, xrCreateVulkanInstanceKHR,
/// xrGetVulkanGraphicsDevice2KHR, then xrCreateVulkanDeviceKHR with the
/// VkDeviceCreateInfo flutter_filament's device info builds. Fills [out].
FFI_PLUGIN_EXPORT int32_t openxr_bridge_create_vulkan_device(bool multiview,
        openxr_bridge_device_info_create_fn info_create, openxr_bridge_device_info_get_fn info_create_info,
        openxr_bridge_device_info_u32_fn info_queue_family, openxr_bridge_device_info_u32_fn info_filament_queue,
        openxr_bridge_device_info_bool_fn info_multiview, openxr_bridge_device_info_destroy_fn info_destroy,
        openxr_bridge_vulkan* out);

// ---------------------------------------------------------------------------
// Session, events, spaces.

/// xrCreateSession with the Vulkan binding (the runtime's queue).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_create_session(void);

/// One polled event, decoded.
typedef struct openxr_bridge_event {
    /// 1 session state changed, 2 instance loss pending, 3 reference space
    /// change pending, 4 interaction profile changed, 5 events lost,
    /// 6 display refresh rate changed, 0 other.
    int32_t kind;
    /// The new XrSessionState (kind 1).
    int32_t state;
    /// The event's XrTime (kinds 1, 2, 3), nanoseconds.
    int64_t time;
    /// Kind 3: the XrReferenceSpaceType that changes; kind 6: the new rate (Hz).
    float value;
    int32_t space_type;
} openxr_bridge_event;

/// xrPollEvent: 1 and [out] filled when an event was waiting, 0 when none,
/// a negative XrResult on failure.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_poll_event(openxr_bridge_event* out);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_begin_session(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_end_session(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_request_exit_session(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_destroy_session(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_destroy_instance(void);

/// Reference space types: 1 VIEW, 2 LOCAL, 3 STAGE, 1000426000 LOCAL_FLOOR
/// (XR_EXT_local_floor / OpenXR 1.1). Returns a space id (> 0) or a
/// negative XrResult.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_create_reference_space(int32_t type);
FFI_PLUGIN_EXPORT void openxr_bridge_destroy_space(int64_t space);

/// A located pose: position (m) and orientation (x, y, z, w), the
/// XrSpaceLocationFlags.
typedef struct openxr_bridge_pose {
    float position[3];
    float orientation[4];
    uint64_t flags;
} openxr_bridge_pose;

/// xrLocateSpace of [space] in [base] at [time] (ns).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_locate_space(int64_t space, int64_t base, int64_t time,
        openxr_bridge_pose* out);

/// One eye: pose in the base space and field of view (radians).
typedef struct openxr_bridge_view {
    openxr_bridge_pose pose;
    float angle_left;
    float angle_right;
    float angle_up;
    float angle_down;
} openxr_bridge_view;

/// xrLocateViews of the primary stereo configuration in [base] at [time];
/// writes up to [capacity] views and the view state flags.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_locate_views(int64_t base, int64_t time, openxr_bridge_view* out,
        uint32_t capacity, uint32_t* count, uint64_t* view_state_flags);

// ---------------------------------------------------------------------------
// The frame loop (a native pacer thread: xrWaitFrame blocks).

/// Called on the pacer thread after each xrWaitFrame with the predicted
/// display time (ns), whether the runtime wants the frame rendered and the
/// frame index. Pass a NativeCallable.listener: Dart runs it on its isolate.
typedef void (*openxr_bridge_frame_callback)(int64_t predicted_display_time, int32_t should_render, int64_t frame);

/// Starts the pacer thread once the session has begun. Until a renderer is
/// attached every frame is ended empty with [blend_mode]
/// (XrEnvironmentBlendMode, 0 = opaque).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_frame_loop_start(openxr_bridge_frame_callback on_frame, int32_t blend_mode);
FFI_PLUGIN_EXPORT void openxr_bridge_frame_loop_stop(void);
FFI_PLUGIN_EXPORT bool openxr_bridge_frame_loop_running(void);
/// Frames waited, frames ended empty, frames the renderer missed, and the
/// runtime's predicted display period (ns).
FFI_PLUGIN_EXPORT void openxr_bridge_frame_loop_stats(int64_t* frames, int64_t* empty_frames,
        int64_t* missed_frames, int64_t* predicted_period);
FFI_PLUGIN_EXPORT int64_t openxr_bridge_last_predicted_display_time(void);

#ifdef __cplusplus
}
#endif

#endif // OPENXR_BRIDGE_C_H
