// Runtime discovery, the loader, logging and the shared state.

#include "openxr_bridge_internal.h"

#include <cctype>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif
#if defined(__ANDROID__)
#include <android/log.h>
#endif

namespace openxr_bridge {

State& state() {
    static State s;
    return s;
}

void log(const char* format, ...) {
    va_list args;
    va_start(args, format);
#if defined(__ANDROID__)
    __android_log_vprint(ANDROID_LOG_INFO, "LuminaOpenXR", format, args);
#else
    fprintf(stderr, "[LuminaOpenXR] ");
    vfprintf(stderr, format, args);
    fprintf(stderr, "\n");
#endif
    va_end(args);
}

XrResult fail(XrResult result, const std::string& message) {
    char name[XR_MAX_RESULT_STRING_SIZE] = {};
    auto toString = state().instance != XR_NULL_HANDLE ? fn<PFN_xrResultToString>("xrResultToString") : nullptr;
    if (toString) {
        toString(state().instance, result, name);
    } else {
        snprintf(name, sizeof(name), "XrResult %d", static_cast<int>(result));
    }
    state().lastError = message + ": " + name;
    log("%s", state().lastError.c_str());
    return result;
}

PFN_xrVoidFunction proc(const char* name) {
    State& s = state();
    if (!s.getInstanceProcAddr) return nullptr;
    PFN_xrVoidFunction function = nullptr;
    if (s.getInstanceProcAddr(s.instance, name, &function) != XR_SUCCESS) return nullptr;
    return function;
}

void* openLibrary(const char* name) {
#if defined(_WIN32)
    return reinterpret_cast<void*>(LoadLibraryA(name));
#else
    return dlopen(name, RTLD_NOW | RTLD_LOCAL);
#endif
}

void* librarySymbol(void* library, const char* name) {
    if (!library) return nullptr;
#if defined(_WIN32)
    return reinterpret_cast<void*>(GetProcAddress(reinterpret_cast<HMODULE>(library), name));
#else
    return dlsym(library, name);
#endif
}

void closeLibrary(void* library) {
    if (!library) return;
#if defined(_WIN32)
    FreeLibrary(reinterpret_cast<HMODULE>(library));
#else
    dlclose(library);
#endif
}

}  // namespace openxr_bridge

using namespace openxr_bridge;

namespace {

std::string g_runtimePath;
std::string g_runtimeName = "None";
bool g_detected = false;

void detectActiveRuntime() {
    if (g_detected) return;
    g_detected = true;
#if defined(__ANDROID__)
    // The Khronos loader asks the runtime broker; there is no manifest to find.
    g_runtimePath = "android://runtime_broker";
    g_runtimeName = "Android OpenXR runtime (broker)";
    return;
#else
    const char* envRuntime = std::getenv("XR_RUNTIME_JSON");
    if (envRuntime && envRuntime[0] != '\0') g_runtimePath = envRuntime;
#if defined(_WIN32)
    if (g_runtimePath.empty()) {
        HKEY key = nullptr;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Khronos\\OpenXR\\1", 0, KEY_READ, &key) == ERROR_SUCCESS) {
            char buffer[MAX_PATH];
            DWORD size = sizeof(buffer);
            DWORD type = REG_SZ;
            if (RegQueryValueExA(key, "ActiveRuntime", nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &size) ==
                    ERROR_SUCCESS) {
                g_runtimePath = buffer;
            }
            RegCloseKey(key);
        }
    }
#endif
    if (g_runtimePath.empty()) return;
    std::string lower = g_runtimePath;
    for (char& c : lower) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (lower.find("oculus") != std::string::npos || lower.find("meta") != std::string::npos) {
        g_runtimeName = "Meta Quest / Oculus Link";
    } else if (lower.find("steamvr") != std::string::npos) {
        g_runtimeName = "SteamVR";
    } else if (lower.find("mixedreality") != std::string::npos || lower.find("windowsmr") != std::string::npos) {
        g_runtimeName = "Windows Mixed Reality";
    } else if (lower.find("monado") != std::string::npos) {
        g_runtimeName = "Monado";
    } else if (lower.find("varjo") != std::string::npos) {
        g_runtimeName = "Varjo OpenXR";
    } else {
        g_runtimeName = "Active OpenXR Runtime (" + g_runtimePath + ")";
    }
#endif
}

}  // namespace

int32_t openxr_bridge_is_runtime_available(void) {
    detectActiveRuntime();
    return g_runtimePath.empty() ? 0 : 1;
}

const char* openxr_bridge_get_active_runtime_path(void) {
    detectActiveRuntime();
    return g_runtimePath.c_str();
}

const char* openxr_bridge_get_active_runtime_name(void) {
    detectActiveRuntime();
    return g_runtimeName.c_str();
}

int32_t openxr_bridge_initialize(void) {
    State& s = state();
    if (s.getInstanceProcAddr) return 0;
    detectActiveRuntime();
#if defined(_WIN32)
    s.loader = openLibrary("openxr_loader.dll");
    if (!s.loader && !g_runtimePath.empty()) {
        const size_t slash = g_runtimePath.find_last_of("\\/");
        if (slash != std::string::npos) {
            s.loader = openLibrary((g_runtimePath.substr(0, slash + 1) + "openxr_loader.dll").c_str());
        }
    }
#else
    // Android: the Khronos loader the hook bundles next to this library.
    s.loader = openLibrary("libopenxr_loader.so");
    if (!s.loader) s.loader = openLibrary("libopenxr_loader.so.1");
#endif
    if (!s.loader) {
        s.lastError = "the OpenXR loader library was not found";
        return 1;
    }
    s.getInstanceProcAddr =
            reinterpret_cast<PFN_xrGetInstanceProcAddr>(librarySymbol(s.loader, "xrGetInstanceProcAddr"));
    if (!s.getInstanceProcAddr) {
        s.lastError = "the OpenXR loader exports no xrGetInstanceProcAddr";
        closeLibrary(s.loader);
        s.loader = nullptr;
        return 2;
    }
    return 0;
}

bool openxr_bridge_loader_loaded(void) {
    return state().getInstanceProcAddr != nullptr;
}

const char* openxr_bridge_last_error(void) {
    return state().lastError.c_str();
}

void openxr_bridge_shutdown(void) {
    openxr_bridge_frame_loop_stop();
    openxr_bridge_destroy_session();
    openxr_bridge_destroy_instance();
    State& s = state();
    s.getInstanceProcAddr = nullptr;
    closeLibrary(s.loader);
    s.loader = nullptr;
}
