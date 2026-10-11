// Instance, system, the Vulkan device through XR_KHR_vulkan_enable2, the
// session, events and spaces.

#include "openxr_bridge_internal.h"

#include <algorithm>
#include <cstring>
#include <sstream>

using namespace openxr_bridge;

namespace {

bool hasExtension(const std::vector<XrExtensionProperties>& offered, const std::string& name) {
    return std::any_of(offered.begin(), offered.end(),
            [&](const XrExtensionProperties& p) { return name == p.extensionName; });
}

std::vector<std::string> split(const char* list) {
    std::vector<std::string> out;
    if (!list) return out;
    std::stringstream stream(list);
    std::string item;
    while (std::getline(stream, item, ',')) {
        item.erase(0, item.find_first_not_of(' '));
        item.erase(item.find_last_not_of(' ') + 1);
        if (!item.empty()) out.push_back(item);
    }
    return out;
}

Space* findSpace(int64_t id) {
    for (auto& s : state().spaces) {
        if (s.id == id) return &s;
    }
    return nullptr;
}

void copyPose(const XrPosef& pose, uint64_t flags, openxr_bridge_pose* out) {
    out->position[0] = pose.position.x;
    out->position[1] = pose.position.y;
    out->position[2] = pose.position.z;
    out->orientation[0] = pose.orientation.x;
    out->orientation[1] = pose.orientation.y;
    out->orientation[2] = pose.orientation.z;
    out->orientation[3] = pose.orientation.w;
    out->flags = flags;
}

PFN_vkVoidFunction vkProc(const char* name) {
    State& s = state();
    return s.vkGetInstanceProcAddr ? s.vkGetInstanceProcAddr(s.vkInstance, name) : nullptr;
}

}  // namespace

int32_t openxr_bridge_create_instance(const char* application_name, const char* optional_extensions) {
    State& s = state();
    if (!s.getInstanceProcAddr && openxr_bridge_initialize() != 0) {
        return fail(XR_ERROR_RUNTIME_UNAVAILABLE, "no OpenXR loader (" + s.lastError + ")");
    }
    if (s.instance != XR_NULL_HANDLE) return XR_SUCCESS;

    auto enumerateExtensions = fn<PFN_xrEnumerateInstanceExtensionProperties>("xrEnumerateInstanceExtensionProperties");
    auto createInstance = fn<PFN_xrCreateInstance>("xrCreateInstance");
    if (!enumerateExtensions || !createInstance) return fail(XR_ERROR_FUNCTION_UNSUPPORTED, "loader entry points");
    uint32_t count = 0;
    XrResult r = enumerateExtensions(nullptr, 0, &count, nullptr);
    if (XR_FAILED(r)) return fail(r, "xrEnumerateInstanceExtensionProperties");
    std::vector<XrExtensionProperties> offered(count, {XR_TYPE_EXTENSION_PROPERTIES});
    r = enumerateExtensions(nullptr, count, &count, offered.data());
    if (XR_FAILED(r)) return fail(r, "xrEnumerateInstanceExtensionProperties");

    std::vector<std::string> wanted = {XR_KHR_VULKAN_ENABLE2_EXTENSION_NAME};
#if defined(__ANDROID__)
    wanted.emplace_back(XR_KHR_ANDROID_CREATE_INSTANCE_EXTENSION_NAME);
#endif
    for (const auto& name : wanted) {
        if (!hasExtension(offered, name)) return fail(XR_ERROR_EXTENSION_NOT_PRESENT, "the runtime lacks " + name);
    }
    for (const auto& name : split(optional_extensions)) {
        if (hasExtension(offered, name) && std::find(wanted.begin(), wanted.end(), name) == wanted.end()) {
            wanted.push_back(name);
        }
    }
    std::vector<const char*> names;
    for (const auto& n : wanted) names.push_back(n.c_str());

    XrInstanceCreateInfo info{XR_TYPE_INSTANCE_CREATE_INFO};
    std::strncpy(info.applicationInfo.applicationName, application_name ? application_name : "Lumina",
            XR_MAX_APPLICATION_NAME_SIZE - 1);
    std::strncpy(info.applicationInfo.engineName, "Lumina", XR_MAX_ENGINE_NAME_SIZE - 1);
    info.applicationInfo.applicationVersion = 1;
    info.applicationInfo.engineVersion = 1;
    info.applicationInfo.apiVersion = XR_API_VERSION_1_0;
    info.enabledExtensionCount = static_cast<uint32_t>(names.size());
    info.enabledExtensionNames = names.data();
#if defined(__ANDROID__)
    XrInstanceCreateInfoAndroidKHR android{XR_TYPE_INSTANCE_CREATE_INFO_ANDROID_KHR};
    android.applicationVM = androidVm();
    android.applicationActivity = androidActivity();
    info.next = &android;
#endif
    r = createInstance(&info, &s.instance);
    if (XR_FAILED(r)) return fail(r, "xrCreateInstance");
    s.enabledExtensions = wanted;

    XrInstanceProperties props{XR_TYPE_INSTANCE_PROPERTIES};
    if (auto getProps = fn<PFN_xrGetInstanceProperties>("xrGetInstanceProperties")) {
        if (XR_SUCCEEDED(getProps(s.instance, &props))) {
            s.runtimeName = props.runtimeName;
            s.runtimeVersion = props.runtimeVersion;
        }
    }
    log("instance created on %s %u.%u.%u with %zu extensions", s.runtimeName.c_str(),
            XR_VERSION_MAJOR(s.runtimeVersion), XR_VERSION_MINOR(s.runtimeVersion),
            XR_VERSION_PATCH(s.runtimeVersion), s.enabledExtensions.size());
    for (const auto& e : s.enabledExtensions) log("  extension %s", e.c_str());
    return XR_SUCCESS;
}

