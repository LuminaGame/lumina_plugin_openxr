import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The OpenXR plugin has no in-editor part: its panel is the editor panel
/// Widget Blueprint it ships as content, run by the editor's Blueprint VM,
/// and everything else runs in its own process. So `lib/` holds no
/// `LuminaEditorPlugin` subclass and no Flutter UI, the library exports none,
/// and the manifest names no `registration_class` (nothing can force it into
/// the editor process).
void main() {
  final lib = Directory('lib');

  test('lib/ has no LuminaEditorPlugin subclass and no lib/src/ui/', () {
    expect(Directory('lib/src/ui').existsSync(), isFalse);
    final shells = [
      for (final f in lib.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && RegExp(r'extends\s+LuminaEditorPlugin\b').hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(shells, isEmpty);
  });

  test('the library exports neither the settings view nor the dialogs', () {
    final exports = File('lib/lumina_plugin_openxr.dart').readAsStringSync();
    expect(exports, isNot(contains('openxr_settings_view.dart')));
    expect(exports, isNot(contains('openxr_dialogs.dart')));
    expect(exports, isNot(contains('openxr_status_badge.dart')));
    expect(exports, isNot(contains('lumina_plugin_openxr_plugin.dart')));
  });

  test('the manifest names no registration_class and may contain content', () {
    final manifest = jsonDecode(File('lumina_plugin_openxr.lmplugin').readAsStringSync()) as Map<String, dynamic>;
    expect(manifest['can_contain_content'], isTrue);
    expect(manifest['isolation'], 'process');
    for (final m in (manifest['modules'] as List).cast<Map<String, dynamic>>()) {
      expect(m.containsKey('registration_class'), isFalse, reason: '${m['name']}');
      expect(m['process_class'], 'LuminaPluginOpenxrProcess');
    }
  });
}
