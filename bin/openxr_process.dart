// The OpenXR plugin's process part as a plain Dart program (no Flutter): what
// the editor runs for this plugin, started here directly, for development
// and for the editor's tests with the real process.
//
//   dart run bin/openxr_process.dart --lumina-plugin-process lumina_plugin_openxr \
//     --lumina-plugin-port <port> --lumina-plugin-token <token>
//
// Without the native loader bridge on the library path it runs the simulated
// OpenXR runtime.
import 'dart:io';

import 'package:lumina_plugin_openxr/src/process/lumina_plugin_openxr_process.dart';
import 'package:lumina_plugin_process/lumina_plugin_process.dart';

Future<void> main(List<String> args) async {
  final launch = PluginProcessLaunch.parse(args);
  if (launch == null) {
    stderr.writeln('usage: dart run bin/openxr_process.dart ${PluginProcessLaunch.flag} lumina_plugin_openxr ...');
    exit(64);
  }
  exit(await runPluginProcessMain(launch, LuminaPluginOpenxrProcess()));
}
