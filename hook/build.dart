import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final builder = CBuilder.library(
      name: 'openxr_bridge',
      assetName: 'openxr_bridge.dart',
      sources: ['src/openxr_bridge_c.cpp'],
      includes: ['src'],
      flags: [
        if (input.config.code.targetOS == OS.windows) ...[
          '/std:c++17',
          '/EHsc',
          'Advapi32.lib',
        ] else ...[
          '-std=c++17',
          '-fPIC',
          '-ldl',
        ],
      ],
    );

    await builder.run(input: input, output: output);
  });
}
