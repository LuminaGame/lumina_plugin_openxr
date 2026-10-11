// Input: action sets and actions, suggested bindings per interaction profile,
// attaching and syncing, action states, action spaces, haptics and the current
// interaction profile.

#include "openxr_bridge_internal.h"

#include <cstring>

using namespace openxr_bridge;

namespace {

XrPath toPath(const char* path) {
    XrPath out = XR_NULL_PATH;
    auto stringToPath = fn<PFN_xrStringToPath>("xrStringToPath");
    if (!stringToPath || !path) return XR_NULL_PATH;
    if (XR_FAILED(stringToPath(state().instance, path, &out))) return XR_NULL_PATH;
    return out;
}

/// The subaction path of [hand] (XR_NULL_PATH for -1 or before the instance).
XrPath handPath(int32_t hand) {
    State& s = state();
    if (hand < 0 || hand > 1 || s.instance == XR_NULL_HANDLE) return XR_NULL_PATH;
    if (s.handPaths[hand] == XR_NULL_PATH) {
        s.handPaths[hand] = toPath(hand == 0 ? "/user/hand/left" : "/user/hand/right");
    }
    return s.handPaths[hand];
}

XrActionSet actionSet(int64_t id) {
    auto& sets = state().actionSets;
    return id > 0 && static_cast<size_t>(id) <= sets.size() ? sets[id - 1] : XR_NULL_HANDLE;
}

XrAction action(int64_t id) {
    auto& actions = state().actions;
    return id > 0 && static_cast<size_t>(id) <= actions.size() ? actions[id - 1] : XR_NULL_HANDLE;
}

XrActionStateGetInfo getInfo(XrAction a, int32_t hand) {
    XrActionStateGetInfo info{XR_TYPE_ACTION_STATE_GET_INFO};
    info.action = a;
    info.subactionPath = handPath(hand);
    return info;
}

void copyName(char* out, size_t capacity, const char* name) {
    if (!out || capacity == 0) return;
    strncpy(out, name ? name : "", capacity - 1);
    out[capacity - 1] = 0;
}

}  // namespace

