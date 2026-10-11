// The frame loop: xrWaitFrame blocks, so it runs on a native pacer thread of
// its own, never on a Dart isolate. Each frame the thread waits, then either
// ends an empty frame itself (no renderer attached) or hands the frame to the
// renderer (task 08) and waits until the renderer has ended it.

#include "openxr_bridge_internal.h"
#include "openxr_frame_internal.h"

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

}  // namespace openxr_bridge

namespace {

void endEmptyFrame(XrTime displayTime) {
    State& s = state();
    XrFrameEndInfo end{XR_TYPE_FRAME_END_INFO};
    end.displayTime = displayTime;
    end.environmentBlendMode = frameLoop().blendMode;
    end.layerCount = 0;
    fn<PFN_xrEndFrame>("xrEndFrame")(s.session, &end);
}

void run() {
    State& s = state();
    FrameLoop& loop = frameLoop();
    auto waitFrame = fn<PFN_xrWaitFrame>("xrWaitFrame");
    auto beginFrame = fn<PFN_xrBeginFrame>("xrBeginFrame");
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
        // The renderer begins (driver thread, in the swapchain acquire), renders and ends the
        // frame (in the present); this thread waits until then before waiting for the next one.
        {
            std::unique_lock<std::mutex> lock(loop.mutex);
            loop.pendingFrame = index;
            loop.pendingDisplayTime = frameState.predictedDisplayTime;
            loop.frameEnded = false;
        }
        if (loop.onFrame) loop.onFrame(frameState.predictedDisplayTime, 1, index);
        std::unique_lock<std::mutex> lock(loop.mutex);
        loop.ended.wait_for(lock, std::chrono::milliseconds(250),
                [&] { return loop.frameEnded || loop.stop.load(); });
        if (!loop.frameEnded && !loop.stop.load()) {
            // The renderer missed the frame: end it empty so the runtime keeps its cadence.
            lock.unlock();
            XrFrameBeginInfo beginInfo{XR_TYPE_FRAME_BEGIN_INFO};
            if (!loop.frameBegun.exchange(false)) {
                if (XR_SUCCEEDED(beginFrame(s.session, &beginInfo))) endEmptyFrame(frameState.predictedDisplayTime);
            }
            ++loop.missedFrames;
        }
    }
    log("frame loop stopped after %lld frames", static_cast<long long>(loop.frameIndex));
}

}  // namespace

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
