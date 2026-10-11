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

/// XR_FB_display_refresh_rate: the rates the display offers (Hz), the current
/// one, and a request for [hz]. 0 / an error when the extension is missing.
FFI_PLUGIN_EXPORT uint32_t openxr_bridge_display_refresh_rates(float* out, uint32_t capacity);
FFI_PLUGIN_EXPORT float openxr_bridge_display_refresh_rate(void);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_request_display_refresh_rate(float hz);

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

// ---------------------------------------------------------------------------
// The swapchain and the renderer's frames.

/// The swapchain formats the runtime offers (VkFormat values), preferred first;
/// returns how many there are.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_swapchain_formats(int64_t* out, uint32_t capacity);
/// The compositor swapchain the renderer draws into: [array_size] 2 for
/// multiview (layer i = eye i), plus a depth image the bridge makes.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_create_swapchain(uint32_t width, uint32_t height, uint32_t array_size,
        int64_t format);
/// A filament_external_swapchain_provider for the swapchain (flutter_filament's
/// src/external_vulkan_c.h), owned by the bridge: acquire begins the frame and
/// takes the next image, present releases it and ends the frame with a
/// projection layer. Null without a swapchain.
FFI_PLUGIN_EXPORT const void* openxr_bridge_swapchain_provider(void);
FFI_PLUGIN_EXPORT void openxr_bridge_destroy_swapchain(void);

/// From now on frames the runtime wants rendered go to the renderer: the pacer
/// locates the views in [space] (a reference space id) and waits until the
/// renderer's present ended the frame. False goes back to empty frames.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_frame_loop_set_renderer(bool render, int64_t space);
/// The views of [frame] (the index the frame callback got), as the pacer located
/// them for its predicted display time; 0 when that frame is gone or the views
/// are not tracked.
FFI_PLUGIN_EXPORT uint32_t openxr_bridge_frame_views(int64_t frame, openxr_bridge_view* out, uint32_t capacity);
/// The renderer will not render [frame] (Filament skipped it): end it empty.
FFI_PLUGIN_EXPORT void openxr_bridge_skip_frame(int64_t frame);
/// Frames the renderer ended with a projection layer.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_rendered_frames(void);

// ---------------------------------------------------------------------------
// Input: action sets, actions, bindings, states, action spaces, haptics.
//
// Hands: 0 left (/user/hand/left), 1 right (/user/hand/right), -1 none.
// Action types are XrActionType values: 1 boolean, 2 float, 3 vector2f,
// 4 pose, 100 vibration output.

/// xrCreateActionSet. Returns an action set id (> 0) or a negative XrResult.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_create_action_set(const char* name, const char* localized_name, uint32_t priority);
/// xrCreateAction in [action_set]; [per_hand] gives it both hands as subaction
/// paths. Returns an action id (> 0) or a negative XrResult.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_create_action(int64_t action_set, const char* name, const char* localized_name,
        int32_t type, bool per_hand);
/// xrSuggestInteractionProfileBindings for [profile]
/// ("/interaction_profiles/oculus/touch_controller"): binding i binds
/// actions[i] to paths[i] ("/user/hand/left/input/squeeze/value").
FFI_PLUGIN_EXPORT int32_t openxr_bridge_suggest_bindings(const char* profile, const int64_t* actions,
        const char* const* paths, uint32_t count);
/// xrAttachSessionActionSets with every action set created so far (once per session).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_attach_action_sets(void);
/// Whether the action sets are attached to the current session.
FFI_PLUGIN_EXPORT bool openxr_bridge_action_sets_attached(void);
/// xrSyncActions for every attached action set.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_sync_actions(void);

/// The current state of [action] for [hand]: value, whether it is active
/// (bound and its device present).
FFI_PLUGIN_EXPORT int32_t openxr_bridge_action_state_boolean(int64_t action, int32_t hand, bool* value, bool* active);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_action_state_float(int64_t action, int32_t hand, float* value, bool* active);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_action_state_vector2f(int64_t action, int32_t hand, float* x, float* y,
        bool* active);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_action_state_pose(int64_t action, int32_t hand, bool* active);

/// xrCreateActionSpace for pose [action] and [hand] (identity pose in action
/// space). Returns a space id for openxr_bridge_locate_space, or a negative XrResult.
FFI_PLUGIN_EXPORT int64_t openxr_bridge_create_action_space(int64_t action, int32_t hand);

/// xrApplyHapticFeedback on vibration [action] for [hand]: [duration_ns]
/// (-1 XR_MIN_HAPTIC_DURATION), [frequency] Hz (0 XR_FREQUENCY_UNSPECIFIED),
/// [amplitude] 0..1.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_apply_haptic(int64_t action, int32_t hand, int64_t duration_ns, float frequency,
        float amplitude);
FFI_PLUGIN_EXPORT int32_t openxr_bridge_stop_haptic(int64_t action, int32_t hand);

/// xrGetCurrentInteractionProfile for [hand]: writes the profile path
/// ("" when none is active) into [out]; returns the XrResult.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_current_interaction_profile(int32_t hand, char* out, uint32_t capacity);

#ifdef __cplusplus
}
#endif

#endif // OPENXR_BRIDGE_C_H
