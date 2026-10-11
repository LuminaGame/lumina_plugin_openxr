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
- [Frame loop](#frame-loop)
- [Coordinate systems and units](#coordinate-systems-and-units)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Limitations and roadmap](#limitations-and-roadmap)
- [Contributing](#contributing)
- [License](#license)

## Status

Version 0.1.0. The plugin is the foundation layer: runtime discovery, the loader bridge, the data model, the
components, the stereo maths, the simulated headset and the editor integration are in place and tested. The native
bridge creates the `XrInstance`, the Vulkan device (`XR_KHR_vulkan_enable2`) and the `XrSession`, follows the
runtime's session events, runs the frame loop on a native thread and locates spaces and views; it runs on a Meta
Quest 3S. The table says what works now.

| Area | State |
|---|---|
| Active runtime discovery (`XR_RUNTIME_JSON`, Windows registry) and friendly runtime name | done |
| Loading the OpenXR loader library (`openxr_loader.dll`, `libopenxr_loader.so[.1]`) | done |
| Simulated headset: 6-DoF head, two controllers, IPD, per-eye asymmetric FOV, haptics log | done |
| Session state machine, tracking origins, OpenXR ↔ Lumina pose conversion | done |
| XR origin actor, HMD component (eye positions), controller component (grip/aim, inputs, haptics request) | done |
| Asymmetric per-eye projection and view matrices; Filament `EngineConfig` for instanced/multiview stereo | done |
| Editor menus, the OpenXR panel (an editor panel Widget Blueprint), status bar button, MCP diagnostic tool | done |
| `xrCreateInstance` / `xrCreateSession`, the Vulkan device through `XR_KHR_vulkan_enable2`, event polling and the event-driven session state machine, `xrLocateSpace` / `xrLocateViews` | done (Quest 3S: FOCUSED at 72 Hz) |
| The frame loop (`xrWaitFrame` on a native pacer thread, empty frames until a renderer attaches) | done |
| Swapchain on the runtime's Vulkan device, Filament rendering both eyes (multiview) into it, frame submission with a projection layer; `OpenXrFrameLoop`, `LuminaXRWorldDriver` | done (Quest 3S: 72 Hz, < 0.1 % late frames) |
| Action binding to interaction profiles (`xrSuggestInteractionProfileBindings`, `xrSyncActions`), real haptics | planned |
| Android (Meta Quest standalone) native path: the Khronos loader from Maven Central, the activity handed over by the Kotlin part (`OpenXrPlugin`) | done |
| `package:lumina_plugin_openxr/runtime.dart`: the library a game imports, free of editor code | done |

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

The package carries its manifest, `lumina_plugin_openxr.lmplugin` (category *Virtual Reality*, one module whose
`process_class` is `LuminaPluginOpenxrProcess`, `"can_contain_content": true` for the panel in `content/`). Lumina
Studio scans `<project>/plugins/`, the per-user plugin folder
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
| **Plugins → OpenXR → OpenXR Panel** | opens the **OpenXR** panel | The panel's own menu item (its `menuPath`). |
| **Plugins → OpenXR → Check Runtime** | opens the **OpenXR** panel | Shows the active runtime and its manifest path, or that the simulated headset is in use. |
| **Plugins → OpenXR → Toggle VR Preview** | command, checked while running | Begins or ends the plugin's OpenXR session and logs it to the Output Log (source `OpenXR`). |
| **Plugins → OpenXR → OpenXR Settings** | opens the **OpenXR** panel | Runtime and manifest, **Force Simulated Runtime** switch, tracking origin (eyeLevel / floorLevel / stage) and stereo mode choice. |
| **Plugins → OpenXR → About OpenXR Support** | opens the **OpenXR** panel | Version and summary (the panel's collapsed About section). |
| Status bar (right) | **XR** button | Shows the active runtime live (`XR (Sim)` or `XR: <runtime>`; green with a dot while the VR preview runs); a click opens a menu with Check Runtime, Toggle VR Preview and OpenXR Settings. |
| **OpenXR** panel (right dock) | editor panel Widget Blueprint | Runtime, manifest and kind; Force Simulated Runtime; tracking origin and stereo mode; session state and a Start / Stop VR Preview button; About (collapsed). It follows every change, whichever menu, button or MCP client made it. |
| MCP | `lumina_plugin_openxr.get_status` (read-only) | Returns `active_runtime`, `manifest_path`, `is_simulated`, `simulation_forced`, `native_runtime_available`, `session_state`, `tracking_origin`, `stereo_mode`, `vr_preview_active`. |

The MCP tool is reachable from any MCP client connected to Lumina Studio's built-in MCP server.

### The OpenXR panel is an asset

The panel is `content/Editor/EPW_OpenXR.lmas`, an editor panel Widget Blueprint (a Widget Blueprint with an
`editorPanel` block: title *OpenXR*, icon `glasses`, dock `right`, menu path `Plugins/OpenXR/OpenXR Panel`, capability
`process` only). No Dart builds it: the editor finds it in the enabled plugin's `content/`, compiles its graph into
its Blueprint VM and docks it, with no editor build. It is laid out with the editor widget set (four Editor Sections:
Active Runtime, Tracking & Stereoscopic, VR Preview, About OpenXR Support collapsed), and its graph does:

| Event | What the graph does |
|---|---|
| Construct | Enables the inputs when the process runs, then `Call Plugin Process ("status")` and fills every element from the answer. |
| On Value Changed (ForceSimulation) | `setForceSimulation {value}` |
| On Selection Changed (TrackingOrigin / StereoMode) | `setTrackingOrigin` / `setStereoMode {value}` for the user's picks (a selection the graph sets itself is ignored). |
| On Clicked (TogglePreview) | `toggleVrPreview` |
| Failed (any call) | a toast with the error. |
| On Plugin Process Event (`openxr.status`) | fills every element from the event's status: the button reads Start or Stop VR Preview, primary or destructive. |
| On Plugin Process State Changed | disables the inputs while the process is not running, refreshes when it runs again. |

The process keeps the status texts (`RuntimeName`, `ManifestPath`, `RuntimeKind`, `SessionState`) current itself:
on every change it patches them in every open instance (`PluginProcessContext.patchPanel`, no graph run) and emits
`openxr.status`. The asset path is the panel's address there, so it lives in one constant, `OpenXrPanel.asset`.

To change the panel, open the plugin from its folder (a user or project plugin being developed) and edit
`EPW_OpenXR.lmas` in the Widget Blueprint designer: the Editor palette section, Class Settings ▸ Editor Panel and
the editor-scope graph palette are there; **Run as Editor Panel** reloads it docked, and saving reloads an open panel
in place. Keep the element names the process patches (`OpenXrPanel.patchedElements`); `test/editor_panel_asset_test.dart`
checks them, the panel block, and that the graph calls only methods the process answers.

## Runs in its own process

The manifest says `"isolation": "process"`: Lumina Studio starts the plugin in a separate process of its own
executable and talks to it over a local connection, so a crash or a hang in an OpenXR runtime or the native bridge
cannot take the editor down.

| Where | What runs there |
|---|---|
| Plugin process (`LuminaPluginOpenxrProcess`, the module's `process_class`) | `OpenXrController` (the plugin's state and actions, pure Dart) registered directly through `PluginProcessContext`: the OpenXR loader bridge (`dart:ffi`), `OpenXrBindings`, the session, every menu and status bar command, the `get_status` MCP tool, the methods the OpenXR panel calls (`status`, `setForceSimulation`, `setTrackingOrigin`, `setStereoMode`, `toggleVrPreview`, each answering the status JSON), its `openxr.status` event and status-text patches, Output Log lines. Caught native errors reported through `LuminaPluginCrashReporter` go to the editor's log under the plugin's name (the plugin process runtime forwards them). |
| Editor | No code of OpenXR: the module names only a `process_class` and no `registration_class`, so the plugin has no in-editor part (and the Plugin Manager offers no in-process override for it) and the editor never opens the bridge. The editor draws the menu items and the status bar button from what the process sent, and runs the OpenXR panel's graph in its Blueprint VM. Editor code that needs the state calls the plugin's process channel: `call('status')` answers the `get_status` JSON. |

When the process stops (a crash, or no answer to three health checks in a row), the editor restarts it a few times,
then marks the plugin stopped: its menu items are greyed out, the OpenXR panel's inputs are disabled, the plugin's
**Restart** button appears, the Plugin Manager shows the status, the exit code and the log tail, and a plugin crash report is filed. The
editor and the open level keep running. A restart begins with a fresh session (the VR preview is off).

Debugging: the process part is a plain Dart program, so it runs on its own with a debugger attached:
`dart run bin/openxr_process.dart --lumina-plugin-process lumina_plugin_openxr --lumina-plugin-port <port> ...`
(what the editor's tests start; without the native bridge on the library path it uses the simulated runtime). With
no `registration_class` the plugin cannot be forced into the editor process.

## Working without a headset

Nothing in the plugin requires hardware. Without a registered runtime (or with **Force Simulated Runtime** on)
`OpenXrBindings` routes everything to `SimulatedOpenXrBackend`: sessions begin and reach `focused`, the head and
controllers have plausible poses, and inputs and haptics can be scripted from tests or tools.
`lumina_plugin_metaxr` adds an editor panel that drives simulated hand gestures on top of this.

### Process part

`LuminaPluginOpenxrProcess` and the libraries it imports (`OpenXrController`, `OpenXrPanel`, `OpenXrBindings`,
the session and the OpenXR types) use only `lumina_plugin_process` (the plugin process API; icons are
`PluginIconSpec` data), `ffi` and `logging` (the loader bridge) and `vector_math`: no Flutter, no `flutter_filament`,
no `lumina_editor_api`. The bridge's `dart:ffi` calls need no Flutter. `OpenXrFilamentBridge` (the Filament stereo
mapping, `flutter_filament`) and the engine
components (`package:lumina`) are outside the process part. `test/architecture/process_part_reach_test.dart` keeps
it that way. The package itself still depends on Flutter, so a package that imports it (even only `xr_types.dart`)
is Flutter-bound through it.

## Architecture

```
lib/
  lumina_plugin_openxr.dart          public library (exports everything below)
  xr_types.dart                      plain XR types without the native bridge (LuminaXRHand, action state)
  src/process/    LuminaPluginOpenxrProcess (process_class), OpenXrController (state and actions, pure Dart),
                  OpenXrPanel (the panel asset's address, element names, status texts)
  src/ffi/        OpenXrBindings (native bridge + simulator switch), OpenXR types/structs, SimulatedOpenXrBackend
  src/session/    OpenXrSession, OpenXrReferenceSpace, OpenXrSpaceConverter
  src/input/      action set, button/axis/vector2 state, haptics, interaction profile paths
  src/components/ LuminaXROriginActor, LuminaXRHMDComponent, LuminaXRControllerComponent, LuminaXRHand
  src/render/     OpenXrStereoView, OpenXrFilamentBridge, OpenXrSwapchainDescriptor
bin/openxr_process.dart   the process part as a plain Dart program
content/Editor/EPW_OpenXR.lmas   the OpenXR panel (editor panel Widget Blueprint)
tool/pack_plugin.dart   packs the plugin for the Marketplace (with content/)
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

## Frame loop

`xrWaitFrame` blocks, so it never runs on a Dart isolate:

1. **The pacer** (a native thread in the bridge) waits for each frame, locates the eyes in the session's reference space
   for the predicted display time and posts `(predictedDisplayTime, shouldRender, frame)` to the UI isolate through a
   `NativeCallable.listener` (`OpenXrNativePacer`). A frame the runtime does not want rendered is begun and ended empty
   by the pacer itself.
2. **The UI isolate** (`OpenXrFrameLoop`) hands the views to the rig (`LuminaXRWorldDriver` puts this frame's head pose
   on the origin's HMD component), ticks the world with the runtime's delta, and renders.
3. **The renderer** (`OpenXrFilamentRenderer`) runs Filament on the runtime's own Vulkan device (`XR_KHR_vulkan_enable2`;
   the device is created with flutter_filament's device info, a queue for the runtime and one for Filament) and draws
   both eyes in one multiview pass into a 2-layer sRGB swapchain image. Filament's driver thread begins the OpenXR
   frame when it acquires the image and ends it with a projection layer when it releases it, so `xrEndFrame` is
   ordered after the frame's GPU submission without a flush.

```dart
final session = OpenXrSession(backend: OpenXrBindings.instance.native)
  ..vulkanDeviceInfo = openXrFilamentDeviceInfo();
OpenXrFrameLoop? loop;
session.onSessionBegan = () {
  final renderer = OpenXrFilamentRenderer.create(OpenXrBindings.instance.native,
      spaceType: session.referenceSpaceType)!;
  // build the scene in renderer.scene (renderer.engine)
  loop = OpenXrFrameLoop(pacer: OpenXrNativePacer(OpenXrBindings.instance.native), renderer: renderer)..start();
};
session.onSessionEnding = () => loop?.stop();
session.beginSession();
// poll session.pollEvents() from a timer
```

The simulated headset has a pacer of its own (`OpenXrSimulatedPacer`), and `OpenXrFilamentRenderer.onSwapChain` renders
the same way into any swapchain (the desktop smoke uses flutter_filament's `ExternalVulkanOffscreen`).
`example/` is the bring-up app for a headset: turning cubes, the frame statistics logged every 5 s
(`--dart-define=XR_REFRESH_RATE=90` asks for another rate). On a Quest 3S it runs at 72 Hz with about 0.25 ms of
Dart CPU and 0.7 ms of GPU per frame.

## Coordinate systems and units

| | Units | Axes |
|---|---|---|
| OpenXR | metres | right-handed, X right, Y up, −Z forward |
| Lumina (stored transforms) | centimetres (one world unit = 1 cm) | Z up |

Lumina's runtime has OpenXR's axes (Y up, −Z forward, +X right) in centimetres, so
`OpenXrSpaceConverter.openXrToRuntimePosition` only scales by 100 and `openXrToRuntimeRotation` keeps the rotation;
the HMD and controller components use these. Stored (authoring) transforms are Z up and go through `LuminaAxes`:
`openXrToLuminaPosition` gives the authoring location `(x, −z, y) × 100` (forward +Y, up +Z), `luminaToOpenXrPosition`
the way back, and `openXrToLuminaRotation` the same change of basis for orientations. The simulator and the stereo
maths stay in OpenXR metres, as the runtime reports them.

## Testing

Unit tests run on the simulated backend and need no headset or GPU:

```bash
flutter test test/architecture/process_part_reach_test.dart
flutter test test/openxr_loader_and_types_test.dart
flutter test test/openxr_session_and_spaces_test.dart
flutter test test/openxr_stereo_render_test.dart
flutter test test/xr_components_test.dart
flutter test test/openxr_plugin_process_test.dart
flutter test test/editor_panel_asset_test.dart
flutter test test/architecture/no_legacy_ui_test.dart
flutter test test/pack_plugin_test.dart
flutter test test/xr_types_library_test.dart
flutter test test/openxr_session_state_machine_test.dart
flutter test test/openxr_stereo_view_test.dart
flutter test test/openxr_space_converter_test.dart
flutter test test/runtime_import_graph_test.dart
flutter test test/hook_android_test.dart
flutter test test/openxr_frame_loop_test.dart
flutter test test/openxr_eye_camera_test.dart
flutter test test/xr_world_driver_test.dart
flutter test test/openxr_multiview_choice_test.dart
dart run tool/smoke_report.dart test/smoke/openxr_frame_loop_smoke_test.dart --no-dashboard
flutter analyze
```

They cover the result codes and struct layouts, the simulation fallback, session states and tracking origins, the
coordinate conversion, input states, the projection matrix (finite values), the Filament stereo mapping, the
origin actor's components.
`openxr_plugin_process_test.dart` runs the process part with `runPluginProcessMain` against `LoopbackHost` (the
editor's side over a real loopback socket): the contributions, the status button's live state and menu, the menu
check mark, the panel's methods (`bad_arguments` for a bad value), the `openxr.status` event and the status-text
patches, the commands opening the editor panel, the MCP tool, errors answered without ending the process, crash
reports in the editor log and a clean shutdown. `editor_panel_asset_test.dart` reads `EPW_OpenXR.lmas` (the panel
block, the elements the process patches, the options and labels, the graph against the process's methods);
`no_legacy_ui_test.dart` keeps `lib/` free of an in-editor part; `pack_plugin_test.dart` packs a copy and finds the
panel in the zip. Lumina Studio's `test/ui/editor_panels/openxr_editor_panel_test.dart` runs this checkout as a user
plugin with its real process (set `LUMINA_OPENXR_DIR` when it is not `../openxr`).

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

- Only the multiview layout renders; the per-eye fallback (two swapchains, two views) is chosen by
  `OpenXrStereoLayout` but not drawn yet. The Quest 3S has multiview.
- A requested refresh rate (`requestDisplayRefreshRate(90)`) was accepted but the Quest stayed at 72 Hz while nobody
  wore it.
- `OpenXrActionSet.sync()` does not read the runtime yet; controller states are filled by the caller.
  `playHapticPulse` records the request (`lastHapticPulse`) without sending it to a device.
- The stereo mode chosen in the OpenXR panel is not yet pushed to the plugin's `OpenXrFilamentBridge`.
- No PC runtime was available while the native path was built; the desktop bridge compiles and finds a runtime the
  same way, but has only run on the Quest.

Planned next: action bindings per interaction profile with real haptics, then passthrough.

## Contributing

Issues and pull requests are welcome. Keep the analyzer clean (`flutter analyze`), add a unit test for new
behaviour (tests use the simulated backend; no mocks of the engine), and keep both READMEs in step (English and
Turkish). The plugin's UI is its editor panel Widget Blueprint: change it in the designer, not in Dart.

## License

MIT — see [LICENSE](LICENSE).

This repository contains no third-party source or binaries. At run time it loads the OpenXR loader and runtime
already installed on the machine (the Khronos OpenXR loader is Apache-2.0; runtimes have their own licences).
OpenXR™ is a trademark of The Khronos Group Inc.
