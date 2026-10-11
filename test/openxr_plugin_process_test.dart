import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:lumina_editor_api/testing.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

const _name = 'lumina_plugin_openxr';

/// The OpenXR plugin's process part over a real loopback connection: the
/// editor side is [LoopbackHost], the process side is
/// [runPluginProcessMain] with [LuminaPluginOpenxrProcess].
void main() {
  late LoopbackHost host;
  late LuminaPluginOpenxrProcess process;
  late Future<int> exit;

  setUp(() async {
    OpenXrBindings.instance.setForceSimulation(false);
    host = await LoopbackHost.start();
    process = LuminaPluginOpenxrProcess();
    exit = runPluginProcessMain(host.launch(_name), process);
  });

  tearDown(() async {
    OpenXrBindings.instance.setForceSimulation(false);
    await host.close();
  });

  /// The contributions, once the process has seen the editor accept them.
  Future<PluginContributions> ready() async {
    final c = await host.contributions;
    await host.call(PluginMethods.ping);
    return c;
  }

  Future<void> shutdown() async {
    await host.call(PluginMethods.shutdown);
    expect(await exit, PluginProcessExitCodes.ok);
  }

  /// The next `openxr.status` event's data matching [where].
  Future<Map<String, Object?>> nextStatus([bool Function(Map<String, Object?> status)? where]) async {
    final n = await host.next(PluginMethods.event,
        where: (a) => a['name'] == OpenXrPanel.statusEvent && (where == null || where((a['data'] as Map).cast())));
    return (n['data'] as Map).cast<String, Object?>();
  }

  /// The next patch of the OpenXR panel setting [element]'s text to one
  /// [text] matches.
  Future<PluginPanelStatePatch> nextPatch(String element, Matcher text) async {
    final n = await host.next(PluginMethods.panelState, where: (a) {
      final p = PluginPanelStatePatch.fromJson(a);
      return p != null &&
          p.panel == OpenXrPanel.asset &&
          p.ops.any((o) => o.element == element && text.matches(o.set['text'], {}));
    });
    return PluginPanelStatePatch.fromJson(n)!;
  }

  Future<String> codeOf(Future<Object?> f) async {
    try {
      await f;
    } on PluginRemoteError catch (e) {
      return e.code;
    }
    return 'no error';
  }

  test('menus, the live status button with its menu, the MCP tool and the OpenXR panel arrive', () async {
    final c = await ready();

    expect([for (final m in c.menuItems) m.path], [
      'Plugins/OpenXR/Check Runtime',
      'Plugins/OpenXR/Toggle VR Preview',
      'Plugins/OpenXR/OpenXR Settings',
      'Plugins/OpenXR/About OpenXR Support',
    ]);
    final toggle = c.menuItems.firstWhere((m) => m.path.endsWith('Toggle VR Preview'));
    expect(toggle.checked, isFalse);
    expect(toggle.section, 'run');

    final button = c.slotButtons.single;
    expect((button.id, button.slot), ('openxr.status_badge', 'statusBarRight'));
    expect(button.state.label, isNotNull);
    expect(button.state.active, isFalse);
    expect(button.state.tooltip, startsWith('OpenXR runtime: ${OpenXrBindings.instance.activeRuntimeName}'));
    expect([for (final m in button.menu!) m.label], ['Check OpenXR Runtime', 'Toggle VR Preview', 'OpenXR Settings']);

    expect(c.mcpTools.single.name, 'get_status');
    expect(c.mcpTools.single.risk, 'readOnly');

    // The panel is plugin content (an editor panel Widget Blueprint), not a
    // declarative view of the process.
    expect(c.panels, isEmpty);

    await shutdown();
  });

  test('Toggle VR Preview runs in the process: button state, check mark, panel and log follow', () async {
    await ready();
    expect(await host.call(PluginMethods.canExecute, {'commandId': 'tools.lumina_plugin_openxr.togglePreview'}), isTrue);

    await host.call(PluginMethods.command, {'commandId': 'tools.lumina_plugin_openxr.togglePreview'});
    expect(process.openxr.isVrPreviewActive, isTrue);
    expect(process.openxr.session.state, OpenXrSessionState.focused);

    final state = (await host.next(PluginMethods.slotState, where: (a) => (a['state'] as Map)['active'] == true));
    expect(state['id'], 'openxr.status_badge');
    expect((state['state'] as Map)['tone'], 'success');
    expect((state['state'] as Map)['badge'], '●');
    expect(await host.next(PluginMethods.menuChecked),
        {'path': 'Plugins/OpenXR/Toggle VR Preview', 'checked': true});
    final status = await nextStatus((s) => s['vr_preview_active'] == true);
    expect(status['session_state'], 'focused');
    final patch = await nextPatch(OpenXrPanel.sessionState, equals('Session: focused (preview running)'));
    expect([for (final o in patch.ops) o.element], OpenXrPanel.patchedElements.keys);
    final log = await host.next(PluginMethods.log, where: (a) => '${a['message']}'.startsWith('VR Preview'));
    expect(log['message'], 'VR Preview started (${OpenXrBindings.instance.activeRuntimeName})');
    expect(log['source'], 'OpenXR');

    // The status button's menu entry toggles it back.
    await host.call(PluginMethods.command, {'commandId': 'tools.lumina_plugin_openxr.statusMenu.togglePreview'});
    expect(process.openxr.isVrPreviewActive, isFalse);
    expect(await host.next(PluginMethods.menuChecked),
        {'path': 'Plugins/OpenXR/Toggle VR Preview', 'checked': false});
    final off = await host.next(PluginMethods.slotState, where: (a) => (a['state'] as Map)['active'] == false);
    expect((off['state'] as Map).containsKey('badge') ? (off['state'] as Map)['badge'] : null, isNull);

    await shutdown();
  });

  test('commands that would open a dialog open the OpenXR editor panel', () async {
    await ready();
    for (final id in [
      'tools.lumina_plugin_openxr.checkRuntime',
      'tools.lumina_plugin_openxr.settings',
      'tools.lumina_plugin_openxr.about',
      'tools.lumina_plugin_openxr.statusBadgeClick',
      'tools.lumina_plugin_openxr.statusMenu.checkRuntime',
      'tools.lumina_plugin_openxr.statusMenu.settings',
    ]) {
      await host.call(PluginMethods.command, {'commandId': id});
    }
    // openEditorPanel is sent without waiting; a ping orders it before the check.
    await host.call(PluginMethods.ping);
    final opens = [for (final r in host.requests) if (r.$1 == PluginMethods.panels) r.$2];
    expect(opens, List.filled(6, {'op': 'openEditorPanel', 'panelId': 'content/Editor/EPW_OpenXR.lmas'}));

    await shutdown();
  });

  test("the panel's methods change the runtime choice, tracking origin and stereo mode", () async {
    await ready();

    final forced = await host.channel.call('setForceSimulation', {'value': true}) as Map;
    expect(OpenXrBindings.instance.isSimulationForced, isTrue);
    expect(forced['simulation_forced'], isTrue);
    expect(forced['active_runtime'], 'Lumina Simulated HMD');
    final texts = {
      for (final o in (await nextPatch(OpenXrPanel.runtimeName, equals('Runtime: Lumina Simulated HMD'))).ops) o.element: o.set['text'],
    };
    expect(texts[OpenXrPanel.manifestPath], 'Manifest: internal://simulated');
    expect(texts[OpenXrPanel.runtimeKind], startsWith(OpenXrBindings.instance.isNativeRuntimeAvailable ? 'Simulated HMD (forced' : 'No physical'));
    // The status button shows the simulated runtime (sent as host.slotState
    // when that differs from what the editor shows).
    final sim = process.openxr.statusButtonState.value;
    expect((sim.label, sim.tooltip), ('XR (Sim)', 'OpenXR runtime: Lumina Simulated HMD (simulated)'));

    // setTrackingOrigin {"value":"stage"}: the session's origin, and an
    // openxr.status event carrying it.
    final staged = await host.channel.call('setTrackingOrigin', {'value': 'stage'}) as Map;
    expect(process.openxr.session.trackingOrigin, OpenXrTrackingOrigin.stage);
    expect(staged['tracking_origin'], 'stage');
    expect((await nextStatus((s) => s['tracking_origin'] == 'stage'))['simulation_forced'], isTrue);

    await host.channel.call('setStereoMode', {'value': 'multiview'});
    expect(process.openxr.stereoMode, OpenXrStereoMode.multiview);
    await nextStatus((s) => s['stereo_mode'] == 'multiview');

    // setStereoMode {"value":"bogus"}: bad_arguments, nothing changes.
    expect(await codeOf(host.channel.call('setStereoMode', {'value': 'bogus'})), PluginErrorCodes.badArguments);
    expect(await codeOf(host.channel.call('setTrackingOrigin', {'value': 3})), PluginErrorCodes.badArguments);
    expect(await codeOf(host.channel.call('setForceSimulation', {})), PluginErrorCodes.badArguments);
    expect(process.openxr.stereoMode, OpenXrStereoMode.multiview);
    expect(process.openxr.session.trackingOrigin, OpenXrTrackingOrigin.stage);

    // toggleVrPreview: the preview runs, the slot button and the menu check
    // mark follow, and the session text is patched.
    final running = await host.channel.call('toggleVrPreview') as Map;
    expect(process.openxr.isVrPreviewActive, isTrue);
    expect(running['vr_preview_active'], isTrue);
    final state = await host.next(PluginMethods.slotState, where: (a) => (a['state'] as Map)['active'] == true);
    expect((state['state'] as Map)['tone'], 'success');
    expect(await host.next(PluginMethods.menuChecked), {'path': 'Plugins/OpenXR/Toggle VR Preview', 'checked': true});
    await nextPatch(OpenXrPanel.sessionState, equals('Session: focused (preview running)'));

    // The MCP tool and the panel's status call report the same state.
    final tool = await host.call(PluginMethods.mcpTool, {'tool': '$_name.get_status', 'arguments': {}}) as Map;
    final status = (tool['structuredContent'] as Map).cast<String, Object?>();
    expect(status, containsPair('active_runtime', 'Lumina Simulated HMD'));
    expect(status, containsPair('is_simulated', true));
    expect(status, containsPair('tracking_origin', 'stage'));
    expect(status, containsPair('stereo_mode', 'multiview'));
    expect(status, containsPair('vr_preview_active', true));
    expect(status, containsPair('session_state', 'focused'));
    expect(await host.channel.call('status'), status);

    await shutdown();
    expect(process.openxr.isVrPreviewActive, isFalse, reason: 'shutdown ends the session');
  });

  test('bad requests answer an error and the process keeps serving', () async {
    await ready();
    expect(await codeOf(host.call(PluginMethods.command, {'commandId': 'tools.lumina_plugin_openxr.nope'})),
        PluginErrorCodes.badArguments);
    expect(await codeOf(host.channel.call('nope')), PluginErrorCodes.unknownMethod);
    expect(
      await codeOf(host.call(PluginMethods.viewEvent, {'viewId': 'other', 'controlId': 'x', 'kind': 'pressed'})),
      PluginErrorCodes.badArguments,
    );
    expect(await codeOf(host.call(PluginMethods.mcpTool, {'tool': 'missing', 'arguments': {}})),
        PluginErrorCodes.badArguments);

    // Still serving.
    expect(await host.call(PluginMethods.ping), isA<Map<Object?, Object?>>());
    expect((await host.channel.call('status') as Map)['vr_preview_active'], isFalse);
    expect(host.channel.state.value.status, PluginProcessStatus.running);

    await shutdown();
  });

  test('the process reports the plugin\'s caught native errors to the editor log', () async {
    await ready();
    LuminaPluginCrashReporter.reportCrash(StateError('xrCreateInstance failed'), StackTrace.current,
        plugin: _name, context: 'initialize: openxr_bridge_initialize');
    final log = await host.next(PluginMethods.log, where: (a) => a['level'] == 'error');
    expect(log['source'], _name);
    expect(log['message'],
        startsWith('crash report (while initialize: openxr_bridge_initialize): Bad state: xrCreateInstance failed'));

    await shutdown();
    expect(LuminaPluginCrashReporter.hasHandler, isFalse, reason: 'the handler is removed on shutdown');
  });
}