bool openxr_bridge_extension_enabled(const char* name) {
    if (!name) return false;
    const auto& list = state().enabledExtensions;
    return std::find(list.begin(), list.end(), std::string(name)) != list.end();
}

const char* openxr_bridge_runtime_name(void) { return state().runtimeName.c_str(); }
uint64_t openxr_bridge_runtime_version(void) { return state().runtimeVersion; }

int32_t openxr_bridge_get_system(void) {
    State& s = state();
    if (s.instance == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no instance");
    XrSystemGetInfo info{XR_TYPE_SYSTEM_GET_INFO};
    info.formFactor = XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;
    XrResult r = fn<PFN_xrGetSystem>("xrGetSystem")(s.instance, &info, &s.system);
    if (XR_FAILED(r)) return fail(r, "xrGetSystem");

    XrSystemProperties props{XR_TYPE_SYSTEM_PROPERTIES};
    r = fn<PFN_xrGetSystemProperties>("xrGetSystemProperties")(s.instance, s.system, &props);
    if (XR_SUCCEEDED(r)) s.systemName = props.systemName;

    auto enumerateViews = fn<PFN_xrEnumerateViewConfigurationViews>("xrEnumerateViewConfigurationViews");
    uint32_t count = 0;
    r = enumerateViews(s.instance, s.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &count, nullptr);
    if (XR_FAILED(r)) return fail(r, "xrEnumerateViewConfigurationViews");
    s.views.assign(count, {XR_TYPE_VIEW_CONFIGURATION_VIEW});
    enumerateViews(s.instance, s.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, count, &count, s.views.data());

    auto enumerateBlend = fn<PFN_xrEnumerateEnvironmentBlendModes>("xrEnumerateEnvironmentBlendModes");
    count = 0;
    enumerateBlend(s.instance, s.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, 0, &count, nullptr);
    s.blendModes.assign(count, XR_ENVIRONMENT_BLEND_MODE_OPAQUE);
    enumerateBlend(s.instance, s.system, XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO, count, &count, s.blendModes.data());

    log("system %s: %zu views, recommended %ux%u, %zu blend modes", s.systemName.c_str(), s.views.size(),
            s.views.empty() ? 0 : s.views[0].recommendedImageRectWidth,
            s.views.empty() ? 0 : s.views[0].recommendedImageRectHeight, s.blendModes.size());
    for (auto mode : s.blendModes) log("  blend mode %d", static_cast<int>(mode));
    return XR_SUCCESS;
}

const char* openxr_bridge_system_name(void) { return state().systemName.c_str(); }

uint32_t openxr_bridge_view_count(void) { return static_cast<uint32_t>(state().views.size()); }

int32_t openxr_bridge_view_configuration(uint32_t index, uint32_t* recommended_width, uint32_t* recommended_height,
        uint32_t* max_width, uint32_t* max_height, uint32_t* recommended_samples) {
    const auto& views = state().views;
    if (index >= views.size()) return XR_ERROR_INDEX_OUT_OF_RANGE;
    const auto& v = views[index];
    if (recommended_width) *recommended_width = v.recommendedImageRectWidth;
    if (recommended_height) *recommended_height = v.recommendedImageRectHeight;
    if (max_width) *max_width = v.maxImageRectWidth;
    if (max_height) *max_height = v.maxImageRectHeight;
    if (recommended_samples) *recommended_samples = v.recommendedSwapchainSampleCount;
    return XR_SUCCESS;
}

uint32_t openxr_bridge_blend_modes(uint32_t* out, uint32_t capacity) {
    const auto& modes = state().blendModes;
    const uint32_t n = std::min<uint32_t>(capacity, static_cast<uint32_t>(modes.size()));
    for (uint32_t i = 0; i < n && out; ++i) out[i] = static_cast<uint32_t>(modes[i]);
    return static_cast<uint32_t>(modes.size());
}

int32_t openxr_bridge_create_vulkan_device(bool multiview, openxr_bridge_device_info_create_fn info_create,
        openxr_bridge_device_info_get_fn info_create_info, openxr_bridge_device_info_u32_fn info_queue_family,
        openxr_bridge_device_info_u32_fn info_filament_queue, openxr_bridge_device_info_bool_fn info_multiview,
        openxr_bridge_device_info_destroy_fn info_destroy, openxr_bridge_vulkan* out) {
    State& s = state();
    if (s.system == XR_NULL_SYSTEM_ID) return fail(XR_ERROR_SYSTEM_INVALID, "no system");
    if (!info_create || !info_create_info || !info_queue_family || !info_filament_queue || !info_multiview ||
            !info_destroy || !out) {
        return fail(XR_ERROR_VALIDATION_FAILURE, "missing device-info entry points");
    }
    if (!s.vulkanLoader) {
#if defined(_WIN32)
        s.vulkanLoader = openLibrary("vulkan-1.dll");
#else
        s.vulkanLoader = openLibrary("libvulkan.so");
        if (!s.vulkanLoader) s.vulkanLoader = openLibrary("libvulkan.so.1");
#endif
        s.vkGetInstanceProcAddr =
                reinterpret_cast<PFN_vkGetInstanceProcAddr>(librarySymbol(s.vulkanLoader, "vkGetInstanceProcAddr"));
    }
    if (!s.vkGetInstanceProcAddr) return fail(XR_ERROR_RUNTIME_FAILURE, "no Vulkan loader");

    XrGraphicsRequirementsVulkan2KHR requirements{XR_TYPE_GRAPHICS_REQUIREMENTS_VULKAN2_KHR};
    XrResult r = fn<PFN_xrGetVulkanGraphicsRequirements2KHR>("xrGetVulkanGraphicsRequirements2KHR")(
            s.instance, s.system, &requirements);
    if (XR_FAILED(r)) return fail(r, "xrGetVulkanGraphicsRequirements2KHR");
    // Vulkan 1.2 at least (Filament chains VkPhysicalDeviceVulkan11Features), within the runtime's range.
    uint32_t apiVersion = VK_API_VERSION_1_2;
    const uint32_t maxVk = VK_MAKE_API_VERSION(0, XR_VERSION_MAJOR(requirements.maxApiVersionSupported),
            XR_VERSION_MINOR(requirements.maxApiVersionSupported), 0);
    if (apiVersion > maxVk) apiVersion = maxVk;

    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Lumina";
    app.pEngineName = "Filament";
    app.apiVersion = apiVersion;
    VkInstanceCreateInfo vkInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    vkInfo.pApplicationInfo = &app;
    XrVulkanInstanceCreateInfoKHR xrVkInfo{XR_TYPE_VULKAN_INSTANCE_CREATE_INFO_KHR};
    xrVkInfo.systemId = s.system;
    xrVkInfo.pfnGetInstanceProcAddr = s.vkGetInstanceProcAddr;
    xrVkInfo.vulkanCreateInfo = &vkInfo;
    VkResult vr = VK_SUCCESS;
    r = fn<PFN_xrCreateVulkanInstanceKHR>("xrCreateVulkanInstanceKHR")(s.instance, &xrVkInfo, &s.vkInstance, &vr);
    if (XR_FAILED(r) || vr != VK_SUCCESS) return fail(XR_FAILED(r) ? r : XR_ERROR_RUNTIME_FAILURE, "xrCreateVulkanInstanceKHR");

    XrVulkanGraphicsDeviceGetInfoKHR deviceGet{XR_TYPE_VULKAN_GRAPHICS_DEVICE_GET_INFO_KHR};
    deviceGet.systemId = s.system;
    deviceGet.vulkanInstance = s.vkInstance;
    r = fn<PFN_xrGetVulkanGraphicsDevice2KHR>("xrGetVulkanGraphicsDevice2KHR")(s.instance, &deviceGet,
            &s.vkPhysicalDevice);
    if (XR_FAILED(r)) return fail(r, "xrGetVulkanGraphicsDevice2KHR");

    void* info = info_create(s.vkInstance, s.vkPhysicalDevice, multiview, nullptr, 0);
    if (!info) return fail(XR_ERROR_RUNTIME_FAILURE, "the device has no graphics queue");
    auto* createInfo = static_cast<const VkDeviceCreateInfo*>(info_create_info(info));
    XrVulkanDeviceCreateInfoKHR xrDevice{XR_TYPE_VULKAN_DEVICE_CREATE_INFO_KHR};
    xrDevice.systemId = s.system;
    xrDevice.pfnGetInstanceProcAddr = s.vkGetInstanceProcAddr;
    xrDevice.vulkanPhysicalDevice = s.vkPhysicalDevice;
    xrDevice.vulkanCreateInfo = createInfo;
    r = fn<PFN_xrCreateVulkanDeviceKHR>("xrCreateVulkanDeviceKHR")(s.instance, &xrDevice, &s.vkDevice, &vr);
    s.queueFamily = info_queue_family(info);
    s.filamentQueueIndex = info_filament_queue(info);
    s.runtimeQueueIndex = 0;
    const bool deviceMultiview = info_multiview(info);
    info_destroy(info);
    if (XR_FAILED(r) || vr != VK_SUCCESS) return fail(XR_FAILED(r) ? r : XR_ERROR_RUNTIME_FAILURE, "xrCreateVulkanDeviceKHR");

    VkPhysicalDeviceProperties props{};
    if (auto getProps = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(vkProc("vkGetPhysicalDeviceProperties"))) {
        getProps(s.vkPhysicalDevice, &props);
    }
    log("Vulkan device %s (api %u.%u), queue family %u: runtime queue %u, Filament queue %u, multiview %d",
            props.deviceName, VK_API_VERSION_MAJOR(props.apiVersion), VK_API_VERSION_MINOR(props.apiVersion),
            s.queueFamily, s.runtimeQueueIndex, s.filamentQueueIndex, deviceMultiview ? 1 : 0);

    out->instance = s.vkInstance;
    out->physical_device = s.vkPhysicalDevice;
    out->device = s.vkDevice;
    out->queue_family = s.queueFamily;
    out->filament_queue_index = s.filamentQueueIndex;
    out->runtime_queue_index = s.runtimeQueueIndex;
    out->multiview = deviceMultiview;
    return XR_SUCCESS;
}

int32_t openxr_bridge_create_session(void) {
    State& s = state();
    if (s.session != XR_NULL_HANDLE) return XR_SUCCESS;
    if (s.vkDevice == VK_NULL_HANDLE) return fail(XR_ERROR_GRAPHICS_DEVICE_INVALID, "no Vulkan device");
    XrGraphicsBindingVulkan2KHR binding{XR_TYPE_GRAPHICS_BINDING_VULKAN2_KHR};
    binding.instance = s.vkInstance;
    binding.physicalDevice = s.vkPhysicalDevice;
    binding.device = s.vkDevice;
    binding.queueFamilyIndex = s.queueFamily;
    binding.queueIndex = s.runtimeQueueIndex;
    XrSessionCreateInfo info{XR_TYPE_SESSION_CREATE_INFO};
    info.next = &binding;
    info.systemId = s.system;
    XrResult r = fn<PFN_xrCreateSession>("xrCreateSession")(s.instance, &info, &s.session);
    if (XR_FAILED(r)) return fail(r, "xrCreateSession");
    log("session created");
    return XR_SUCCESS;
}

int32_t openxr_bridge_poll_event(openxr_bridge_event* out) {
    State& s = state();
    if (s.instance == XR_NULL_HANDLE || !out) return XR_ERROR_HANDLE_INVALID;
    XrEventDataBuffer buffer{XR_TYPE_EVENT_DATA_BUFFER};
    XrResult r = fn<PFN_xrPollEvent>("xrPollEvent")(s.instance, &buffer);
    if (r == XR_EVENT_UNAVAILABLE) return 0;
    if (XR_FAILED(r)) return fail(r, "xrPollEvent");
    *out = openxr_bridge_event{};
    switch (buffer.type) {
        case XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED: {
            auto* e = reinterpret_cast<XrEventDataSessionStateChanged*>(&buffer);
            out->kind = 1;
            out->state = e->state;
            out->time = e->time;
            log("XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED state %d", static_cast<int>(e->state));
            break;
        }
        case XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING: {
            auto* e = reinterpret_cast<XrEventDataInstanceLossPending*>(&buffer);
            out->kind = 2;
            out->time = e->lossTime;
            log("XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING");
            break;
        }
        case XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING: {
            auto* e = reinterpret_cast<XrEventDataReferenceSpaceChangePending*>(&buffer);
            out->kind = 3;
            out->time = e->changeTime;
            out->space_type = e->referenceSpaceType;
            log("XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING space %d", static_cast<int>(e->referenceSpaceType));
            break;
        }
        case XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED:
            out->kind = 4;
            log("XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED");
            break;
        case XR_TYPE_EVENT_DATA_EVENTS_LOST:
            out->kind = 5;
            log("XR_TYPE_EVENT_DATA_EVENTS_LOST");
            break;
        case XR_TYPE_EVENT_DATA_DISPLAY_REFRESH_RATE_CHANGED_FB: {
            auto* e = reinterpret_cast<XrEventDataDisplayRefreshRateChangedFB*>(&buffer);
            out->kind = 6;
            out->value = e->toDisplayRefreshRate;
            log("XR_TYPE_EVENT_DATA_DISPLAY_REFRESH_RATE_CHANGED_FB %.1f Hz", e->toDisplayRefreshRate);
            break;
        }
        default: {
            out->kind = 0;
            uint64_t payload = 0;
            memcpy(&payload, buffer.varying, sizeof(payload));
            out->payload = payload;
            break;
        }
    }
    out->structure_type = static_cast<int32_t>(buffer.type);
    return 1;
}

int32_t openxr_bridge_begin_session(void) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    XrSessionBeginInfo info{XR_TYPE_SESSION_BEGIN_INFO};
    info.primaryViewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    XrResult r = fn<PFN_xrBeginSession>("xrBeginSession")(s.session, &info);
    if (XR_FAILED(r)) return fail(r, "xrBeginSession");
    log("session begun");
    return r;
}

