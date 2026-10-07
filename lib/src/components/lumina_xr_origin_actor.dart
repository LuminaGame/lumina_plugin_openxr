import 'package:lumina/lumina.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_controller_component.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hmd_component.dart';

/// Root XR Player Tracking Origin Actor representing the VR play space in the Lumina world.
class LuminaXROriginActor extends LuminaActor {
  OpenXrTrackingOrigin trackingOrigin;

  late final LuminaXRHMDComponent hmdComponent;
  late final LuminaXRControllerComponent leftController;
  late final LuminaXRControllerComponent rightController;

  LuminaXROriginActor({
    super.key,
    super.location,
    super.rotation,
    this.trackingOrigin = OpenXrTrackingOrigin.floorLevel,
  }) {
    hmdComponent = LuminaXRHMDComponent();
    leftController = LuminaXRControllerComponent(hand: LuminaXRHand.left);
    rightController = LuminaXRControllerComponent(hand: LuminaXRHand.right);

    addComponent(hmdComponent);
    addComponent(leftController);
    addComponent(rightController);

    hmdComponent.attachToComponent(rootComponent);
    leftController.attachToComponent(rootComponent);
    rightController.attachToComponent(rootComponent);
  }

  /// Recalibrates origin space to recenter the head to the current position.
  void recenter() {
    hmdComponent.location.setZero();
    hmdComponent.rotation = Quaternion.identity();
  }
}
