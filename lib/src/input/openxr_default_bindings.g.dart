// GENERATED CODE - DO NOT MODIFY BY HAND
// lib/src/input/bindings.json, embedded by tool/embed_bindings.dart.

/// The default action set and bindings (`lib/src/input/bindings.json`).
const String openXrDefaultBindingsJson = r'''
{
  "action_set": {"name": "gameplay", "localized_name": "Gameplay", "priority": 0},
  "actions": [
    {"name": "grip_pose", "localized_name": "Grip Pose", "type": "pose"},
    {"name": "aim_pose", "localized_name": "Aim Pose", "type": "pose"},
    {"name": "grip", "localized_name": "Grip", "type": "float"},
    {"name": "trigger", "localized_name": "Trigger", "type": "float"},
    {"name": "trigger_touch", "localized_name": "Trigger Touch", "type": "boolean"},
    {"name": "thumbstick", "localized_name": "Thumbstick", "type": "vector2f"},
    {"name": "thumbstick_click", "localized_name": "Thumbstick Click", "type": "boolean"},
    {"name": "primary", "localized_name": "Primary Button (X / A)", "type": "boolean"},
    {"name": "secondary", "localized_name": "Secondary Button (Y / B)", "type": "boolean"},
    {"name": "menu", "localized_name": "Menu", "type": "boolean"},
    {"name": "haptic", "localized_name": "Haptic", "type": "vibration"}
  ],
  "profiles": [
    {
      "path": "/interaction_profiles/meta/touch_controller_plus",
      "extension": "XR_META_touch_controller_plus",
      "bindings": {
        "grip_pose": ["/user/hand/left/input/grip/pose", "/user/hand/right/input/grip/pose"],
        "aim_pose": ["/user/hand/left/input/aim/pose", "/user/hand/right/input/aim/pose"],
        "grip": ["/user/hand/left/input/squeeze/value", "/user/hand/right/input/squeeze/value"],
        "trigger": ["/user/hand/left/input/trigger/value", "/user/hand/right/input/trigger/value"],
        "trigger_touch": ["/user/hand/left/input/trigger/touch", "/user/hand/right/input/trigger/touch"],
        "thumbstick": ["/user/hand/left/input/thumbstick", "/user/hand/right/input/thumbstick"],
        "thumbstick_click": ["/user/hand/left/input/thumbstick/click", "/user/hand/right/input/thumbstick/click"],
        "primary": ["/user/hand/left/input/x/click", "/user/hand/right/input/a/click"],
        "secondary": ["/user/hand/left/input/y/click", "/user/hand/right/input/b/click"],
        "menu": ["/user/hand/left/input/menu/click"],
        "haptic": ["/user/hand/left/output/haptic", "/user/hand/right/output/haptic"]
      }
    },
    {
      "path": "/interaction_profiles/oculus/touch_controller",
      "bindings": {
        "grip_pose": ["/user/hand/left/input/grip/pose", "/user/hand/right/input/grip/pose"],
        "aim_pose": ["/user/hand/left/input/aim/pose", "/user/hand/right/input/aim/pose"],
        "grip": ["/user/hand/left/input/squeeze/value", "/user/hand/right/input/squeeze/value"],
        "trigger": ["/user/hand/left/input/trigger/value", "/user/hand/right/input/trigger/value"],
        "trigger_touch": ["/user/hand/left/input/trigger/touch", "/user/hand/right/input/trigger/touch"],
        "thumbstick": ["/user/hand/left/input/thumbstick", "/user/hand/right/input/thumbstick"],
        "thumbstick_click": ["/user/hand/left/input/thumbstick/click", "/user/hand/right/input/thumbstick/click"],
        "primary": ["/user/hand/left/input/x/click", "/user/hand/right/input/a/click"],
        "secondary": ["/user/hand/left/input/y/click", "/user/hand/right/input/b/click"],
        "menu": ["/user/hand/left/input/menu/click"],
        "haptic": ["/user/hand/left/output/haptic", "/user/hand/right/output/haptic"]
      }
    },
    {
      "path": "/interaction_profiles/khr/simple_controller",
      "bindings": {
        "grip_pose": ["/user/hand/left/input/grip/pose", "/user/hand/right/input/grip/pose"],
        "aim_pose": ["/user/hand/left/input/aim/pose", "/user/hand/right/input/aim/pose"],
        "trigger": ["/user/hand/left/input/select/click", "/user/hand/right/input/select/click"],
        "menu": ["/user/hand/left/input/menu/click", "/user/hand/right/input/menu/click"],
        "haptic": ["/user/hand/left/output/haptic", "/user/hand/right/output/haptic"]
      }
    }
  ]
}
''';
