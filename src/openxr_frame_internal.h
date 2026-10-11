#ifndef OPENXR_FRAME_INTERNAL_H
#define OPENXR_FRAME_INTERNAL_H

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>

#include "openxr_bridge_internal.h"

namespace openxr_bridge {

/// The pacer thread and the hand-over of each frame to the renderer.
struct FrameLoop {
    std::thread thread;
    std::atomic<bool> stop{false};
    /// Set while a renderer (an external swapchain) ends the frames itself.
    std::atomic<bool> renderer{false};
    openxr_bridge_frame_callback onFrame = nullptr;
    XrEnvironmentBlendMode blendMode = XR_ENVIRONMENT_BLEND_MODE_OPAQUE;

    std::mutex mutex;
    std::condition_variable ended;
    int64_t pendingFrame = 0;
    XrTime pendingDisplayTime = 0;
    bool frameEnded = true;
    /// The renderer called xrBeginFrame for the pending frame.
    std::atomic<bool> frameBegun{false};

    int64_t frameIndex = 0;
    int64_t emptyFrames = 0;
    int64_t missedFrames = 0;
    std::atomic<int64_t> lastPredictedDisplayTime{0};
    std::atomic<int64_t> lastPredictedPeriod{0};
};

FrameLoop& frameLoop();

}  // namespace openxr_bridge

#endif  // OPENXR_FRAME_INTERNAL_H