int32_t openxr_bridge_end_session(void) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    XrResult r = fn<PFN_xrEndSession>("xrEndSession")(s.session);
    if (XR_FAILED(r)) return fail(r, "xrEndSession");
    log("session ended");
    return r;
}

int32_t openxr_bridge_request_exit_session(void) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    XrResult r = fn<PFN_xrRequestExitSession>("xrRequestExitSession")(s.session);
    return XR_FAILED(r) ? fail(r, "xrRequestExitSession") : r;
}

int32_t openxr_bridge_destroy_session(void) {
    openxr_bridge_frame_loop_stop();
    openxr_bridge_destroy_swapchain();
    State& s = state();
    for (auto& space : s.spaces) {
        if (space.handle != XR_NULL_HANDLE) fn<PFN_xrDestroySpace>("xrDestroySpace")(space.handle);
    }
    s.spaces.clear();
    s.actionSetsAttached = false;
    if (s.session == XR_NULL_HANDLE) return XR_SUCCESS;
    XrResult r = fn<PFN_xrDestroySession>("xrDestroySession")(s.session);
    s.session = XR_NULL_HANDLE;
    return r;
}

int32_t openxr_bridge_destroy_instance(void) {
    State& s = state();
    // The device and Vulkan instance the runtime created belong to the app; the engine that used
    // them is gone by now.
    if (s.vkDevice != VK_NULL_HANDLE) {
        if (auto destroy = reinterpret_cast<PFN_vkDestroyDevice>(vkProc("vkDestroyDevice"))) destroy(s.vkDevice, nullptr);
        s.vkDevice = VK_NULL_HANDLE;
    }
    if (s.vkInstance != VK_NULL_HANDLE) {
        if (auto destroy = reinterpret_cast<PFN_vkDestroyInstance>(vkProc("vkDestroyInstance"))) destroy(s.vkInstance, nullptr);
        s.vkInstance = VK_NULL_HANDLE;
    }
    s.vkPhysicalDevice = VK_NULL_HANDLE;
    if (s.instance == XR_NULL_HANDLE) return XR_SUCCESS;
    XrResult r = fn<PFN_xrDestroyInstance>("xrDestroyInstance")(s.instance);
    s.instance = XR_NULL_HANDLE;
    s.system = XR_NULL_SYSTEM_ID;
    s.enabledExtensions.clear();
    // xrDestroyInstance destroyed the action sets and actions with it.
    s.actionSets.clear();
    s.actions.clear();
    s.handPaths[0] = s.handPaths[1] = XR_NULL_PATH;
    return r;
}