int64_t openxr_bridge_create_action_set(const char* name, const char* localized_name, uint32_t priority) {
    State& s = state();
    if (s.instance == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no instance");
    XrActionSetCreateInfo info{XR_TYPE_ACTION_SET_CREATE_INFO};
    copyName(info.actionSetName, sizeof(info.actionSetName), name);
    copyName(info.localizedActionSetName, sizeof(info.localizedActionSetName), localized_name);
    info.priority = priority;
    XrActionSet set = XR_NULL_HANDLE;
    XrResult r = fn<PFN_xrCreateActionSet>("xrCreateActionSet")(s.instance, &info, &set);
    if (XR_FAILED(r)) return fail(r, std::string("xrCreateActionSet ") + (name ? name : ""));
    s.actionSets.push_back(set);
    return static_cast<int64_t>(s.actionSets.size());
}

int64_t openxr_bridge_create_action(int64_t action_set, const char* name, const char* localized_name, int32_t type,
        bool per_hand) {
    State& s = state();
    XrActionSet set = actionSet(action_set);
    if (set == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no action set");
    XrPath hands[2] = {handPath(0), handPath(1)};
    XrActionCreateInfo info{XR_TYPE_ACTION_CREATE_INFO};
    copyName(info.actionName, sizeof(info.actionName), name);
    copyName(info.localizedActionName, sizeof(info.localizedActionName), localized_name);
    info.actionType = static_cast<XrActionType>(type);
    if (per_hand) {
        info.countSubactionPaths = 2;
        info.subactionPaths = hands;
    }
    XrAction a = XR_NULL_HANDLE;
    XrResult r = fn<PFN_xrCreateAction>("xrCreateAction")(set, &info, &a);
    if (XR_FAILED(r)) return fail(r, std::string("xrCreateAction ") + (name ? name : ""));
    s.actions.push_back(a);
    return static_cast<int64_t>(s.actions.size());
}

int32_t openxr_bridge_suggest_bindings(const char* profile, const int64_t* actions, const char* const* paths,
        uint32_t count) {
    State& s = state();
    if (s.instance == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no instance");
    std::vector<XrActionSuggestedBinding> bindings;
    for (uint32_t i = 0; i < count; ++i) {
        XrAction a = action(actions[i]);
        XrPath p = toPath(paths[i]);
        if (a == XR_NULL_HANDLE || p == XR_NULL_PATH) {
            return fail(XR_ERROR_PATH_INVALID, std::string("binding ") + (paths[i] ? paths[i] : ""));
        }
        bindings.push_back({a, p});
    }
    XrInteractionProfileSuggestedBinding info{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};
    info.interactionProfile = toPath(profile);
    info.countSuggestedBindings = static_cast<uint32_t>(bindings.size());
    info.suggestedBindings = bindings.data();
    XrResult r = fn<PFN_xrSuggestInteractionProfileBindings>("xrSuggestInteractionProfileBindings")(s.instance, &info);
    if (XR_FAILED(r)) return fail(r, std::string("xrSuggestInteractionProfileBindings ") + (profile ? profile : ""));
    log("bindings suggested for %s (%u)", profile, count);
    return r;
}

int32_t openxr_bridge_attach_action_sets(void) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no session");
    if (s.actionSetsAttached) return XR_SUCCESS;
    XrSessionActionSetsAttachInfo info{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};
    info.countActionSets = static_cast<uint32_t>(s.actionSets.size());
    info.actionSets = s.actionSets.data();
    XrResult r = fn<PFN_xrAttachSessionActionSets>("xrAttachSessionActionSets")(s.session, &info);
    if (XR_FAILED(r)) return fail(r, "xrAttachSessionActionSets");
    s.actionSetsAttached = true;
    log("%u action sets attached", info.countActionSets);
    return r;
}

bool openxr_bridge_action_sets_attached(void) { return state().actionSetsAttached; }

int32_t openxr_bridge_sync_actions(void) {
    State& s = state();
    if (s.session == XR_NULL_HANDLE || !s.actionSetsAttached) return XR_ERROR_ACTIONSET_NOT_ATTACHED;
    std::vector<XrActiveActionSet> active;
    for (auto set : s.actionSets) active.push_back({set, XR_NULL_PATH});
    XrActionsSyncInfo info{XR_TYPE_ACTIONS_SYNC_INFO};
    info.countActiveActionSets = static_cast<uint32_t>(active.size());
    info.activeActionSets = active.data();
    XrResult r = fn<PFN_xrSyncActions>("xrSyncActions")(s.session, &info);
    // XR_SESSION_NOT_FOCUSED is a success code: the states read inactive.
    return XR_FAILED(r) ? fail(r, "xrSyncActions") : r;
}

int32_t openxr_bridge_action_state_boolean(int64_t id, int32_t hand, bool* value, bool* active) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrActionStateGetInfo info = getInfo(a, hand);
    XrActionStateBoolean st{XR_TYPE_ACTION_STATE_BOOLEAN};
    XrResult r = fn<PFN_xrGetActionStateBoolean>("xrGetActionStateBoolean")(state().session, &info, &st);
    if (XR_FAILED(r)) return fail(r, "xrGetActionStateBoolean");
    if (value) *value = st.currentState == XR_TRUE;
    if (active) *active = st.isActive == XR_TRUE;
    return r;
}

int32_t openxr_bridge_action_state_float(int64_t id, int32_t hand, float* value, bool* active) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrActionStateGetInfo info = getInfo(a, hand);
    XrActionStateFloat st{XR_TYPE_ACTION_STATE_FLOAT};
    XrResult r = fn<PFN_xrGetActionStateFloat>("xrGetActionStateFloat")(state().session, &info, &st);
    if (XR_FAILED(r)) return fail(r, "xrGetActionStateFloat");
    if (value) *value = st.currentState;
    if (active) *active = st.isActive == XR_TRUE;
    return r;
}

int32_t openxr_bridge_action_state_vector2f(int64_t id, int32_t hand, float* x, float* y, bool* active) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrActionStateGetInfo info = getInfo(a, hand);
    XrActionStateVector2f st{XR_TYPE_ACTION_STATE_VECTOR2F};
    XrResult r = fn<PFN_xrGetActionStateVector2f>("xrGetActionStateVector2f")(state().session, &info, &st);
    if (XR_FAILED(r)) return fail(r, "xrGetActionStateVector2f");
    if (x) *x = st.currentState.x;
    if (y) *y = st.currentState.y;
    if (active) *active = st.isActive == XR_TRUE;
    return r;
}

