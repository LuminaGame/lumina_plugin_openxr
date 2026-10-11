// The frame loop: xrWaitFrame blocks, so it runs on a native pacer thread of
// its own, never on a Dart isolate. Each frame the thread waits, then either
// ends an empty frame itself (no renderer attached) or hands the frame to the
// renderer (task 08) and waits until the renderer has ended it.

#include "openxr_bridge_internal.h"
#include "openxr_frame_internal.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>

using namespace openxr_bridge;

namespace openxr_bridge {

FrameLoop& frameLoop() {
    static FrameLoop loop;
    return loop;
}

XrResult endFrameWithLayers(XrTime displayTime, XrCompositionLayerProjection* projection) {
    State& s = state();
    FrameLoop& loop = frameLoop();
    std::vector<const XrCompositionLayerBaseHeader*> layers;
    {
        std::lock_guard<std::mutex> lock(loop.layersMutex);
        layers.insert(layers.end(), loop.layersBefore.begin(), loop.layersBefore.end());
        if (projection) {
            projection->layerFlags |= loop.projectionFlags;
            layers.push_back(reinterpret_cast<const XrCompositionLayerBaseHeader*>(projection));
        }
        layers.insert(layers.end(), loop.layersAfter.begin(), loop.layersAfter.end());
    }
    XrFrameEndInfo end{XR_TYPE_FRAME_END_INFO};
    end.displayTime = displayTime;
    end.environmentBlendMode = loop.blendMode.load();
    end.layerCount = static_cast<uint32_t>(layers.size());
    end.layers = layers.empty() ? nullptr : layers.data();
    return fn<PFN_xrEndFrame>("xrEndFrame")(s.session, &end);
}

}  // namespace openxr_bridge

namespace {

void endEmptyFrame(XrTime displayTime) { endFrameWithLayers(displayTime, nullptr); }

void run() {
    State& s = state();
    FrameLoop& loop = frameLoop();
    auto waitFrame = fn<PFN_xrWaitFrame>("xrWaitFrame");
    auto beginFrame = fn<PFN_xrBeginFrame>("xrBeginFrame");
    auto locateViews = fn<PFN_xrLocateViews>("xrLocateViews");
    log("frame loop started");
    while (!loop.stop.load()) {
        XrFrameState frameState{XR_TYPE_FRAME_STATE};
        XrFrameWaitInfo waitInfo{XR_TYPE_FRAME_WAIT_INFO};
        XrResult r = waitFrame(s.session, &waitInfo, &frameState);
        if (XR_FAILED(r)) {
            fail(r, "xrWaitFrame");
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            continue;
        }
        const int64_t index = ++loop.frameIndex;
        loop.lastPredictedDisplayTime.store(frameState.predictedDisplayTime);
        loop.lastPredictedPeriod.store(frameState.predictedDisplayPeriod);
        const bool render = frameState.shouldRender == XR_TRUE && loop.renderer.load();
        if (!render) {
            XrFrameBeginInfo beginInfo{XR_TYPE_FRAME_BEGIN_INFO};
            r = beginFrame(s.session, &beginInfo);
            if (XR_SUCCEEDED(r)) endEmptyFrame(frameState.predictedDisplayTime);
            ++loop.emptyFrames;
            if (loop.onFrame) loop.onFrame(frameState.predictedDisplayTime, 0, index);
            continue;
        }
        // The views this frame is rendered with and shown at, located once for both.
        XrViewLocateInfo locateInfo{XR_TYPE_VIEW_LOCATE_INFO};
        locateInfo.viewConfigurationType = XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;
        locateInfo.displayTime = frameState.predictedDisplayTime;
        locateInfo.space = loop.space;
        XrViewState viewState{XR_TYPE_VIEW_STATE};
        XrView located[2] = {{XR_TYPE_VIEW}, {XR_TYPE_VIEW}};
        uint32_t located_count = 0;
        const XrResult lr = locateViews(s.session, &locateInfo, &viewState, 2, &located_count, located);
        // The renderer begins (driver thread, in the swapchain acquire), renders and ends the
        // frame (in the present); this thread waits until then before waiting for the next one.
        {
            std::unique_lock<std::mutex> lock(loop.mutex);
            loop.pendingFrame = index;
            loop.pendingDisplayTime = frameState.predictedDisplayTime;
            loop.frameEnded = false;
            loop.viewCount = XR_SUCCEEDED(lr) ? located_count : 0;
            loop.viewsValid = XR_SUCCEEDED(lr) && (viewState.viewStateFlags & XR_VIEW_STATE_ORIENTATION_VALID_BIT) &&
                    (viewState.viewStateFlags & XR_VIEW_STATE_POSITION_VALID_BIT);
            for (uint32_t i = 0; i < located_count && i < 2; ++i) loop.views[i] = located[i];
        }
        if (loop.onFrame) loop.onFrame(frameState.predictedDisplayTime, 1, index);
        std::unique_lock<std::mutex> lock(loop.mutex);
        loop.ended.wait_for(lock, std::chrono::milliseconds(250),
                [&] { return loop.frameEnded || loop.stop.load(); });
        if (!loop.frameEnded && !loop.stop.load()) {
            // The renderer missed the frame: end it empty so the runtime keeps its cadence (a frame
            // the driver thread already began is left to its present).
            lock.unlock();
            XrFrameBeginInfo beginInfo{XR_TYPE_FRAME_BEGIN_INFO};
            if (!loop.frameBegun.exchange(true)) {
                if (XR_SUCCEEDED(beginFrame(s.session, &beginInfo))) endEmptyFrame(frameState.predictedDisplayTime);
                loop.frameBegun.store(false);
            }
            ++loop.missedFrames;
        }
    }
    log("frame loop stopped after %lld frames", static_cast<long long>(loop.frameIndex));
}

}  // namespace