uint32_t openxr_bridge_display_refresh_rates(float* out, uint32_t capacity) {
    State& s = state();
    auto enumerate = fn<PFN_xrEnumerateDisplayRefreshRatesFB>("xrEnumerateDisplayRefreshRatesFB");
    if (s.session == XR_NULL_HANDLE || !enumerate) return 0;
    uint32_t count = 0;
    if (XR_FAILED(enumerate(s.session, 0, &count, nullptr))) return 0;
    std::vector<float> rates(count);
    enumerate(s.session, count, &count, rates.data());
    for (uint32_t i = 0; i < count && i < capacity && out; ++i) out[i] = rates[i];
    return count;
}

float openxr_bridge_display_refresh_rate(void) {
    State& s = state();
    auto get = fn<PFN_xrGetDisplayRefreshRateFB>("xrGetDisplayRefreshRateFB");
    float hz = 0;
    if (s.session != XR_NULL_HANDLE && get) get(s.session, &hz);
    return hz;
}

int32_t openxr_bridge_request_display_refresh_rate(float hz) {
    State& s = state();
    auto request = fn<PFN_xrRequestDisplayRefreshRateFB>("xrRequestDisplayRefreshRateFB");
    if (s.session == XR_NULL_HANDLE || !request) return fail(XR_ERROR_EXTENSION_NOT_PRESENT, "XR_FB_display_refresh_rate");
    XrResult r = request(s.session, hz);
    if (XR_FAILED(r)) return fail(r, "xrRequestDisplayRefreshRateFB");
    log("display refresh rate %.0f Hz requested", hz);
    return r;
}

