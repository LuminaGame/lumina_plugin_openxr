import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_stereo_view.dart';

/// One eye's camera for a frame: its model matrix (the eye pose in world
/// units, the tracking origin at [origin]) and its asymmetric projection.
class OpenXrEyeCamera {
  const OpenXrEyeCamera({required this.model, required this.projection});

  final vm.Matrix4 model;
  final vm.Matrix4 projection;

  /// The eye cameras of [views] (OpenXR metres): positions scaled by
  /// [unitsPerMetre] (100 for Lumina's centimetres, 1 for metres) and placed
  /// relative to [origin] (the XR origin in world space, identity by default).
  static List<OpenXrEyeCamera> fromViews(List<OpenXrEyeView> views,
      {double unitsPerMetre = 1, vm.Matrix4? origin, double near = 0.05, double far = 1000}) {
    return [
      for (final v in views)
        OpenXrEyeCamera(
          model: (origin ?? vm.Matrix4.identity())
              .multiplied(vm.Matrix4.compose(v.position * unitsPerMetre, v.orientation.normalized(), vm.Vector3.all(1))),
          projection: OpenXrStereoView(
            eyePosition: v.position,
            eyeOrientation: v.orientation,
            angleLeft: v.angleLeft,
            angleRight: v.angleRight,
            angleUp: v.angleUp,
            angleDown: v.angleDown,
          ).createProjectionMatrix(nearPlane: near, farPlane: far),
        ),
    ];
  }

  /// The head of [views] (world units): midway between the eyes, oriented
  /// like the first. The camera sits there, so Filament culls from the head
  /// (with [cullingProjection]) and each eye's model matrix is relative to it
  /// ([relativeTo]).
  static vm.Matrix4 head(List<OpenXrEyeView> views, {double unitsPerMetre = 1}) {
    if (views.isEmpty) return vm.Matrix4.identity();
    final centre = views.fold(vm.Vector3.zero(), (vm.Vector3 a, v) => a + v.position) / views.length.toDouble();
    return vm.Matrix4.compose(centre * unitsPerMetre, views.first.orientation.normalized(), vm.Vector3.all(1));
  }

  /// [eye] (a model matrix in the tracking space) relative to [head].
  static vm.Matrix4 relativeTo(vm.Matrix4 head, vm.Matrix4 eye) => vm.Matrix4.inverted(head).multiplied(eye);

  /// A projection enclosing every eye's frustum (for culling both eyes in one
  /// pass): the widest angle on each side.
  static vm.Matrix4 cullingProjection(List<OpenXrEyeView> views, {double near = 0.05, double far = 1000}) {
    if (views.isEmpty) return vm.Matrix4.identity();
    return OpenXrStereoView(
      eyePosition: vm.Vector3.zero(),
      eyeOrientation: vm.Quaternion.identity(),
      angleLeft: views.map((v) => v.angleLeft).reduce(math.min),
      angleRight: views.map((v) => v.angleRight).reduce(math.max),
      angleUp: views.map((v) => v.angleUp).reduce(math.max),
      angleDown: views.map((v) => v.angleDown).reduce(math.min),
    ).createProjectionMatrix(nearPlane: near, farPlane: far);
  }
}
