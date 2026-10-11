#ifndef OPENXR_FRAME_INTERNAL_H
#define OPENXR_FRAME_INTERNAL_H

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

#include "openxr_bridge_internal.h"

namespace openxr_bridge {

/// The pacer thread and the hand-over of each frame to the renderer.
struct FrameLoop {
    std::thread thread;
    std::atomic<bool> stop{false};
    /// Set while a renderer (an external swapchain) ends the frames itself.
    std::atomic<bool> renderer{false};
    openxr_bridge_frame_callback onFrame = nullptr;
    std::atomic<XrEnvironmentBlendMode> blendMode{XR_ENVIRONMENT_BLEND_MODE_OPAQUE};

    /// Other plugins' layers under / over the projection layer, and the
    /// projection layer's flags (openxr_bridge_set_frame_layers).
    std::mutex layersMutex;
    std::vector<const XrCompositionLayerBaseHeader*> layersBefore;
    std::vector<const XrCompositionLayerBaseHeader*> layersAfter;
    XrCompositionLayerFlags projectionFlags = 0;

    std::mutex mutex;
    std::condition_variable ended;
    int64_t pendingFrame = 0;
    XrTime pendingDisplayTime = 0;
    bool frameEnded = true;
    /// The renderer called xrBeginFrame for the pending frame.
    std::atomic<bool> frameBegun{false};

    /// The space the views are located in and the projection layer lives in.
    XrSpace space = XR_NULL_HANDLE;
    /// The views of the pending frame, located by the pacer at its predicted display time.
    XrView views[2] = {{XR_TYPE_VIEW}, {XR_TYPE_VIEW}};
    uint32_t viewCount = 0;
    bool viewsValid = false;
    int64_t renderedFrames = 0;

    int64_t frameIndex = 0;
    int64_t emptyFrames = 0;
    int64_t missedFrames = 0;
    std::atomic<int64_t> lastPredictedDisplayTime{0};
    std::atomic<int64_t> lastPredictedPeriod{0};
};

FrameLoop& frameLoop();

/// xrEndFrame for [displayTime] with the other plugins' layers around
/// [projection] (null: no rendered image this frame).
XrResult endFrameWithLayers(XrTime displayTime, XrCompositionLayerProjection* projection);

}  // namespace openxr_bridge

#endif  // OPENXR_FRAME_INTERNAL_H