int64_t openxr_bridge_create_reference_space(int32_t type) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    XrReferenceSpaceCreateInfo info{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};
    info.referenceSpaceType = static_cast<XrReferenceSpaceType>(type);
    info.poseInReferenceSpace.orientation.w = 1.0f;
    XrSpace handle = XR_NULL_HANDLE;
    XrResult r = fn<PFN_xrCreateReferenceSpace>("xrCreateReferenceSpace")(s.session, &info, &handle);
    if (XR_FAILED(r)) return fail(r, "xrCreateReferenceSpace");
    Space space;
    space.id = s.nextSpaceId++;
    space.handle = handle;
    s.spaces.push_back(space);
    return space.id;
}

void openxr_bridge_destroy_space(int64_t id) {
    auto& spaces = state().spaces;
    for (auto it = spaces.begin(); it != spaces.end(); ++it) {
        if (it->id != id) continue;
        if (it->handle != XR_NULL_HANDLE) fn<PFN_xrDestroySpace>("xrDestroySpace")(it->handle);
        spaces.erase(it);
        return;
    }
}

int32_t openxr_bridge_locate_space(int64_t space, int64_t base, int64_t time, openxr_bridge_pose* out) {
    Space* s = findSpace(space);
    Space* b = findSpace(base);
    if (!s || !b || !out) return XR_ERROR_HANDLE_INVALID;
    XrSpaceLocation location{XR_TYPE_SPACE_LOCATION};
    XrResult r = fn<PFN_xrLocateSpace>("xrLocateSpace")(s->handle, b->handle, time, &location);
    if (XR_FAILED(r)) return fail(r, "xrLocateSpace");
    copyPose(location.pose, location.locationFlags, out);
    return r;
}

