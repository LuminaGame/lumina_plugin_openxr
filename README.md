# OpenXR Support — Lumina Studio plugin (`lumina_plugin_openxr`)

The Khronos OpenXR base plugin for the [Lumina](https://github.com/LuminaGame/lumina) game engine and its editor,
Lumina Studio. It finds the OpenXR runtime installed on the machine, loads the OpenXR loader through a small native
bridge built by a Dart Native Assets hook, and gives games and the editor the pieces an XR application is made of:
a session with tracking spaces, an XR origin actor with head and controller components, input state for actions,
the stereo projection maths for Filament's stereoscopic rendering, and a simulated headset for working without one.

*Türkçe: [README.tr.md](README.tr.md)*

Vendor-specific features build on top of this package. The Meta Quest extensions (passthrough, hand tracking,
spatial anchors, scene, face and eye tracking) live in
[`lumina_plugin_metaxr`](https://github.com/LuminaGame/lumina_plugin_metaxr), which depends on this one.

## Contents

- [Status](#status)
- [Features](#features)
- [Requirements and platforms](#requirements-and-platforms)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Usage](#usage)
- [Editor integration](#editor-integration)
- [Runs in its own process](#runs-in-its-own-process)
- [Working without a headset](#working-without-a-headset)
- [Architecture](#architecture)
- [Coordinate systems and units](#coordinate-systems-and-units)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Limitations and roadmap](#limitations-and-roadmap)
- [Contributing](#contributing)
- [License](#license)

## Status

Version 0.1.0. The plugin is the foundation layer: runtime discovery, the loader bridge, the data model, the
components, the stereo maths, the simulated headset and the editor integration are in place and tested. The native
bridge does **not** yet create an `XrInstance` / `XrSession`, locate spaces or submit frames to the compositor; a
"native" session today means a runtime and loader were found. The table says what works now.

| Area | State |
|---|---|
| Active runtime discovery (`XR_RUNTIME_JSON`, Windows registry) and friendly runtime name | done |
| Loading the OpenXR loader library (`openxr_loader.dll`, `libopenxr_loader.so[.1]`) | done |
| Simulated headset: 6-DoF head, two controllers, IPD, per-eye asymmetric FOV, haptics log | done |
| Session state machine, tracking origins, OpenXR ↔ Lumina pose conversion | done |
| XR origin actor, HMD component (eye positions), controller component (grip/aim, inputs, haptics request) | done |
| Asymmetric per-eye projection and view matrices; Filament `EngineConfig` for instanced/multiview stereo | done |
| Editor menus, settings dialog, status bar button, MCP diagnostic tool | done |
| `xrCreateInstance` / `xrCreateSession`, event polling, `xrLocateSpace` / `xrLocateViews` through the bridge | planned |
| Swapchain creation and frame submission (`xrWaitFrame` / `xrBeginFrame` / `xrEndFrame`) | planned |
| Action binding to interaction profiles (`xrSuggestInteractionProfileBindings`, `xrSyncActions`), real haptics | planned |
| Android (Meta Quest standalone) native path | planned (Android runs on the simulated backend today) |

## Features

### Runtime discovery and loader bridge

- `OpenXrBindings` (singleton `OpenXrBindings.instance`) opens the native `openxr_bridge` library and asks it:
  - whether an OpenXR runtime is registered (`isNativeRuntimeAvailable`);
  - the runtime manifest path (`activeRuntimePath`) and a readable name (`activeRuntimeName`). The bridge recognises
    Meta Quest / Oculus Link, SteamVR, Windows Mixed Reality, Monado and Varjo from the manifest path and otherwise
    reports `Active OpenXR Runtime (<path>)`.
- Discovery order: the `XR_RUNTIME_JSON` environment variable, then (Windows) the registry value
  `HKEY_LOCAL_MACHINE\SOFTWARE\Khronos\OpenXR\1\ActiveRuntime`.
- `initialize()` loads the OpenXR loader: `openxr_loader.dll` from the DLL search path or next to the runtime
  manifest on Windows; `libopenxr_loader.so` or `libopenxr_loader.so.1` on Linux. `shutdown()` unloads it.
- When the bridge cannot be opened or no runtime is registered, everything falls back to the simulated backend;
  `setForceSimulation(true)` forces the simulator even when a runtime exists. `isSimulated` says which one is in use.
- `XrResult` mirrors the OpenXR result codes (`isSuccess` / `isFailure`, `fromValue`).

### Session and spaces

- `OpenXrSession`: `beginSession()`, `endSession()`, `pollEvents()`, `state` (`OpenXrSessionState`: `idle`, `ready`,
  `synchronized`, `visible`, `focused`, `stopping`, `lossPending`, `exiting`).
- Tracking origins (`OpenXrTrackingOrigin`): `eyeLevel` (seated, the OpenXR `LOCAL` space), `floorLevel` (standing,
  the default) and `stage` (bounded room scale, `STAGE`). `setTrackingOrigin` resets the space offset.
- `OpenXrReferenceSpace` holds an origin offset (`setOffset(position, orientation)`).
- `OpenXrSpaceConverter` converts positions and orientations between OpenXR and Lumina
  ([below](#coordinate-systems-and-units)).
- FFI structs with the OpenXR memory layout: `XrVector3f`, `XrQuaternionf`, `XrPosef`, `XrFovf`, `XrView`.

### Components

| Class | Kind | What it does |
|---|---|---|
| `LuminaXROriginActor` | `LuminaActor` | The play space in the world. Creates and attaches `hmdComponent`, `leftController` and `rightController` to its root; `trackingOrigin`; `recenter()` resets the head to the origin. |
| `LuminaXRHMDComponent` | `LuminaSceneComponent` | The head. `updatePoseFromOpenXr(position, orientation)` takes an OpenXR pose, `updatePoseLumina(location, rotation)` a Lumina one; `interPupillaryDistance` (metres, 0.064 default); `leftEyeLocation` / `rightEyeLocation` derived from the IPD. |
| `LuminaXRControllerComponent` | `LuminaSceneComponent` | A motion controller for one `LuminaXRHand`. Grip pose (`location` / `rotation`) and aim pose (`aimLocation` / `aimRotation`) via `updatePoseFromOpenXr`; `trigger`, `grip` (axis), `thumbstick` (2D), `primaryButton`, `secondaryButton`, `menuButton`; `playHapticPulse(amplitude, durationMicroseconds, frequencyHz)` records the request in `lastHapticPulse`. |
| `LuminaXRHand` | enum | `left`, `right` (`isLeft`, `isRight`). |

### Input

- `OpenXrButtonState` (`isPressed`, `isTouched`, `justPressed`, `justReleased`), `OpenXrAxisState` (0..1 with
  `delta`), `OpenXrVector2State` (−1..1 per axis), `OpenXrHapticFeedback`, `OpenXrActionType`.
- `OpenXrActionSet` groups the standard controller actions for both hands (triggers, grips, thumbsticks, A/B/X/Y,
  menu buttons).
- `OpenXrInteractionProfiles` names the standard profiles: Khronos simple controller, Oculus Touch, Valve Index,
  HTC Vive, Microsoft motion controller.

### Stereo rendering

- `OpenXrStereoView`: one eye's pose and the four FOV angles of an OpenXR `XrFovf`;
  `createProjectionMatrix(nearPlane, farPlane)` builds the asymmetric (off-axis) perspective projection,
  `createViewMatrix()` the inverse eye transform.
- `OpenXrFilamentBridge`: chooses the stereo technique (`OpenXrStereoMode.instanced` (default), `multiview`,
  `separateViews`), maps it to Filament's `StereoscopicType`, and `createEngineConfig()` returns a `flutter_filament`
  `EngineConfig` with two stereoscopic eyes. `updateEyeViews(left:, right:)` stores the current eye views.
- `OpenXrSwapchainDescriptor` / `OpenXrSwapchainFormat`: the parameters of a stereo swapchain (size, sample count,
  sRGB/UNORM colour or depth format, `arraySize` 2 for a texture array).

### Simulated headset

`SimulatedOpenXrBackend` (reached as `OpenXrBindings.instance.simulator`) is a complete stand-in runtime: system name
"Lumina Virtual OpenXR HMD", 2064 × 2208 per eye, 90 Hz, IPD 64 mm, head at 1.7 m, both controllers at waist height
in front. It gives per-eye views with an asymmetric FOV (`getLeftEyeView()`, `getRightEyeView()`), takes head look
angles (`setHeadLookAngles(yaw, pitch)`), controller poses (`setControllerPose`) and inputs
(`setControllerInputs`: trigger, grip, thumbstick, primary/secondary buttons), and records haptics
(`applyHapticFeedback`).

## Requirements and platforms

- Flutter with Dart SDK `^3.12.0` and a C/C++ toolchain the Native Assets hook can find: Visual Studio 2022 with the
  C++ workload on Windows, clang or gcc on Linux.
- The Lumina packages (`lumina`, `lumina_editor_api`, `flutter_filament`), pinned by commit in `pubspec.yaml`, and
  the prebuilt Filament that `flutter_filament` links (see the
  [Lumina setup guide](https://github.com/LuminaGame/lumina/blob/main/docs/en/getting-started/setup.md)).
- For a real headset: an installed OpenXR runtime that registers itself as the active runtime (Meta Quest Link,
  SteamVR, Windows Mixed Reality, Varjo, Monado, …) and the OpenXR loader on the library path. None of the OpenXR
  SDK is bundled; the loader comes from the runtime or the system.

| Platform | Runtime discovery | Loader | Notes |
|---|---|---|---|
| Windows (PC VR) | `XR_RUNTIME_JSON`, registry | `openxr_loader.dll` (search path or next to the manifest) | Main target. |
| Linux | `XR_RUNTIME_JSON` | `libopenxr_loader.so`, `.so.1` | Set `XR_RUNTIME_JSON` (for example to Monado's manifest); the `/etc/xdg/openxr/1/active_runtime.json` default is not read yet. |
| Android (Meta Quest) | — | — | The bridge library is not opened on Android; the simulated backend is used. |
| macOS | — | — | No OpenXR runtimes; simulated backend only. |

## Installation

### As a Lumina Studio plugin

The package carries its manifest, `lumina_plugin_openxr.lmplugin` (category *Virtual Reality*, editor module
`LuminaPluginOpenxrPlugin`). Lumina Studio scans `<project>/plugins/`, the per-user plugin folder
(`~/.local/share/lumina/plugins/` on Linux, `%LOCALAPPDATA%\Lumina\plugins` on Windows) and the engine's built-in
plugins.

1. Clone this repository and link or copy it into one of those folders (or use **Plugins → Plugin Manager → Import
   from Folder**).
2. Enable **OpenXR Support** in the Plugin Manager and restart the editor when it asks.

See [Editor plugins](https://github.com/LuminaGame/lumina/blob/main/docs/en/plugins/index.md) for discovery,
enabling and how code plugins are compiled into the editor.

### As a dependency of a game or another plugin

```yaml
dependencies:
  lumina_plugin_openxr:
    git:
      url: https://github.com/LuminaGame/lumina_plugin_openxr.git
      ref: <commit sha>
```

Then `flutter pub get`. Import everything from one library:

```dart
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';
```

Code that needs only the plain XR types (`LuminaXRHand`, `OpenXrActionType`, the action and input state classes,
`OpenXrInteractionProfiles`) can import `package:lumina_plugin_openxr/xr_types.dart` instead: it reaches neither
`dart:ffi` nor the OpenXR bridge. The main library exports the same types.

### The native bridge

`hook/build.dart` compiles `src/openxr_bridge_c.cpp` with `package:native_toolchain_c` into the code asset
`openxr_bridge` on the first `flutter run` / `flutter test` / `flutter build`: C++17, linked with `Advapi32` on
Windows (registry access) and `libdl` on Linux. It needs no OpenXR headers or libraries at build time; the loader is
opened at run time. If the library cannot be opened, the plugin keeps working on the simulated backend.

### Local development against sibling checkouts

`pubspec.yaml` points at the Lumina repositories on GitHub. To build against local checkouts next to this one
(`../lumina`, `../tools`), create a gitignored `pubspec_overrides.yaml` with `dependency_overrides:` for `lumina`,
`lumina_editor_api`, `flutter_filament` and the tools packages, and link the shared Filament build as `filament`
(`hooks: user_defines:` in `pubspec.yaml` reads it from there).

## Quick start

```dart
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

void startXr() {
  final xr = OpenXrBindings.instance;
  print('Runtime: ${xr.activeRuntimeName} (simulated: ${xr.isSimulated})');

  final session = OpenXrSession()..setTrackingOrigin(OpenXrTrackingOrigin.floorLevel);
  final result = session.beginSession();
  if (result.isFailure) {
    print('OpenXR session failed: $result');
    return;
  }

  // The play space: head + two controllers, attached to the actor's root.
  final origin = LuminaXROriginActor(trackingOrigin: session.trackingOrigin);
  // Add `origin` to your world like any other LuminaActor.
}
```

## Usage

### Driving the head and controllers each frame

The components take OpenXR poses (metres, Y-up) and store Lumina transforms (centimetres, Z-up). With the simulated
backend:

```dart
final sim = OpenXrBindings.instance.simulator;

void tick(LuminaXROriginActor origin, OpenXrSession session) {
  session.pollEvents();

  origin.hmdComponent.updatePoseFromOpenXr(sim.headPosition, sim.headOrientation);
  origin.leftController.updatePoseFromOpenXr(
    openXrGripPos: sim.leftGripPosition,
    openXrGripRot: sim.leftGripOrientation,
  );
  origin.rightController
    ..updatePoseFromOpenXr(
      openXrGripPos: sim.rightGripPosition,
      openXrGripRot: sim.rightGripOrientation,
    )
    ..trigger.update(sim.rightTrigger)
    ..primaryButton.update(sim.rightPrimaryButton);

  if (origin.rightController.primaryButton.justPressed) {
    origin.rightController.playHapticPulse(amplitude: 0.6, durationMicroseconds: 20000);
  }
}
```

### Per-eye projection for Filament

```dart
final bridge = OpenXrFilamentBridge(stereoMode: OpenXrStereoMode.multiview)..isStereoEnabled = true;
final engineConfig = bridge.createEngineConfig(); // stereoscopicEyeCount: 2, StereoscopicType.multiview

final l = OpenXrBindings.instance.simulator.getLeftEyeView();
final left = OpenXrStereoView(
  eyePosition: l.position,
  eyeOrientation: l.orientation,
  angleLeft: l.fovLeft,
  angleRight: l.fovRight,
  angleUp: l.fovUp,
  angleDown: l.fovDown,
);
final projection = left.createProjectionMatrix(nearPlane: 0.05, farPlane: 1000.0);
final view = left.createViewMatrix();
```

### Converting poses yourself

```dart
final luminaLocation = OpenXrSpaceConverter.openXrToLuminaPosition(openXrPosition); // cm, Z-up
final luminaRotation = OpenXrSpaceConverter.openXrToLuminaRotation(openXrOrientation);
final openXrPosition2 = OpenXrSpaceConverter.luminaToOpenXrPosition(luminaLocation); // m, Y-up
```

## Editor integration

Enabling the plugin adds:

| Where | Item | What it does |
|---|---|---|
| **Plugins → OpenXR → Check Runtime** | opens the **OpenXR** panel | Shows the active runtime and its manifest path, or that the simulated headset is in use. |
| **Plugins → OpenXR → Toggle VR Preview** | command, checked while running | Begins or ends the plugin's OpenXR session and logs it to the Output Log (source `OpenXR`). |
| **Plugins → OpenXR → OpenXR Settings** | opens the **OpenXR** panel | Runtime and manifest, **Force Simulated Runtime** switch, tracking origin (eyeLevel / floorLevel / stage) and stereo mode choice. |
| **Plugins → OpenXR → About OpenXR Support** | opens the **OpenXR** panel | Version and summary (the panel's collapsed About section). |
| Status bar (right) | **XR** button | Shows the active runtime live (`XR (Sim)` or `XR: <runtime>`; green with a dot while the VR preview runs); a click opens a menu with Check Runtime, Toggle VR Preview and OpenXR Settings. |
| **OpenXR** panel (right dock) | declarative panel | Runtime, manifest and kind; Force Simulated Runtime; tracking origin and stereo mode; session state and a Start / Stop VR Preview button; About. It follows every change, whichever menu, button or MCP client made it. |
| MCP | `lumina_plugin_openxr.get_status` (read-only) | Returns `active_runtime`, `manifest_path`, `is_simulated`, `native_runtime_available`, `session_state`, `tracking_origin`, `stereo_mode`, `vr_preview_active`. |

`OpenXrStatusBadge` (a badge showing native / simulated / offline) and `OpenXrSettingsView` are exported widgets, so a
game's own UI or another plugin can embed them. The MCP tool is reachable from any MCP client connected to Lumina
Studio's built-in MCP server. `LuminaPluginOpenxrPlugin` still works as an ordinary in-process plugin (a host that
calls its commands with a `BuildContext` gets the Check Runtime, Settings and About dialogs); Lumina Studio runs it in
the plugin's own process, described next.

## Runs in its own process

The manifest says `"isolation": "process"`: Lumina Studio starts the plugin in a separate process of its own
executable and talks to it over a local connection, so a crash or a hang in an OpenXR runtime or the native bridge
cannot take the editor down.

| Where | What runs there |
|---|---|
| Plugin process (`LuminaPluginOpenxrProcess`, the module's `process_class`) | `LuminaPluginOpenxrPlugin` unchanged through `PluginProcessAdapter`: the OpenXR loader bridge (`dart:ffi`), `OpenXrBindings`, the session, every menu and status bar command, the `get_status` MCP tool, the OpenXR panel's events (`OpenXrStatusView`), Output Log lines. Caught native errors reported through `LuminaPluginCrashReporter` go to the editor's log under the plugin's name (the plugin process runtime forwards them). |
| Editor | Nothing of OpenXR: the module names only a `process_class` and no `registration_class`, so the plugin has no in-editor part and the editor never opens the bridge. The editor draws the menu items, the status bar button (its state arrives as it changes) and the OpenXR panel from what the process sent. Editor code that needs the state calls the plugin's process channel: `call('status')` answers the `get_status` JSON. |

When the process stops (a crash, or no answer to three health checks in a row), the editor restarts it a few times,
then marks the plugin stopped: its menu items are greyed out, the OpenXR panel shows the state with a **Restart**
button, the Plugin Manager shows the status, the exit code and the log tail, and a plugin crash report is filed. The
editor and the open level keep running. A restart begins with a fresh session (the VR preview is off).

Debugging: to run the same process part inside the editor (breakpoints, one process), set the project override in the
`.lmproject`:

```json
"plugin_isolation": {"lumina_plugin_openxr": "in_process"}
```

or use **Run in editor process (debugging)** in the Plugin Manager. A crash in OpenXR then affects the editor again.

## Working without a headset

Nothing in the plugin requires hardware. Without a registered runtime (or with **Force Simulated Runtime** on)
`OpenXrBindings` routes everything to `SimulatedOpenXrBackend`: sessions begin and reach `focused`, the head and
controllers have plausible poses, and inputs and haptics can be scripted from tests or tools.
`lumina_plugin_metaxr` adds an editor panel that drives simulated hand gestures on top of this.

## Architecture

```
lib/
  lumina_plugin_openxr.dart          public library (exports everything below)
  xr_types.dart                      plain XR types without the native bridge (LuminaXRHand, action state)
  src/lumina_plugin_openxr_plugin.dart   LuminaEditorPlugin: menus, status bar button, MCP tool
  src/process/    LuminaPluginOpenxrProcess (process_class), OpenXrStatusView (the declarative OpenXR panel)
  src/ffi/        OpenXrBindings (native bridge + simulator switch), OpenXR types/structs, SimulatedOpenXrBackend
  src/session/    OpenXrSession, OpenXrReferenceSpace, OpenXrSpaceConverter
  src/input/      action set, button/axis/vector2 state, haptics, interaction profile paths
  src/components/ LuminaXROriginActor, LuminaXRHMDComponent, LuminaXRControllerComponent, LuminaXRHand
  src/render/     OpenXrStereoView, OpenXrFilamentBridge, OpenXrSwapchainDescriptor
  src/ui/         OpenXrSettingsView, OpenXrStatusBadge, the in-process dialogs (shadcn_flutter)
hook/build.dart   Native Assets hook building the bridge
src/              openxr_bridge_c.h / .cpp (C API, FFI_PLUGIN_EXPORT)
```

- **Dart ↔ native.** The bridge exports five C functions: `openxr_bridge_is_runtime_available`,
  `openxr_bridge_get_active_runtime_path`, `openxr_bridge_get_active_runtime_name`, `openxr_bridge_initialize`
  (0 on success) and `openxr_bridge_shutdown`. `OpenXrBindings` looks them up with `dart:ffi` and converts the
  results to `XrResult` and Dart strings. Every call is guarded; a failure logs through `package:logging` (logger
  `OpenXrBindings`) and falls back to the simulator.
- **Threading.** All calls are synchronous and made from the Dart isolate that owns the world (in Lumina Studio,
  the plugin process's isolate, never the editor's). The bridge keeps its state in process-wide statics; call it from one isolate.
- **Frame loop.** The game (or a tool) owns the loop: `session.pollEvents()`, read poses (today from the simulator),
  feed them to the components, build the eye views and hand them to the renderer. The bridge will take over pose
  and frame timing once instance/session creation lands.
- **Stereo path.** OpenXR gives each eye a pose and four FOV half-angles; `OpenXrStereoView` turns them into the
  off-axis projection and the view matrix; `OpenXrFilamentBridge` configures Filament for two-eye instanced or
  multiview rendering (one pass into a 2-layer texture array, matching `OpenXrSwapchainDescriptor.arraySize`), or
  `separateViews` for one ordinary pass per eye.

## Coordinate systems and units

| | Units | Axes |
|---|---|---|
| OpenXR | metres | right-handed, X right, Y up, −Z forward |
| Lumina (stored transforms) | centimetres (one world unit = 1 cm) | Z up |

`OpenXrSpaceConverter` maps OpenXR `(x, y, z)` metres to `(−z, x, y) × 100` centimetres — X forward, Y right, Z up —
and back with `luminaToOpenXrPosition`; `openXrToLuminaRotation` applies the same change of basis to orientations.
The HMD component works in the same frame (+Y is right when it places the eyes) and keeps the IPD in metres. The
simulator and the stereo maths stay in OpenXR metres, as the runtime reports them.

## Testing

Unit tests run on the simulated backend and need no headset or GPU:

```bash
flutter test test/openxr_loader_and_types_test.dart
flutter test test/openxr_session_and_spaces_test.dart
flutter test test/openxr_stereo_render_test.dart
flutter test test/xr_components_test.dart
flutter test test/openxr_editor_integration_test.dart
flutter test test/openxr_plugin_process_test.dart
flutter test test/xr_types_library_test.dart
flutter analyze
```

They cover the result codes and struct layouts, the simulation fallback, session states and tracking origins, the
coordinate conversion, input states, the projection matrix (finite values), the Filament stereo mapping, the
origin actor's components and the editor registration (menus and the MCP tool against a host context).
`openxr_plugin_process_test.dart` runs the process part with `runPluginProcessMain` against `LoopbackHost` (the
editor's side over a real loopback socket): the contributions, the status button's live state and menu, the menu
check mark, the OpenXR panel and its events, the MCP tool, the channel's `status`, errors answered without ending the
process, crash reports in the editor log and a clean shutdown.

## Troubleshooting

- **"Lumina Simulated HMD" although a headset is connected.** Check that the runtime is set as the active OpenXR
  runtime (in the Meta Quest Link app, SteamVR settings, …). On Linux set `XR_RUNTIME_JSON` to the runtime's
  manifest. Make sure **Force Simulated Runtime** is off. **Plugins → OpenXR → Check Runtime** shows what the bridge
  found.
- **`openxr_bridge_initialize` fails (initialization failed).** The loader was not found: put `openxr_loader.dll`
  on the DLL search path (or next to the runtime manifest), or install the system OpenXR loader package on Linux
  (`libopenxr-loader1` or equivalent).
- **The hook fails to build.** Install the C++ toolchain (Visual Studio 2022 C++ workload on Windows, clang/gcc on
  Linux) and run `flutter clean`.
- **Wrong runtime name.** The name is guessed from the manifest path; an unrecognised runtime is reported with its
  path, which does not affect behaviour.

## Limitations and roadmap

- No `XrInstance`, `XrSession`, space location, swapchains or frame submission through the bridge yet; on a machine
  with a runtime the session reports `focused` once the loader is loaded, and poses come from your own code or the
  simulator.
- `OpenXrActionSet.sync()` does not read the runtime yet; controller states are filled by the caller.
  `playHapticPulse` records the request (`lastHapticPulse`) without sending it to a device.
- The stereo mode chosen in the settings dialog is not yet pushed to the plugin's `OpenXrFilamentBridge`.
- The status bar button has a fixed label; the live `OpenXrStatusBadge` widget is available for embedding.
- `OpenXrSpaceConverter` uses its own forward axis (+X); aligning it with the engine's authoring frame
  (`LuminaAxes`) is planned.
- Android / Meta Quest standalone builds use the simulated backend until the bridge is built and loaded for Android.

Planned next: instance and session creation with the required extensions, `xrLocateViews` / `xrLocateSpace`
feeding the components, swapchain images shared with Filament, action bindings per interaction profile with real
haptics, and the Android loader path.

## Contributing

Issues and pull requests are welcome. Keep the analyzer clean (`flutter analyze`), add a unit test for new
behaviour (tests use the simulated backend; no mocks of the engine), and keep both READMEs in step (English and
Turkish). UI uses `shadcn_flutter` widgets only, as everywhere in Lumina Studio.

## License

MIT — see [LICENSE](LICENSE).

This repository contains no third-party source or binaries. At run time it loads the OpenXR loader and runtime
already installed on the machine (the Khronos OpenXR loader is Apache-2.0; runtimes have their own licences).
OpenXR™ is a trademark of The Khronos Group Inc.