void openxr_bridge_set_frame_layers(const void* const* before, uint32_t before_count, const void* const* after,
        uint32_t after_count, uint64_t projection_flags) {
    FrameLoop& loop = frameLoop();
    std::lock_guard<std::mutex> lock(loop.layersMutex);
    loop.layersBefore.clear();
    loop.layersAfter.clear();
    for (uint32_t i = 0; i < before_count && before; ++i) {
        loop.layersBefore.push_back(static_cast<const XrCompositionLayerBaseHeader*>(before[i]));
    }
    for (uint32_t i = 0; i < after_count && after; ++i) {
        loop.layersAfter.push_back(static_cast<const XrCompositionLayerBaseHeader*>(after[i]));
    }
    loop.projectionFlags = static_cast<XrCompositionLayerFlags>(projection_flags);
    log("frame layers: %u before, %u after, projection flags 0x%llx", before_count, after_count,
            static_cast<unsigned long long>(projection_flags));
}

void openxr_bridge_set_environment_blend_mode(int32_t mode) {
    frameLoop().blendMode.store(static_cast<XrEnvironmentBlendMode>(mode <= 0 ? XR_ENVIRONMENT_BLEND_MODE_OPAQUE : mode));
    log("environment blend mode %d", mode);
}

void* openxr_bridge_get_instance_proc_addr(void) { return reinterpret_cast<void*>(state().getInstanceProcAddr); }

uint64_t openxr_bridge_instance_handle(void) { return reinterpret_cast<uint64_t>(state().instance); }

uint64_t openxr_bridge_session_handle(void) { return reinterpret_cast<uint64_t>(state().session); }

