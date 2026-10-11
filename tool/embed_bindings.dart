// Embeds lib/src/input/bindings.json into lib/src/input/openxr_default_bindings.g.dart,
// so a game reads the default bindings without a file or an asset bundle.
// Run from the package root after editing bindings.json:
//   dart run tool/embed_bindings.dart
// test/openxr_bindings_test.dart fails while the two differ.
import 'dart:io';

const jsonPath = 'lib/src/input/bindings.json';
const dartPath = 'lib/src/input/openxr_default_bindings.g.dart';

String render(String json) => '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// lib/src/input/bindings.json, embedded by tool/embed_bindings.dart.

/// The default action set and bindings (`lib/src/input/bindings.json`).
const String openXrDefaultBindingsJson = r\'\'\'
${json.replaceAll('\r\n', '\n').trimRight()}
\'\'\';
''';

void main() {
  final json = File(jsonPath).readAsStringSync();
  File(dartPath).writeAsStringSync(render(json));
  stdout.writeln('wrote $dartPath');
}
