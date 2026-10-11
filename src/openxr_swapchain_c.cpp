// The compositor's swapchain as a Filament swapchain provider, and the frame
// hand-over: the pacer thread (openxr_frame_c.cpp) waits for a frame and
// locates the views; the renderer (Filament's driver thread) begins the frame
// when it acquires the image and ends it with a projection layer when it
// releases the image.

#include "openxr_bridge_internal.h"
#include "openxr_frame_internal.h"

#include <algorithm>
#include <cstring>

using namespace openxr_bridge;

namespace {

/// The renderer's view of the compositor swapchain (a copy of
/// filament_external_swapchain_provider's layout, src/external_vulkan_c.h).
struct Provider {
    void* user_data;
    uint32_t image_count;
    uint32_t width;
    uint32_t height;
    uint32_t color_format;
    uint32_t layer_count;
    uint32_t depth_format;
    void (*get_images)(void* user_data, uint64_t* colors, uint64_t* depth);
    int32_t (*acquire)(void* user_data, uint32_t* index);
    int32_t (*present)(void* user_data, uint32_t index);
    void (*destroy)(void* user_data);
};

struct Swapchain {
    XrSwapchain handle = XR_NULL_HANDLE;
    int64_t format = 0;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t layers = 1;
    std::vector<XrSwapchainImageVulkanKHR> images;
    // The depth image the bridge makes for Filament (one, reused by every colour image).
    VkImage depth = VK_NULL_HANDLE;
    VkDeviceMemory depthMemory = VK_NULL_HANDLE;
    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    Provider provider{};
};

Swapchain g_swapchain;

PFN_vkVoidFunction vkProc(const char* name) {
    State& s = state();
    return s.vkGetInstanceProcAddr ? s.vkGetInstanceProcAddr(s.vkInstance, name) : nullptr;
}

template <typename T>
T vk(const char* name) {
    return reinterpret_cast<T>(vkProc(name));
}

bool makeDepth(Swapchain& sc) {
    State& s = state();
    auto formatProps = vk<PFN_vkGetPhysicalDeviceFormatProperties>("vkGetPhysicalDeviceFormatProperties");
    for (VkFormat f : {VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT, VK_FORMAT_D16_UNORM}) {
        VkFormatProperties props{};
        formatProps(s.vkPhysicalDevice, f, &props);
        if (props.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            sc.depthFormat = f;
            break;
        }
    }
    if (sc.depthFormat == VK_FORMAT_UNDEFINED) return false;
    VkImageCreateInfo ci{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ci.imageType = VK_IMAGE_TYPE_2D;
    ci.format = sc.depthFormat;
    ci.extent = {sc.width, sc.height, 1};
    ci.mipLevels = 1;
    ci.arrayLayers = sc.layers;
    ci.samples = VK_SAMPLE_COUNT_1_BIT;
    ci.tiling = VK_IMAGE_TILING_OPTIMAL;
    ci.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    ci.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    if (vk<PFN_vkCreateImage>("vkCreateImage")(s.vkDevice, &ci, nullptr, &sc.depth) != VK_SUCCESS) return false;
    VkMemoryRequirements req{};
    vk<PFN_vkGetImageMemoryRequirements>("vkGetImageMemoryRequirements")(s.vkDevice, sc.depth, &req);
    VkPhysicalDeviceMemoryProperties mem{};
    vk<PFN_vkGetPhysicalDeviceMemoryProperties>("vkGetPhysicalDeviceMemoryProperties")(s.vkPhysicalDevice, &mem);
    uint32_t type = UINT32_MAX;
    for (uint32_t i = 0; i < mem.memoryTypeCount; ++i) {
        if ((req.memoryTypeBits & (1u << i)) &&
                (mem.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
            type = i;
            break;
        }
    }
    VkMemoryAllocateInfo ai{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    ai.allocationSize = req.size;
    ai.memoryTypeIndex = type;
    if (type == UINT32_MAX ||
            vk<PFN_vkAllocateMemory>("vkAllocateMemory")(s.vkDevice, &ai, nullptr, &sc.depthMemory) != VK_SUCCESS) {
        return false;
    }
    return vk<PFN_vkBindImageMemory>("vkBindImageMemory")(s.vkDevice, sc.depth, sc.depthMemory, 0) == VK_SUCCESS;
}

void getImages(void*, uint64_t* colors, uint64_t* depth) {
    for (size_t i = 0; i < g_swapchain.images.size(); ++i) {
        colors[i] = reinterpret_cast<uint64_t>(g_swapchain.images[i].image);
    }
    *depth = reinterpret_cast<uint64_t>(g_swapchain.depth);
}

/// Driver thread, when Filament begins a frame: xrBeginFrame for the frame the
/// pacer handed out, then the next compositor image.
int32_t acquire(void*, uint32_t* index) {
    State& s = state();
    FrameLoop& loop = frameLoop();
    if (!loop.frameBegun.exchange(true)) {
        XrFrameBeginInfo begin{XR_TYPE_FRAME_BEGIN_INFO};
        XrResult r = fn<PFN_xrBeginFrame>("xrBeginFrame")(s.session, &begin);
        if (XR_FAILED(r)) fail(r, "xrBeginFrame");
    }
    XrSwapchainImageAcquireInfo acquireInfo{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};
    XrResult r = fn<PFN_xrAcquireSwapchainImage>("xrAcquireSwapchainImage")(g_swapchain.handle, &acquireInfo, index);
    if (XR_FAILED(r)) {
        fail(r, "xrAcquireSwapchainImage");
        return VK_ERROR_OUT_OF_DATE_KHR;
    }
    XrSwapchainImageWaitInfo waitInfo{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};
    waitInfo.timeout = XR_INFINITE_DURATION;
    r = fn<PFN_xrWaitSwapchainImage>("xrWaitSwapchainImage")(g_swapchain.handle, &waitInfo);
    if (XR_FAILED(r)) fail(r, "xrWaitSwapchainImage");
    return VK_SUCCESS;
}

/// Driver thread, after the frame's commands are submitted: hand the image back
/// and end the frame with a projection layer of the views the pacer located.
int32_t present(void*, uint32_t) {
    State& s = state();
    FrameLoop& loop = frameLoop();
    XrSwapchainImageReleaseInfo releaseInfo{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};
    XrResult r = fn<PFN_xrReleaseSwapchainImage>("xrReleaseSwapchainImage")(g_swapchain.handle, &releaseInfo);
    if (XR_FAILED(r)) fail(r, "xrReleaseSwapchainImage");

    XrTime displayTime;
    XrCompositionLayerProjectionView views[2];
    uint32_t viewCount;
    bool viewsValid;
    {
        std::lock_guard<std::mutex> lock(loop.mutex);
        displayTime = loop.pendingDisplayTime;
        viewCount = std::min<uint32_t>(loop.viewCount, 2);
        viewsValid = loop.viewsValid;
        for (uint32_t i = 0; i < viewCount; ++i) {
            views[i] = {XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};
            views[i].pose = loop.views[i].pose;
            views[i].fov = loop.views[i].fov;
            views[i].subImage.swapchain = g_swapchain.handle;
            views[i].subImage.imageRect.offset = {0, 0};
            views[i].subImage.imageRect.extent = {static_cast<int32_t>(g_swapchain.width),
                    static_cast<int32_t>(g_swapchain.height)};
            views[i].subImage.imageArrayIndex = g_swapchain.layers > 1 ? i : 0;
        }
    }
    XrCompositionLayerProjection layer{XR_TYPE_COMPOSITION_LAYER_PROJECTION};
    layer.space = loop.space;
    layer.viewCount = viewCount;
    layer.views = views;
    const bool project = viewsValid && viewCount == 2 && loop.space != XR_NULL_HANDLE;
    r = endFrameWithLayers(displayTime, project ? &layer : nullptr);
    if (XR_FAILED(r)) fail(r, "xrEndFrame");
    loop.frameBegun.store(false);
    {
        std::lock_guard<std::mutex> lock(loop.mutex);
        loop.frameEnded = true;
        ++loop.renderedFrames;
    }
    loop.ended.notify_all();
    return VK_SUCCESS;
}

}  // namespace

int64_t openxr_bridge_swapchain_formats(int64_t* out, uint32_t capacity) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    uint32_t count = 0;
    auto enumerate = fn<PFN_xrEnumerateSwapchainFormats>("xrEnumerateSwapchainFormats");
    XrResult r = enumerate(s.session, 0, &count, nullptr);
    if (XR_FAILED(r)) return fail(r, "xrEnumerateSwapchainFormats");
    std::vector<int64_t> formats(count);
    enumerate(s.session, count, &count, formats.data());
    for (uint32_t i = 0; i < count && i < capacity && out; ++i) out[i] = formats[i];
    return count;
}

int32_t openxr_bridge_create_swapchain(uint32_t width, uint32_t height, uint32_t array_size, int64_t format) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    if (g_swapchain.handle != XR_NULL_HANDLE) openxr_bridge_destroy_swapchain();
    XrSwapchainCreateInfo info{XR_TYPE_SWAPCHAIN_CREATE_INFO};
    info.usageFlags = XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT | XR_SWAPCHAIN_USAGE_SAMPLED_BIT;
    info.format = format;
    info.sampleCount = 1;
    info.width = width;
    info.height = height;
    info.faceCount = 1;
    info.arraySize = array_size == 0 ? 1 : array_size;
    info.mipCount = 1;
    XrResult r = fn<PFN_xrCreateSwapchain>("xrCreateSwapchain")(s.session, &info, &g_swapchain.handle);
    if (XR_FAILED(r)) return fail(r, "xrCreateSwapchain");
    uint32_t count = 0;
    auto enumerate = fn<PFN_xrEnumerateSwapchainImages>("xrEnumerateSwapchainImages");
    enumerate(g_swapchain.handle, 0, &count, nullptr);
    g_swapchain.images.assign(count, {XR_TYPE_SWAPCHAIN_IMAGE_VULKAN_KHR});
    r = enumerate(g_swapchain.handle, count, &count,
            reinterpret_cast<XrSwapchainImageBaseHeader*>(g_swapchain.images.data()));
    if (XR_FAILED(r)) return fail(r, "xrEnumerateSwapchainImages");
    g_swapchain.format = format;
    g_swapchain.width = width;
    g_swapchain.height = height;
    g_swapchain.layers = info.arraySize;
    if (!makeDepth(g_swapchain)) return fail(XR_ERROR_RUNTIME_FAILURE, "no depth image for the swapchain");

    Provider& p = g_swapchain.provider;
    p = Provider{};
    p.user_data = &g_swapchain;
    p.image_count = count;
    p.width = width;
    p.height = height;
    p.color_format = static_cast<uint32_t>(format);
    p.layer_count = g_swapchain.layers;
    p.depth_format = static_cast<uint32_t>(g_swapchain.depthFormat);
    p.get_images = getImages;
    p.acquire = acquire;
    p.present = present;
    p.destroy = nullptr;
    log("swapchain %ux%u x%u layers, format %lld, %u images, depth format %d", width, height, g_swapchain.layers,
            static_cast<long long>(format), count, static_cast<int>(g_swapchain.depthFormat));
    return XR_SUCCESS;
}

const void* openxr_bridge_swapchain_provider(void) {
    return g_swapchain.handle == XR_NULL_HANDLE ? nullptr : &g_swapchain.provider;
}

void openxr_bridge_destroy_swapchain(void) {
    State& s = state();
    if (g_swapchain.depth) vk<PFN_vkDestroyImage>("vkDestroyImage")(s.vkDevice, g_swapchain.depth, nullptr);
    if (g_swapchain.depthMemory) vk<PFN_vkFreeMemory>("vkFreeMemory")(s.vkDevice, g_swapchain.depthMemory, nullptr);
    if (g_swapchain.handle != XR_NULL_HANDLE) fn<PFN_xrDestroySwapchain>("xrDestroySwapchain")(g_swapchain.handle);
    g_swapchain = Swapchain{};
}
