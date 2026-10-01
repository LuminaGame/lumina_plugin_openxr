#include "openxr_bridge_c.h"

#include <cstring>
#include <string>
#include <cstdlib>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

static std::string g_runtimePath;
static std::string g_runtimeName;
static bool g_initialized = false;
#if defined(_WIN32)
static HMODULE g_loaderModule = nullptr;
#else
static void* g_loaderModule = nullptr;
#endif

static void detectActiveRuntime() {
    g_runtimePath.clear();
    g_runtimeName = "None";

    // 1. Check environment variable override
    const char* envRuntime = std::getenv("XR_RUNTIME_JSON");
    if (envRuntime && envRuntime[0] != '\0') {
        g_runtimePath = envRuntime;
    }

#if defined(_WIN32)
    // 2. Query Windows Registry: HKEY_LOCAL_MACHINE\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime
    if (g_runtimePath.empty()) {
        HKEY hKey = nullptr;
        if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Khronos\\OpenXR\\1", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            char buffer[MAX_PATH];
            DWORD bufferSize = sizeof(buffer);
            DWORD type = REG_SZ;
            if (RegQueryValueExA(hKey, "ActiveRuntime", nullptr, &type, reinterpret_cast<LPBYTE>(buffer), &bufferSize) == ERROR_SUCCESS) {
                g_runtimePath = buffer;
            }
            RegCloseKey(hKey);
        }
    }
#endif

    if (!g_runtimePath.empty()) {
        // Derive friendly runtime name
        std::string lower = g_runtimePath;
        for (char& c : lower) {
            c = static_cast<char>(tolower(c));
        }

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
    }
}

int32_t openxr_bridge_is_runtime_available(void) {
    if (g_runtimeName.empty() || g_runtimeName == "None") {
        detectActiveRuntime();
    }
    return (!g_runtimePath.empty()) ? 1 : 0;
}

const char* openxr_bridge_get_active_runtime_path(void) {
    if (g_runtimeName.empty() || g_runtimeName == "None") {
        detectActiveRuntime();
    }
    return g_runtimePath.c_str();
}

const char* openxr_bridge_get_active_runtime_name(void) {
    if (g_runtimeName.empty() || g_runtimeName == "None") {
        detectActiveRuntime();
    }
    return g_runtimeName.c_str();
}

int32_t openxr_bridge_initialize(void) {
    if (g_initialized) {
        return 0;
    }

    detectActiveRuntime();

#if defined(_WIN32)
    // Try to load openxr_loader.dll
    g_loaderModule = LoadLibraryA("openxr_loader.dll");
    if (!g_loaderModule && !g_runtimePath.empty()) {
        // Parse directory of active runtime JSON
        size_t lastSlash = g_runtimePath.find_last_of("\\/");
        if (lastSlash != std::string::npos) {
            std::string dir = g_runtimePath.substr(0, lastSlash + 1);
            std::string possibleDll = dir + "openxr_loader.dll";
            g_loaderModule = LoadLibraryA(possibleDll.c_str());
        }
    }
#else
    g_loaderModule = dlopen("libopenxr_loader.so", RTLD_NOW | RTLD_LOCAL);
    if (!g_loaderModule) {
        g_loaderModule = dlopen("libopenxr_loader.so.1", RTLD_NOW | RTLD_LOCAL);
    }
#endif

    g_initialized = true;
    return (g_loaderModule != nullptr) ? 0 : 1;
}

void openxr_bridge_shutdown(void) {
#if defined(_WIN32)
    if (g_loaderModule) {
        FreeLibrary(g_loaderModule);
        g_loaderModule = nullptr;
    }
#else
    if (g_loaderModule) {
        dlclose(g_loaderModule);
        g_loaderModule = nullptr;
    }
#endif
    g_initialized = false;
}
