/// The interaction profiles the plugin binds (`bindings.json`) and others
/// runtimes report.
abstract final class OpenXrInteractionProfiles {
  /// Meta Quest Touch Plus (Quest 3 / 3S); needs `XR_META_touch_controller_plus`.
  static const String metaTouchControllerPlus = '/interaction_profiles/meta/touch_controller_plus';
  static const String oculusTouch = '/interaction_profiles/oculus/touch_controller';
  static const String khronosSimple = '/interaction_profiles/khr/simple_controller';
  static const String valveIndex = '/interaction_profiles/valve/index_controller';
  static const String htcVive = '/interaction_profiles/htc/vive_controller';
  static const String microsoftMotion = '/interaction_profiles/microsoft/motion_controller';
}
