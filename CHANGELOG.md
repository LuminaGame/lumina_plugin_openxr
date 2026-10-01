# Changelog

All notable changes to `lumina_plugin_openxr` will be documented in this file.

## [0.1.0] - 2026-10-02

### Added
- Khronos OpenXR 1.0/1.1 runtime integration for Lumina Studio and runtime games.
- Native Assets hook (`hook/build.dart`) and C bridge (`src/openxr_bridge_c.cpp`) detecting active runtime registry keys on Windows and shared loader libraries on Linux.
- Built-in `SimulatedOpenXrBackend` for headless testing and VR development on systems without physical HMDs.
- `LuminaXROriginActor` tracking space manager with eye-level, floor-level, and stage reference spaces.
- `LuminaXRHMDComponent` for head tracking, IPD calculation, and stereo eye offset generation.
- `LuminaXRControllerComponent` handling left and right hand motion controllers, grip/aim poses, buttons, and haptics.
- `OpenXrFilamentBridge` connecting OpenXR asymmetric perspective projections to Filament's native stereoscopic rendering pipeline (`StereoscopicType.instanced` and `StereoscopicType.multiview`).
- Lumina Studio editor integration: status bar indicator badge, VR Preview toggle, XR settings view, and MCP diagnostic tool `openxr.get_status`.
