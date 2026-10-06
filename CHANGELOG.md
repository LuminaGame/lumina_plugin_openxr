# Changelog

All notable changes to `lumina_plugin_openxr` will be documented in this file.

## [Unreleased]

### Changed
- Runs in its own process in Lumina Studio (`"isolation": "process"`): `LuminaPluginOpenxrProcess` runs the plugin
  through `PluginProcessAdapter`, so the OpenXR loader bridge, the session and every command live outside the editor;
  a crash or hang there stops only the plugin process (the editor shows it and offers Restart). The editor module's
  `registration_class` is now `LuminaPluginOpenxrShell`, which holds no OpenXR code. Debugging override:
  `.lmproject` `plugin_isolation: {"lumina_plugin_openxr": "in_process"}`.
- Commands run without a `BuildContext` open the new declarative **OpenXR** panel (`OpenXrStatusView`) instead of a
  dialog.
- The status bar button shows the runtime and the VR preview live and opens a menu (Check Runtime, Toggle VR Preview,
  OpenXR Settings); Toggle VR Preview carries a check mark.

### Added
- `LuminaPluginOpenxrPlugin`: `vrPreview`, `statusButtonState`, `changes`, `stereoMode`, `setForceSimulation`,
  `setTrackingOrigin`, `toggleVrPreview`, `refreshStatus`, `statusJson`, `panelId`, `aboutText`.
- `OpenXrBindings.isSimulationForced`; `OpenXrSettingsView` optional `initialStereoMode`, `onChanged`,
  `onStereoModeChanged`; `showOpenXrMessageDialog`, `showOpenXrSettingsDialog`.
- `get_status` also returns `native_runtime_available` and `stereo_mode`.
- A crash reporter in the plugin process that sends caught native errors to the editor's log.

## [0.1.0] - 2026-10-02

### Added
- Khronos OpenXR 1.0/1.1 runtime integration for Lumina Studio and runtime games.
- Native Assets hook (`hook/build.dart`) and C bridge (`src/openxr_bridge_c.cpp`) detecting active runtime registry keys on Windows and shared loader libraries on Linux.
- Built-in `SimulatedOpenXrBackend` for headless testing and VR development on systems without physical HMDs.
- `LuminaXROriginActor` tracking space manager with eye-level, floor-level, and stage reference spaces.
- `LuminaXRHMDComponent` for head tracking, IPD calculation, and stereo eye offset generation.
- `LuminaXRControllerComponent` handling left and right hand motion controllers, grip/aim poses, buttons, and haptics.
- `OpenXrFilamentBridge` connecting OpenXR asymmetric perspective projections to Filament's native stereoscopic rendering pipeline (`StereoscopicType.instanced` and `StereoscopicType.multiview`).
- Lumina Studio editor integration: status bar indicator badge, VR Preview toggle, XR settings view, and MCP diagnostic tool `lumina_plugin_openxr.get_status`.
