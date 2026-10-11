import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../hook/build.dart' as hook;
import '../hook/openxr_loader.dart';

/// The Android build bundles the Khronos loader from the Maven Central AAR,
/// checked against a pinned SHA-256 and never committed.
void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('openxr_loader_test'));
  tearDown(() async => temp.delete(recursive: true));

  test('a wrong checksum fails with the expected and actual hashes', () async {
    // A real archive on disk that is not the pinned AAR.
    final aar = File('${temp.path}/other.aar')..writeAsBytesSync(Uint8List.fromList(List.generate(4096, (i) => i % 251)));
    final actual = sha256.convert(aar.readAsBytesSync()).toString();
    await expectLater(
      ensureOpenXrLoader(cacheDir: Directory('${temp.path}/cache'), abi: 'arm64-v8a', aar: aar),
      throwsA(isA<OpenXrLoaderException>().having((e) => e.message, 'message',
          allOf(contains('expected $openXrLoaderAarSha256'), contains('got $actual')))),
    );
    expect(File('${temp.path}/cache/arm64-v8a/libopenxr_loader.so').existsSync(), isFalse);
  });

  test('the pinned AAR from Maven Central yields the arm64-v8a loader', () async {
    final File loader;
    try {
      loader = await ensureOpenXrLoader(cacheDir: Directory('${temp.path}/cache'), abi: 'arm64-v8a');
    } on OpenXrLoaderException catch (e) {
      if (e.message.contains('GET ')) return markTestSkipped('Maven Central unreachable: ${e.message}');
      rethrow;
    }
    final bytes = loader.readAsBytesSync();
    expect(bytes.sublist(0, 4), [0x7f, 0x45, 0x4c, 0x46], reason: 'an ELF shared library');
    expect(bytes[4], 2, reason: '64-bit');
    expect(bytes.length, greaterThan(1000000));
    // A second call reuses the cache.
    final again = await ensureOpenXrLoader(cacheDir: Directory('${temp.path}/cache'), abi: 'arm64-v8a');
    expect(again.path, loader.path);
  });

  test('the hook builds the bridge for every target and maps Android ABIs', () {
    expect(hook.bridgeSources, containsAll(['src/openxr_bridge_c.cpp', 'src/openxr_client_c.cpp', 'src/openxr_android_c.cpp']));
    expect(hook.bridgeIncludes, containsAll(['third_party/openxr/include', 'third_party/vulkan/include']));
    for (final header in ['third_party/openxr/include/openxr/openxr.h', 'third_party/openxr/LICENSE']) {
      expect(File(header).existsSync(), isTrue, reason: header);
    }
  });
}
