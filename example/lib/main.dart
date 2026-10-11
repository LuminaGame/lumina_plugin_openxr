import 'dart:async';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

/// Bring-up of the native OpenXR path on a headset: instance, system, the
/// Vulkan device Filament will adopt, the session following the runtime's
/// events, the frame loop on its pacer thread, and the eyes located on
/// LOCAL_FLOOR. Everything is logged (`[openxr_example]` lines; the bridge
/// logs under the logcat tag LuminaOpenXR).
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OpenXrErrorReporter.handler = (error, stack, where) => debugPrint('[openxr_example] $where failed: $error');
  runApp(const OpenXrExampleApp());
}

class OpenXrExampleApp extends StatefulWidget {
  const OpenXrExampleApp({super.key});

  @override
  State<OpenXrExampleApp> createState() => _OpenXrExampleAppState();
}

class _OpenXrExampleAppState extends State<OpenXrExampleApp> {
  final _native = OpenXrBindings.instance.native;
  late final OpenXrSession _session = OpenXrSession(backend: _native)..vulkanDeviceInfo = openXrFilamentDeviceInfo();
  NativeCallable<OpenXrFrameCallbackNative>? _onFrame;
  Timer? _poll;
  final _lines = <String>[];
  int _frames = 0;
  int _lastReport = 0;

  void _log(String line) {
    debugPrint('[openxr_example] $line');
    if (mounted) setState(() => _lines.add(line));
  }

  @override
  void initState() {
    super.initState();
    _session
      ..onSessionBegan = _startFrameLoop
      ..onSessionEnding = _stopFrameLoop
      ..onExitRequested = () => _log('the runtime asked the app to quit');
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    final r = _session.beginSession();
    if (r.isFailure) {
      _log('beginSession failed: ${r.name} (${_native.lastError})');
      return;
    }
    _log('runtime ${_native.runtimeName}, system "${_native.systemName}"');
    for (final (i, v) in _native.viewConfigurations.indexed) {
      _log('view $i: recommended ${v.recommendedWidth}x${v.recommendedHeight}, max ${v.maxWidth}x${v.maxHeight}');
    }
    _log('blend modes: ${_native.blendModes.map(OpenXrBlendMode.name).join(', ')}');
    _log('Vulkan: ${_native.vulkan}');
    for (final e in ['XR_EXT_local_floor', 'XR_FB_display_refresh_rate', 'XR_FB_passthrough', 'XR_EXT_hand_tracking']) {
      _log('$e: ${_native.extensionEnabled(e)}');
    }
    _poll = Timer.periodic(const Duration(milliseconds: 20), (_) {
      for (final event in _session.pollEvents()) {
        _log('event: $event -> session ${_session.state.name}');
      }
    });
  }

  void _startFrameLoop() {
    _onFrame = NativeCallable<OpenXrFrameCallbackNative>.listener(_frame);
    final r = _native.startFrameLoop(_onFrame, blendMode: OpenXrBlendMode.opaque);
    _log('frame loop started: ${r.name}');
  }

  void _frame(int predictedDisplayTime, int shouldRender, int frame) {
    _frames++;
    if (frame - _lastReport < 144) return;
    _lastReport = frame;
    final stats = _native.frameStats;
    final views = _native.locateViews(_session.referenceSpaceType, predictedDisplayTime);
    final eyes = [
      for (final v in views)
        '(${v.position.x.toStringAsFixed(3)}, ${v.position.y.toStringAsFixed(3)}, ${v.position.z.toStringAsFixed(3)})',
    ];
    _log('frame $frame: period ${(stats.period.inMicroseconds / 1000).toStringAsFixed(2)} ms '
        '(${(1e6 / (stats.period.inMicroseconds == 0 ? 1 : stats.period.inMicroseconds)).toStringAsFixed(1)} Hz), '
        'empty ${stats.empty}, eyes ${eyes.join(' ')}');
  }

  void _stopFrameLoop() {
    _native.stopFrameLoop();
    _onFrame?.close();
    _onFrame = null;
    _log('frame loop stopped after $_frames frames');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _session.endSession();
    _onFrame?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(children: [for (final l in _lines) Text(l, style: const TextStyle(fontSize: 12))]),
        ),
      );
}
