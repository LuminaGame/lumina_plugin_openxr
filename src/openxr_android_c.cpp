// Android glue: the JavaVM (JNI_OnLoad, when the Kotlin plugin loads this
// library) and the activity (OpenXrPlugin.nativeSetActivity), which
// xrInitializeLoaderKHR and XrInstanceCreateInfoAndroidKHR need.

#include "openxr_bridge_internal.h"

using namespace openxr_bridge;

#if defined(__ANDROID__)

namespace {
JavaVM* g_vm = nullptr;
jobject g_activity = nullptr;
bool g_loaderInitialized = false;
}  // namespace

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void*) {
    g_vm = vm;
    return JNI_VERSION_1_6;
}

extern "C" JNIEXPORT void JNICALL Java_com_lumina_openxr_OpenXrPlugin_nativeSetActivity(JNIEnv* env, jclass,
        jobject activity) {
    if (g_activity) {
        env->DeleteGlobalRef(g_activity);
        g_activity = nullptr;
    }
    if (activity) g_activity = env->NewGlobalRef(activity);
    if (!g_vm) env->GetJavaVM(&g_vm);
    log("activity %s", activity ? "attached" : "detached");
}

namespace openxr_bridge {
void* androidVm() { return g_vm; }
void* androidActivity() { return g_activity; }
}  // namespace openxr_bridge

int32_t openxr_bridge_initialize_loader_android(void) {
    if (g_loaderInitialized) return XR_SUCCESS;
    if (!g_vm || !g_activity) return fail(XR_ERROR_INITIALIZATION_FAILED, "no activity from the OpenXR plugin");
    if (!openxr_bridge_loader_loaded() && openxr_bridge_initialize() != 0) {
        return fail(XR_ERROR_RUNTIME_UNAVAILABLE, "no OpenXR loader (" + state().lastError + ")");
    }
    auto initialize = fn<PFN_xrInitializeLoaderKHR>("xrInitializeLoaderKHR");
    if (!initialize) return fail(XR_ERROR_FUNCTION_UNSUPPORTED, "xrInitializeLoaderKHR");
    XrLoaderInitInfoAndroidKHR info{XR_TYPE_LOADER_INIT_INFO_ANDROID_KHR};
    info.applicationVM = g_vm;
    info.applicationContext = g_activity;
    XrResult r = initialize(reinterpret_cast<const XrLoaderInitInfoBaseHeaderKHR*>(&info));
    if (XR_FAILED(r)) return fail(r, "xrInitializeLoaderKHR");
    g_loaderInitialized = true;
    log("loader initialised");
    return XR_SUCCESS;
}

bool openxr_bridge_has_android_activity(void) { return g_activity != nullptr; }

#else

namespace openxr_bridge {
void* androidVm() { return nullptr; }
void* androidActivity() { return nullptr; }
}  // namespace openxr_bridge

int32_t openxr_bridge_initialize_loader_android(void) { return XR_SUCCESS; }
bool openxr_bridge_has_android_activity(void) { return false; }

#endif