int32_t openxr_bridge_action_state_pose(int64_t id, int32_t hand, bool* active) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrActionStateGetInfo info = getInfo(a, hand);
    XrActionStatePose st{XR_TYPE_ACTION_STATE_POSE};
    XrResult r = fn<PFN_xrGetActionStatePose>("xrGetActionStatePose")(state().session, &info, &st);
    if (XR_FAILED(r)) return fail(r, "xrGetActionStatePose");
    if (active) *active = st.isActive == XR_TRUE;
    return r;
}

int64_t openxr_bridge_create_action_space(int64_t id, int32_t hand) {
    State& s = state();
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || s.session == XR_NULL_HANDLE) return fail(XR_ERROR_HANDLE_INVALID, "no action or session");
    XrActionSpaceCreateInfo info{XR_TYPE_ACTION_SPACE_CREATE_INFO};
    info.action = a;
    info.subactionPath = handPath(hand);
    info.poseInActionSpace.orientation.w = 1.0f;
    XrSpace handle = XR_NULL_HANDLE;
    XrResult r = fn<PFN_xrCreateActionSpace>("xrCreateActionSpace")(s.session, &info, &handle);
    if (XR_FAILED(r)) return fail(r, "xrCreateActionSpace");
    Space space;
    space.id = s.nextSpaceId++;
    space.handle = handle;
    s.spaces.push_back(space);
    return space.id;
}

int32_t openxr_bridge_apply_haptic(int64_t id, int32_t hand, int64_t duration_ns, float frequency, float amplitude) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrHapticActionInfo info{XR_TYPE_HAPTIC_ACTION_INFO};
    info.action = a;
    info.subactionPath = handPath(hand);
    XrHapticVibration vibration{XR_TYPE_HAPTIC_VIBRATION};
    vibration.duration = duration_ns;
    vibration.frequency = frequency;
    vibration.amplitude = amplitude;
    XrResult r = fn<PFN_xrApplyHapticFeedback>("xrApplyHapticFeedback")(
            state().session, &info, reinterpret_cast<const XrHapticBaseHeader*>(&vibration));
    if (XR_FAILED(r)) return fail(r, "xrApplyHapticFeedback");
    log("haptic pulse hand %d amplitude %.2f duration %lld ns frequency %.0f", hand, amplitude,
            static_cast<long long>(duration_ns), frequency);
    return r;
}

int32_t openxr_bridge_stop_haptic(int64_t id, int32_t hand) {
    XrAction a = action(id);
    if (a == XR_NULL_HANDLE || state().session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrHapticActionInfo info{XR_TYPE_HAPTIC_ACTION_INFO};
    info.action = a;
    info.subactionPath = handPath(hand);
    XrResult r = fn<PFN_xrStopHapticFeedback>("xrStopHapticFeedback")(state().session, &info);
    return XR_FAILED(r) ? fail(r, "xrStopHapticFeedback") : r;
}

int32_t openxr_bridge_current_interaction_profile(int32_t hand, char* out, uint32_t capacity) {
    State& s = state();
    copyName(out, capacity, "");
    if (s.session == XR_NULL_HANDLE) return XR_ERROR_HANDLE_INVALID;
    XrInteractionProfileState profile{XR_TYPE_INTERACTION_PROFILE_STATE};
    XrResult r = fn<PFN_xrGetCurrentInteractionProfile>("xrGetCurrentInteractionProfile")(s.session, handPath(hand), &profile);
    if (XR_FAILED(r)) return fail(r, "xrGetCurrentInteractionProfile");
    if (profile.interactionProfile == XR_NULL_PATH) return r;
    char buffer[XR_MAX_PATH_LENGTH] = {};
    uint32_t length = 0;
    r = fn<PFN_xrPathToString>("xrPathToString")(s.instance, profile.interactionProfile, sizeof(buffer), &length, buffer);
    if (XR_FAILED(r)) return fail(r, "xrPathToString");
    copyName(out, capacity, buffer);
    log("interaction profile hand %d: %s", hand, buffer);
    return r;
}