int32_t openxr_bridge_locate_views(int64_t base, int64_t time, openxr_bridge_view* out, uint32_t capacity,
        uint32_t* count, uint64_t* view_state_flags) {
    State& st = state();
    Space* b = findSpace(base);
    if (!b || st.session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrViewLocateInfo info{XR_TYPE_VIEW_LOCATE_INFO};
    info.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
    info.displayTime = time;
    info.space = b->handle;
    XrViewState viewState{XR_TYPE_VIEW_STATE};
    XrView views[4];
    for (auto& v : views) v = {XR_TYPE_VIEW};
    uint32_t n = 0;
    XrResult r = fn<PFN_xrLocateViews>("xrLocateViews")(st.session, &info, &viewState, 4, &n, views);
    if (XR_FAILED(r)) return fail(r, "xrLocateViews");
    if (count) *count = n;
    if (view_state_flags) *view_state_flags = viewState.viewStateFlags;
    for (uint32_t i = 0; i < n && i < capacity && out; ++i) {
        copyPose(views[i].pose, viewState.viewStateFlags, &out[i].pose);
        out[i].angle_left = views[i].fov.angleLeft;
        out[i].angle_right = views[i].fov.angleRight;
        out[i].angle_up = views[i].fov.angleUp;
        out[i].angle_down = views[i].fov.angleDown;
    }
    return r;
}