int32_t openxr_bridge_frame_loop_start(openxr_bridge_frame_callback on_frame, int32_t blend_mode) {
    FrameLoop& loop = frameLoop();
    if (loop.thread.joinable()) return XR_SUCCESS;
    if (state().session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    loop.stop.store(false);
    loop.onFrame = on_frame;
    loop.blendMode = static_cast<XrEnvironmentBlendMode>(blend_mode == 0 ? XR_ENVIRONMENT_BLEND_MODE_OPAQUE : blend_mode);
    loop.frameIndex = 0;
    loop.emptyFrames = 0;
    loop.missedFrames = 0;
    loop.thread = std::thread(run);
    return XR_SUCCESS;
}

void openxr_bridge_frame_loop_stop(void) {
    FrameLoop& loop = frameLoop();
    if (!loop.thread.joinable()) return;
    loop.stop.store(true);
    loop.ended.notify_all();
    loop.thread.join();
    loop.onFrame = nullptr;
}

bool openxr_bridge_frame_loop_running(void) { return frameLoop().thread.joinable(); }

void openxr_bridge_frame_loop_stats(int64_t* frames, int64_t* empty_frames, int64_t* missed_frames,
        int64_t* predicted_period) {
    FrameLoop& loop = frameLoop();
    if (frames) *frames = loop.frameIndex;
    if (empty_frames) *empty_frames = loop.emptyFrames;
    if (missed_frames) *missed_frames = loop.missedFrames;
    if (predicted_period) *predicted_period = loop.lastPredictedPeriod.load();
}

int64_t openxr_bridge_last_predicted_display_time(void) { return frameLoop().lastPredictedDisplayTime.load(); }

int32_t openxr_bridge_frame_loop_set_renderer(bool render, int64_t space) {
    FrameLoop& loop = frameLoop();
    XrSpace handle = XR_NULL_HANDLE;
    for (const auto& s : state().spaces) {
        if (s.id == space) handle = s.handle;
    }
    if (render && handle == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no such space");
    {
        std::lock_guard<std::mutex> lock(loop.mutex);
        loop.space = handle;
    }
    loop.renderer.store(render);
    return XR_SUCCESS;
}

uint32_t openxr_bridge_frame_views(int64_t frame, openxr_bridge_view* out, uint32_t capacity) {
    FrameLoop& loop = frameLoop();
    std::lock_guard<std::mutex> lock(loop.mutex);
    if (loop.pendingFrame != frame || !loop.viewsValid) return 0;
    const uint32_t n = std::min<uint32_t>(capacity, loop.viewCount);
    for (uint32_t i = 0; i < n && out; ++i) {
        const XrView& v = loop.views[i];
        out[i].pose.position[0] = v.pose.position.x;
        out[i].pose.position[1] = v.pose.position.y;
        out[i].pose.position[2] = v.pose.position.z;
        out[i].pose.orientation[0] = v.pose.orientation.x;
        out[i].pose.orientation[1] = v.pose.orientation.y;
        out[i].pose.orientation[2] = v.pose.orientation.z;
        out[i].pose.orientation[3] = v.pose.orientation.w;
        out[i].pose.flags = 0;
        out[i].angle_left = v.fov.angleLeft;
        out[i].angle_right = v.fov.angleRight;
        out[i].angle_up = v.fov.angleUp;
        out[i].angle_down = v.fov.angleDown;
    }
    return n;
}

void openxr_bridge_skip_frame(int64_t frame) {
    FrameLoop& loop = frameLoop();
    {
        std::lock_guard<std::mutex> lock(loop.mutex);
        if (loop.pendingFrame != frame || loop.frameEnded) return;
    }
    State& s = state();
    if (!loop.frameBegun.exchange(true)) {
        XrFrameBeginInfo beginInfo{XR_TYPE_FRAME_BEGIN_INFO};
        if (XR_SUCCEEDED(fn<PFN_xrBeginFrame>("xrBeginFrame")(s.session, &beginInfo))) {
            endEmptyFrame(loop.pendingDisplayTime);
        }
        loop.frameBegun.store(false);
    }
    {
        std::lock_guard<std::mutex> lock(loop.mutex);
        loop.frameEnded = true;
        ++loop.missedFrames;
    }
    loop.ended.notify_all();
}

int64_t openxr_bridge_rendered_frames(void) { return frameLoop().renderedFrames; }
