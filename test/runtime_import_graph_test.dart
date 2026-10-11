import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `runtime.dart` is what a game imports: nothing it reaches may pull the
/// editor in (the editor API, the plugin-process runtime or its protocol).
void main() {
  test('runtime.dart reaches no editor, plugin-process or protocol library', () {
    const forbidden = [
      'package:lumina_editor_api/',
      'package:lumina_plugin_process/',
      'package:lumina_plugin_protocol/',
    ];
    const self = 'package:lumina_plugin_openxr/';
    final directive = RegExp(r"""^(?:import|export)\s+'([^']+)'""", multiLine: true);
    final seen = <String>{};
    final offenders = <String>[];
    final queue = ['lib/runtime.dart'];
    while (queue.isNotEmpty) {
      final path = queue.removeLast();
      if (!seen.add(path)) continue;
      for (final m in directive.allMatches(File(path).readAsStringSync())) {
        final uri = m.group(1)!;
        if (forbidden.any(uri.startsWith)) offenders.add('$path -> $uri');
        if (uri.startsWith(self)) queue.add('lib/${uri.substring(self.length)}');
      }
    }
    expect(offenders, isEmpty);
    expect(seen.length, greaterThan(10), reason: 'the walk found the runtime library');
  });
}
