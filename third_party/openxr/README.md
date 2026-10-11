# Third-party: Khronos OpenXR and Vulkan headers, the OpenXR loader for Android

- `third_party/openxr/include/openxr/`: the OpenXR headers (`openxr.h`, `openxr_platform.h`,
  `openxr_platform_defines.h`, `openxr_reflection.h`, `openxr_loader_negotiation.h`) of the Khronos
  [OpenXR-SDK](https://github.com/KhronosGroup/OpenXR-SDK) tag `release-1.1.63`
  (`XR_CURRENT_API_VERSION` 1.1.63). Apache-2.0, `third_party/openxr/LICENSE`.
- `third_party/vulkan/include/`: the Vulkan headers the bridge compiles `XR_KHR_vulkan_enable2` against, from
  [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) tag `v1.3.290`. Apache-2.0 OR MIT,
  `third_party/vulkan/LICENSE.md` and `third_party/vulkan/LICENSES/`.
- **The OpenXR loader for Android is not in the repository.** The native-assets hook
  (`hook/openxr_loader.dart`) downloads `org.khronos.openxr:openxr_loader_for_android:1.1.63` from Maven Central at
  build time, checks the AAR's SHA-256 (`622419d2f6741c3443a3beb4779af0764318edd01830de967f24c741ebcded73`; Maven's
  SHA-1 `bb72fea1e7bdd35b381ae2a705206d912a1d5b30`), extracts `jni/<abi>/libopenxr_loader.so` into the hook's shared
  output folder and bundles it with the app as a code asset. The loader is Apache-2.0 (Copyright The Khronos Group
  Inc.); its licence is the same as `third_party/openxr/LICENSE`, which travels with the plugin.
  Why the hook and not the game's Gradle file: the bridge is a native-assets code asset already, the hook pins and
  verifies the exact binary, and a game needs no Gradle edit to get it.

All three are compatible with the plugin's MIT licence and Lumina's GPLv3.
