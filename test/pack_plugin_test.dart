import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// `tool/pack_plugin.dart` on a temp copy of this plugin's tracked files: the
/// Marketplace zip carries the OpenXR panel asset (the plugin's content) and
/// a manifest that may contain content.
void main() {
  late Directory temp;
  late Directory copy;
  final pluginRoot = Directory.current; // flutter test runs in the package root

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('openxr_pack_test_');
    copy = Directory('${temp.path}/lumina_plugin_openxr')..createSync();
    final tracked = await Process.run('git', ['ls-files', '-z'], workingDirectory: pluginRoot.path);
    expect(tracked.exitCode, 0, reason: '${tracked.stderr}');
    for (final rel in '${tracked.stdout}'.split('\u0000').where((r) => r.isNotEmpty)) {
      final source = File('${pluginRoot.path}/$rel');
      if (!source.existsSync()) continue;
      File('${copy.path}/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(source.readAsBytesSync());
    }
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('the packed .lmplugin zip contains content/Editor/EPW_OpenXR.lmas and can_contain_content', () async {
    final out = Directory('${temp.path}/out');
    final r = await Process.run('dart', ['tool/pack_plugin.dart', copy.path, '--out', out.path],
        workingDirectory: pluginRoot.path, runInShell: Platform.isWindows);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final zip = File('${out.path}/lumina_plugin_openxr-0.1.0.zip');
    expect(zip.existsSync(), isTrue, reason: '${r.stdout}');
    final entries = {for (final e in ZipDecoder().decodeBytes(zip.readAsBytesSync(), verify: true)) if (e.isFile) e.name: e};
    expect(entries.keys, contains('lumina_plugin_openxr/content/Editor/EPW_OpenXR.lmas'));
    expect(entries['lumina_plugin_openxr/content/Editor/EPW_OpenXR.lmas']!.readBytes(),
        File('${pluginRoot.path}/content/Editor/EPW_OpenXR.lmas').readAsBytesSync());
    final manifest =
        jsonDecode(utf8.decode(entries['lumina_plugin_openxr/lumina_plugin_openxr.lmplugin']!.readBytes()!)) as Map<String, dynamic>;
    expect(manifest['can_contain_content'], isTrue);
    expect(entries.keys.where((k) => k.contains('/lib/src/ui/')), isEmpty);
  });
}
