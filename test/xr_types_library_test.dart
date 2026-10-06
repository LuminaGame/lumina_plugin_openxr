import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/xr_types.dart';

void main() {
  test('the plain XR types library carries the hand and input types', () {
    expect(LuminaXRHand.left.isLeft, isTrue);
    expect(LuminaXRHand.right.isRight, isTrue);
    expect(OpenXrActionType.values, isNotEmpty);
  });

  test('the plain XR types library never reaches dart:ffi or the bindings', () async {
    // Walks the library's relative imports and exports from the package sources.
    final seen = <String>{};
    final pending = ['lib/xr_types.dart'];
    final directive = RegExp(r'''^(?:import|export)\s+'([^']+)';''', multiLine: true);
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!seen.add(path)) continue;
      final source = await File(path).readAsString();
      for (final m in directive.allMatches(source)) {
        final uri = m.group(1)!;
        expect(uri, isNot(anyOf('dart:ffi', startsWith('package:ffi'), contains('openxr_bindings'))), reason: path);
        if (!uri.contains(':')) pending.add(File(path).parent.uri.resolve(uri).toFilePath());
      }
    }
    expect(seen.length, greaterThan(1));
  });
}
