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

  Future<Map<String, Object?>> nextView() async {
    final n = await host.next(PluginMethods.view, where: (a) => a['viewId'] == OpenXrStatusView.viewId);
    return (n['spec'] as Map).cast<String, Object?>();
  }

  String? textOf(Map<String, Object?> specJson, String controlId) {
    final spec = PluginViewSpec.fromJson(specJson);
    final c = spec.find(controlId)!;
    return (c['value'] ?? c['text']) as String?;
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

    final panel = c.panels.single;
    expect((panel.id, panel.title, panel.dock), (LuminaPluginOpenxrPlugin.panelId, 'OpenXR', 'right'));
    expect(panel.view.id, OpenXrStatusView.viewId);
    expect(panel.view.find(OpenXrStatusView.runtimeName)!['value'],
        'Runtime: ${OpenXrBindings.instance.activeRuntimeName}');
    expect(panel.view.find(OpenXrStatusView.togglePreview)!['text'], 'Start VR Preview');

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
    final view = await nextView();
    expect(textOf(view, OpenXrStatusView.togglePreview), 'Stop VR Preview');
    expect(textOf(view, OpenXrStatusView.sessionState), 'Session: focused (preview running)');
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

  test('commands that would open a dialog show the OpenXR panel in the editor', () async {
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
    // showPanel is sent without waiting; a ping orders it before the check.
    await host.call(PluginMethods.ping);
    final shows = [for (final r in host.requests) if (r.$1 == PluginMethods.panels) r.$2];
    expect(shows, List.filled(6, {'op': 'show', 'panelId': LuminaPluginOpenxrPlugin.panelId}));

    await shutdown();
  });

  test('the panel changes the runtime choice, tracking origin and stereo mode', () async {
    await ready();
    Future<void> event(String control, Object? value) => host.call(PluginMethods.viewEvent,
        {'viewId': OpenXrStatusView.viewId, 'controlId': control, 'kind': 'changed', 'value': value});

    await event(OpenXrStatusView.forceSimulation, true);
    expect(OpenXrBindings.instance.isSimulationForced, isTrue);
    var view = await nextView();
    expect(textOf(view, OpenXrStatusView.runtimeName), 'Runtime: Lumina Simulated HMD');
    expect(textOf(view, OpenXrStatusView.manifestPath), 'Manifest: internal://simulated');
    expect(PluginViewSpec.fromJson(view).find(OpenXrStatusView.forceSimulation)!['value'], isTrue);
    // The status button shows the simulated runtime (sent as host.slotState
    // when that differs from what the editor shows).
    final sim = process.openxr.statusButtonState.value;
    expect((sim.label, sim.tooltip), ('XR (Sim)', 'OpenXR runtime: Lumina Simulated HMD (simulated)'));

    await event(OpenXrStatusView.trackingOrigin, 'stage');
    expect(process.openxr.session.trackingOrigin, OpenXrTrackingOrigin.stage);
    view = await nextView();
    expect(PluginViewSpec.fromJson(view).find(OpenXrStatusView.trackingOrigin)!['value'], 'stage');

    await event(OpenXrStatusView.stereoMode, 'multiview');
    expect(process.openxr.stereoMode, OpenXrStereoMode.multiview);
    view = await nextView();
    expect(PluginViewSpec.fromJson(view).find(OpenXrStatusView.stereoMode)!['value'], 'multiview');

    // An unknown option changes nothing and sends no view.
    await event(OpenXrStatusView.stereoMode, 'triple');
    expect(process.openxr.stereoMode, OpenXrStereoMode.multiview);

    // The panel's own button starts the preview.
    await host.call(PluginMethods.viewEvent,
        {'viewId': OpenXrStatusView.viewId, 'controlId': OpenXrStatusView.togglePreview, 'kind': 'pressed'});
    expect(process.openxr.isVrPreviewActive, isTrue);
    view = await nextView();
    expect(textOf(view, OpenXrStatusView.togglePreview), 'Stop VR Preview');

    // The MCP tool and the shell's channel report the same state.
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
    Future<String> codeOf(Future<Object?> f) async {
      try {
        await f;
      } on PluginRemoteError catch (e) {
        return e.code;
      }
      return 'no error';
    }

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
    expect(log['message'],
        startsWith('$_name error while initialize: openxr_bridge_initialize: Bad state: xrCreateInstance failed'));

    await shutdown();
    expect(LuminaPluginCrashReporter.hasHandler, isFalse, reason: 'the handler is removed on shutdown');
  });
}
