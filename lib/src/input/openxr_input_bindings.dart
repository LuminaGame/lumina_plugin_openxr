import 'dart:convert';

import 'package:lumina_plugin_openxr/src/input/openxr_action_state.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_default_bindings.g.dart';

/// One action of the action set: its name (`grip`, `trigger`, ...), the name
/// the runtime shows, and its type.
class OpenXrActionSpec {
  const OpenXrActionSpec(this.name, this.localizedName, this.type);

  final String name;
  final String localizedName;
  final OpenXrActionType type;

  /// The `XrActionType` value.
  int get xrType => switch (type) {
        OpenXrActionType.booleanInput => 1,
        OpenXrActionType.floatInput => 2,
        OpenXrActionType.vector2Input => 3,
        OpenXrActionType.poseInput => 4,
        OpenXrActionType.vibrationOutput => 100,
      };

  static OpenXrActionType parseType(String name) => switch (name) {
        'boolean' => OpenXrActionType.booleanInput,
        'float' => OpenXrActionType.floatInput,
        'vector2f' => OpenXrActionType.vector2Input,
        'pose' => OpenXrActionType.poseInput,
        'vibration' => OpenXrActionType.vibrationOutput,
        _ => throw FormatException('unknown OpenXR action type "$name"'),
      };
}

/// The suggested bindings for one interaction profile: action name → the
/// input/output paths bound to it (one per hand, or one for a single hand).
class OpenXrProfileBindings {
  const OpenXrProfileBindings(this.path, this.bindings, {this.extension});

  /// `/interaction_profiles/oculus/touch_controller`.
  final String path;

  /// The instance extension the profile needs (`XR_META_touch_controller_plus`),
  /// or null for a core profile.
  final String? extension;

  final Map<String, List<String>> bindings;

  /// The profile path without the `/interaction_profiles/` prefix.
  String get shortName => path.replaceFirst('/interaction_profiles/', '');

  /// Every (action, path) pair, in the action order of [bindings].
  List<({String action, String path})> get pairs => [
        for (final e in bindings.entries)
          for (final p in e.value) (action: e.key, path: p),
      ];

  /// The paths bound to [action] (empty when the profile does not bind it).
  List<String> pathsOf(String action) => bindings[action] ?? const [];
}

/// The action set the plugin creates and the bindings it suggests per
/// interaction profile, read from `lib/src/input/bindings.json` ([defaults]).
class OpenXrInputBindings {
  const OpenXrInputBindings({
    required this.actionSetName,
    required this.localizedName,
    required this.priority,
    required this.actions,
    required this.profiles,
  });

  /// The bindings the plugin ships (`bindings.json`, embedded at build time
  /// by `tool/embed_bindings.dart`).
  static final OpenXrInputBindings defaults = OpenXrInputBindings.parse(openXrDefaultBindingsJson);

  factory OpenXrInputBindings.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final set = json['action_set'] as Map<String, dynamic>;
    return OpenXrInputBindings(
      actionSetName: set['name'] as String,
      localizedName: set['localized_name'] as String? ?? set['name'] as String,
      priority: (set['priority'] as num?)?.toInt() ?? 0,
      actions: [
        for (final a in (json['actions'] as List).cast<Map<String, dynamic>>())
          OpenXrActionSpec(a['name'] as String, a['localized_name'] as String? ?? a['name'] as String,
              OpenXrActionSpec.parseType(a['type'] as String)),
      ],
      profiles: [
        for (final p in (json['profiles'] as List).cast<Map<String, dynamic>>())
          OpenXrProfileBindings(
            p['path'] as String,
            {
              for (final e in (p['bindings'] as Map<String, dynamic>).entries)
                e.key: [for (final path in e.value as List) path as String],
            },
            extension: p['extension'] as String?,
          ),
      ],
    );
  }

  final String actionSetName;
  final String localizedName;
  final int priority;
  final List<OpenXrActionSpec> actions;
  final List<OpenXrProfileBindings> profiles;

  OpenXrActionSpec? action(String name) {
    for (final a in actions) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// The profile [name] names: the full path or the short one
  /// (`meta/touch_controller_plus`).
  OpenXrProfileBindings? profile(String name) {
    for (final p in profiles) {
      if (p.path == name || p.shortName == name) return p;
    }
    return null;
  }

  /// The profiles to suggest: core profiles always, an extension profile
  /// only when [extensionEnabled] says the instance has its extension.
  List<OpenXrProfileBindings> profilesToSuggest(bool Function(String extension) extensionEnabled) => [
        for (final p in profiles)
          if (p.extension == null || extensionEnabled(p.extension!)) p,
      ];

  /// The extensions the extension profiles need (to ask for at instance creation).
  List<String> get extensions => [
        for (final p in profiles)
          if (p.extension != null) p.extension!,
      ];
}
