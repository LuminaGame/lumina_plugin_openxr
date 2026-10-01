#ifndef OPENXR_BRIDGE_C_H
#define OPENXR_BRIDGE_C_H

#include <stdint.h>
#include <stdbool.h>

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Checks whether an OpenXR active runtime is registered and discoverable on this machine.
/// Returns 1 if available, 0 if no runtime was detected.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_is_runtime_available(void);

/// Returns the detected active OpenXR runtime JSON manifest path, or empty string.
FFI_PLUGIN_EXPORT const char* openxr_bridge_get_active_runtime_path(void);

/// Returns the human-readable runtime name (e.g. "Oculus / Meta Quest Link", "SteamVR", "Windows Mixed Reality", "None").
FFI_PLUGIN_EXPORT const char* openxr_bridge_get_active_runtime_name(void);

/// Attempts to load the active OpenXR loader library.
/// Returns 0 on success, or a negative error code on failure.
FFI_PLUGIN_EXPORT int32_t openxr_bridge_initialize(void);

/// Unloads the OpenXR loader library and frees resources.
FFI_PLUGIN_EXPORT void openxr_bridge_shutdown(void);

#ifdef __cplusplus
}
#endif

#endif // OPENXR_BRIDGE_C_H
