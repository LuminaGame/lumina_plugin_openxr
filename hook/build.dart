import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'openxr_loader.dart';

/// The bridge's sources (src/), the OpenXR and Vulkan headers it compiles
/// against (third_party/, vendored from the Khronos SDKs).
const bridgeSources = [
  'src/openxr_bridge_c.cpp',
  'src/openxr_client_c.cpp',
  'src/openxr_android_c.cpp',
  'src/openxr_frame_c.cpp',
  'src/openxr_swapchain_c.cpp',
];
const bridgeIncludes = ['src', 'third_party/openxr/include', 'third_party/vulkan/include'];

/// The Android ABI directory name of [architecture].
String androidAbi(Architecture architecture) => switch (architecture) {
      Architecture.arm64 => 'arm64-v8a',
      Architecture.x64 => 'x86_64',
      Architecture.arm => 'armeabi-v7a',
      Architecture.ia32 => 'x86',
      final other => throw UnsupportedError('Unsupported Android architecture: $other'),
    };

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final targetOS = input.config.code.targetOS;
    final isWindows = targetOS == OS.windows;
    final isAndroid = targetOS == OS.android;

    final builder = CBuilder.library(
      name: 'openxr_bridge',
      assetName: 'openxr_bridge.dart',
      sources: bridgeSources,
      includes: bridgeIncludes,
      flags: [
        if (isWindows) ...['/std:c++17', '/EHsc', '/utf-8', '/DNOMINMAX'] else ...['-std=c++17', '-fexceptions'],
        // The NDK's static libc++ after the objects that need it (CBuilder's
        // cppLinkStdLib alone leaves operator new and the typeinfo unresolved).
        if (isAndroid) ...['-landroid', '-llog', '-ldl', '-lc++_static', '-lc++abi'],
        if (targetOS == OS.linux) '-ldl',
      ],
      libraries: [if (isWindows) 'Advapi32'],
      cppLinkStdLib: isAndroid ? 'c++_static' : null,
    );
    await builder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => stderr.writeln(record.message)),
    );

    // Android: the Khronos loader travels with the bridge (it finds the runtime through the
    // runtime broker); desktop uses the loader of the installed runtime.
    if (isAndroid) {
      final abi = androidAbi(input.config.code.targetArchitecture);
      final cache = Directory.fromUri(input.outputDirectoryShared.resolve('openxr_loader/'));
      final loader = await ensureOpenXrLoader(cacheDir: cache, abi: abi);
      output.assets.code.add(CodeAsset(
        package: input.packageName,
        name: 'openxr_loader.dart',
        linkMode: DynamicLoadingBundled(),
        file: loader.uri,
      ));
      output.dependencies.add(input.packageRoot.resolve('hook/openxr_loader.dart'));
    }
  });
}
