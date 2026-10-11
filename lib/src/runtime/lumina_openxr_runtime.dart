import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:lumina_widgets/lumina_widgets.dart' show LuminaGameHost;

import 'package:lumina_plugin_openxr/src/input/openxr_blueprint_nodes.dart';
import 'package:lumina_plugin_openxr/src/runtime/openxr_game_presenter.dart';

/// The plugin's runtime module (`.lmplugin` `"type": "runtime"`): a game
/// with the plugin enabled calls [register] from its generated `main()`,
/// before the game starts.
abstract final class LuminaOpenXrRuntime {
  /// The project settings the game registered with: `project_name` and
  /// its Android settings (`xr`, `refresh_rate`, `multiview`, ...).
  static Map<String, Object?> settings = const {};

  static bool _registered = false;

  /// Whether [register] ran.
  static bool get isRegistered => _registered;

  /// The XR profile the game was built with (`quest` or `none`).
  static String get xrProfile => settings['xr'] as String? ?? 'none';

  /// The display refresh rate an immersive session asks for (Hz).
  static int get refreshRate => (settings['refresh_rate'] as num?)?.toInt() ?? 72;

  /// Whether both eyes render in one pass.
  static bool get multiview => settings['multiview'] as bool? ?? true;

  /// Whether this build presents immersive: the Meta Quest profile on
  /// Android (a headset build).
  static bool get immersive => !kIsWeb && Platform.isAndroid && xrProfile == 'quest';

  /// Registers the XR Blueprint nodes and, on a headset build, makes the
  /// game host present the game in the headset ([OpenXrGamePresenter]);
  /// idempotent.
  static void register([Map<String, Object?> settings = const {}]) {
    LuminaOpenXrRuntime.settings = Map.unmodifiable(settings);
    if (immersive) {
      LuminaGameHost.immersivePresenter =
          (game, {required levelName}) => OpenXrGamePresenter(game: game, levelName: levelName, refreshRate: refreshRate, multiview: multiview);
    }
    if (_registered) return;
    _registered = true;
    OpenXrBlueprintNodes.register();
  }
}
