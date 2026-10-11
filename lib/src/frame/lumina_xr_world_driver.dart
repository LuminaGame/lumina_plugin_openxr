import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_origin_actor.dart';
import 'package:lumina_plugin_openxr/src/frame/openxr_frame_loop.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_filament_renderer.dart';

/// Drives a [LuminaWorld] from the XR frame loop: each frame the XR origin's
/// head (and later the controllers) takes this frame's located pose, then
/// the world ticks with the runtime's delta, then the renderer draws both
/// eyes from the origin's world transform. Gameplay therefore reads current
/// poses in `onTick`, and never calls `updatePoseFromOpenXr` itself.
class LuminaXRWorldDriver {
  LuminaXRWorldDriver({required this.world, required this.origin, this.renderer, this.maxDeltaSeconds = 0.1});

  final LuminaWorld world;
  final LuminaXROriginActor origin;

  /// The renderer whose head follows [origin] (null: tick only).
  final OpenXrFilamentRenderer? renderer;

  /// A delta above this (a pause, a resume) is clamped.
  final double maxDeltaSeconds;

  /// Hooks into [loop]: views → the rig, then the world tick.
  void attach(OpenXrFrameLoop loop) {
    loop
      ..onViews = onViews
      ..onFrame = onFrame;
  }

  /// The head is the midpoint of the eyes, oriented like the first eye.
  void onViews(OpenXrFrame frame, List<OpenXrEyeView> views) {
    if (views.length < 2) return;
    final head = (views[0].position + views[1].position) * 0.5;
    origin.hmdComponent.updatePoseFromOpenXr(head, views[0].orientation);
    origin.hmdComponent.interPupillaryDistance = views[0].position.distanceTo(views[1].position);
  }

  void onFrame(double deltaSeconds, OpenXrFrame frame) {
    final dt = deltaSeconds <= 0 ? 0.0 : (deltaSeconds > maxDeltaSeconds ? maxDeltaSeconds : deltaSeconds);
    world.tick(dt);
    final r = renderer;
    if (r != null) {
      r.origin = vm.Matrix4.compose(origin.actorLocation, origin.actorRotation, vm.Vector3.all(1));
    }
  }
}
