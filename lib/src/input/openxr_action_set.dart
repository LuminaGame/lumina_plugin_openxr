import 'package:lumina_plugin_openxr/src/input/openxr_action_state.dart';

/// Standard OpenXR Interaction Profiles.
class OpenXrInteractionProfiles {
  static const String khronosSimple = '/interaction_profiles/khr/simple_controller';
  static const String oculusTouch = '/interaction_profiles/oculus/touch_controller';
  static const String valveIndex = '/interaction_profiles/valve/index_controller';
  static const String htcVive = '/interaction_profiles/htc/vive_controller';
  static const String microsoftMotion = '/interaction_profiles/microsoft/motion_controller';
}

/// Collection of OpenXR Actions attached to a session.
class OpenXrActionSet {
  final String name;
  final String localizedName;
  final int priority;

  // Standard controller action states
  final OpenXrAxisState leftTrigger = OpenXrAxisState();
  final OpenXrAxisState rightTrigger = OpenXrAxisState();
  final OpenXrAxisState leftGrip = OpenXrAxisState();
  final OpenXrAxisState rightGrip = OpenXrAxisState();
  final OpenXrVector2State leftThumbstick = OpenXrVector2State();
  final OpenXrVector2State rightThumbstick = OpenXrVector2State();

  final OpenXrButtonState leftPrimary = OpenXrButtonState(); // X button
  final OpenXrButtonState leftSecondary = OpenXrButtonState(); // Y button
  final OpenXrButtonState rightPrimary = OpenXrButtonState(); // A button
  final OpenXrButtonState rightSecondary = OpenXrButtonState(); // B button
  final OpenXrButtonState leftMenu = OpenXrButtonState();
  final OpenXrButtonState rightMenu = OpenXrButtonState();

  OpenXrActionSet({
    this.name = 'gameplay',
    this.localizedName = 'Gameplay Actions',
    this.priority = 0,
  });

  /// Synchronizes actions from simulated or native backend inputs.
  void sync() {
    // Keep action deltas aligned across frame updates
  }
}
