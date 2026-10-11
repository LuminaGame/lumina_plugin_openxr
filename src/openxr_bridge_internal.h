#ifndef OPENXR_BRIDGE_INTERNAL_H
#define OPENXR_BRIDGE_INTERNAL_H

// State shared by the bridge's translation units. Not part of the FFI surface.

#include <string>
#include <vector>

#define XR_USE_GRAPHICS_API_VULKAN 1
#if defined(__ANDROID__)
#define XR_USE_PLATFORM_ANDROID 1
#include <jni.h>
#endif
#include <vulkan/vulkan.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>

#include "openxr_bridge_c.h"

namespace openxr_bridge {

struct Space {
    int64_t id = 0;
    XrSpace handle = XR_NULL_HANDLE;
};

struct State {
    void* loader = nullptr;
    PFN_xrGetInstanceProcAddr getInstanceProcAddr = nullptr;
    XrInstance instance = XR_NULL_HANDLE;
    XrSystemId system = XR_NULL_SYSTEM_ID;
    XrSession session = XR_NULL_HANDLE;
    std::vector<std::string> enabledExtensions;
    std::string runtimeName;
    uint64_t runtimeVersion = 0;
    std::string systemName;
    std::vector<XrViewConfigurationView> views;
    std::vector<XrEnvironmentBlendMode> blendModes;
    std::string lastError;

    // Vulkan, from XR_KHR_vulkan_enable2.
    void* vulkanLoader = nullptr;
    PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr = nullptr;
    VkInstance vkInstance = VK_NULL_HANDLE;
    VkPhysicalDevice vkPhysicalDevice = VK_NULL_HANDLE;
    VkDevice vkDevice = VK_NULL_HANDLE;
    uint32_t queueFamily = 0;
    uint32_t runtimeQueueIndex = 0;
    uint32_t filamentQueueIndex = 0;

    std::vector<Space> spaces;
    int64_t nextSpaceId = 1;
};

State& state();

/// Records [message] (with the result's name) as the last error and returns [result].
XrResult fail(XrResult result, const std::string& message);

/// xrGetInstanceProcAddr for [name] on the current instance (or none).
PFN_xrVoidFunction proc(const char* name);

template <typename T>
T fn(const char* name) {
    return reinterpret_cast<T>(proc(name));
}

/// Opens [name] as a shared library; returns null on failure.
void* openLibrary(const char* name);
void* librarySymbol(void* library, const char* name);
void closeLibrary(void* library);

/// Android: the JavaVM and activity (a global reference) the Kotlin plugin handed over.
void* androidVm();
void* androidActivity();

/// Logs to logcat (tag LuminaOpenXR) on Android, stderr elsewhere.
void log(const char* format, ...);

}  // namespace openxr_bridge

#endif  // OPENXR_BRIDGE_INTERNAL_H
