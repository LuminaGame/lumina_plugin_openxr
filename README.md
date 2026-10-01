# OpenXR Plugin for Lumina Studio (`lumina_plugin_openxr`)

Cross-platform Khronos OpenXR 1.0/1.1 integration for Lumina game engine and Lumina Studio.

## Features

- **Cross-Platform OpenXR**: Compatible with Meta Quest Link, SteamVR, Windows Mixed Reality, Monado, and Varjo.
- **Native Assets Integration**: Native C bridge compiled via `hook/build.dart` dynamically discovering active runtime registry on Windows and system loader libraries on Linux.
- **Simulated XR Runtime**: Built-in 6-DOF simulation mode for developing and running tests without requiring a physical VR headset.
- **Stereoscopic Rendering**: Bridges OpenXR asymmetric field of view (FOV) and IPD directly into Google Filament's stereoscopic pipeline (`StereoscopicType.instanced` and `StereoscopicType.multiview`).
- **Engine Components**:
  - `LuminaXROriginActor`: Root tracking space actor supporting Floor-level, Eye-level, and Stage reference spaces.
  - `LuminaXRHMDComponent`: Real-time head tracking driving eye viewpoints.
  - `LuminaXRControllerComponent`: Grip and aim tracking for Left and Right controllers, thumbstick/trigger axes, digital buttons, and haptic pulse feedback.
- **Editor Integration**: Live OpenXR status badge on the status bar, VR Preview toggle, XR Project Settings panel, and AI agent diagnostic tool `openxr.get_status`.

## Installation

Add to your project's `pubspec.yaml` or enable via **Plugins → Plugin Manager**:

```yaml
dependencies:
  lumina_plugin_openxr:
    path: ../openxr
```

## Architecture

- `lib/src/ffi/`: OpenXR FFI structs, native loader lookup, and simulation backend.
- `lib/src/session/`: Session state machine and coordinate conversions (OpenXR metres Y-up to Lumina cm Z-up).
- `lib/src/input/`: Action sets, axis states, and interaction profile bindings.
- `lib/src/components/`: XR Origin actor, HMD component, and controller components.
- `lib/src/render/`: Stereoscopic asymmetric projection math and Filament bridge.
- `lib/src/ui/`: shadcn_flutter status bar badge and XR settings form.

## License

MIT License. See [LICENSE](file:///d:/lumina/openxr/LICENSE).
