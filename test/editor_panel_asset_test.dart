import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/lumina.dart';
import 'package:lumina_core/lumina_core.dart' show LuminaEditorPanelCapability, LuminaEditorPanelDock, LuminaEditorPanelInfo;
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:lumina_editor_api/testing.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

/// `content/Editor/EPW_OpenXR.lmas`, the OpenXR panel: an editor panel
/// Widget Blueprint (dock right, capability `process` only) whose elements
/// are the ones the process patches and whose graph calls only methods the
/// process answers and listens only to events it sends.
void main() {
  late Map<String, dynamic> payload;
  late Map<String, Map<String, dynamic>> elements; // name → designer node
  late LuminaBlueprintDocument graph;

  setUpAll(() {
    final asset = LuminaAsset.fromBytes(File(OpenXrPanel.asset).readAsBytesSync());
    expect(asset.type, AssetType.widget);
    expect(asset.name, 'EPW_OpenXR');
    payload = (jsonDecode(utf8.decode(asset.rawPayload!)) as Map).cast<String, dynamic>();
    elements = {};
    void walk(Map<String, dynamic> n) {
      elements[n['name'] as String] = n;
      for (final c in (n['children'] as List? ?? const [])) {
        walk((c as Map).cast<String, dynamic>());
      }
    }

    walk((payload['root'] as Map).cast<String, dynamic>());
    graph = LuminaBlueprintDocument.fromJson((payload[LuminaWidgetBlueprintDocument.payloadKey] as Map).cast<String, dynamic>());
  });

  Iterable<LuminaBlueprintNode> nodesOf(String registryId) => graph.eventGraph.nodes.where((n) => n.registryId == registryId);

  test('parses as an editor panel docked right that needs only the process capability', () {
    final info = LuminaEditorPanelInfo.ofPayload(payload)!;
    expect(info.title, 'OpenXR');
    expect(info.icon, 'glasses');
    expect(info.dock, LuminaEditorPanelDock.right);
    expect(info.menuPath, 'Plugins/OpenXR/OpenXR Panel');
    expect(info.capabilities, {LuminaEditorPanelCapability.process});
  });

  test('every element the process patches or the graph drives exists with its type', () {
    String typeOf(String name) => elements[name]?['type'] as String? ?? 'missing';
    for (final e in OpenXrPanel.patchedElements.entries) {
      expect(typeOf(e.key), e.value, reason: e.key);
    }
    expect(typeOf(OpenXrPanel.forceSimulation), 'shadcnSwitch');
    expect(typeOf(OpenXrPanel.trackingOrigin), 'comboBox');
    expect(typeOf(OpenXrPanel.stereoMode), 'comboBox');
    expect(typeOf(OpenXrPanel.togglePreview), 'button');
    expect(typeOf(OpenXrPanel.about), 'text');

    // The four sections with today's titles; About starts collapsed.
    final sections = [
      for (final n in elements.values)
        if (n['type'] == 'editorSection') ((n['props'] as Map)['title'], (n['props'] as Map)['expanded']),
    ];
    expect(sections, [
      ('Active Runtime', true),
      ('Tracking & Stereoscopic', true),
      ('VR Preview', true),
      ('About ${OpenXrController.friendlyName}', false),
    ]);
    expect((elements[OpenXrPanel.about]!['props'] as Map)['text'], OpenXrController.aboutText);

    // The selects offer every origin and mode with today's labels, by value.
    List<(Object?, Object?)> options(String name) => [
          for (final o in ((elements[name]!['props'] as Map)['options'] as List).cast<Map<String, dynamic>>()) (o['value'], o['label']),
        ];
    expect(options(OpenXrPanel.trackingOrigin),
        [for (final o in OpenXrTrackingOrigin.values) (o.name, OpenXrPanel.originLabel(o))]);
    expect(options(OpenXrPanel.stereoMode), [for (final m in OpenXrStereoMode.values) (m.name, OpenXrPanel.stereoLabel(m))]);
  });

  test('its graph compiles in the editor scope; only the editor library nodes are left to the editor', () {
    LuminaJsonBlueprintNodes.ensureRegistered();
    final widget = LuminaWidgetBlueprintDocument(
      widgetClass: 'EPW_OpenXR',
      variables: [
        for (final n in elements.values)
          // `Is Variable`: stored when it differs from the type's default
          // (leaves are variables, panels are not).
          if (n['isVariable'] as bool? ?? (n['children'] as List? ?? const []).isEmpty)
            LuminaBlueprintWidgetElement(
                name: n['name'] as String, typeName: n['type'] as String, props: (n['props'] as Map).cast<String, dynamic>()),
      ],
      blueprint: graph,
    );
    final compiled = LuminaBlueprintClass.forEditorPanel(widget, capabilities: {'process'});
    // The editor registers its function library (Editor|…, `editor_*`
    // nodes) itself; the editor's own test compiles the panel with it.
    final editorNodes = {for (final n in graph.eventGraph.nodes) if (n.registryId.startsWith('editor_')) n.id};
    final rest = [for (final d in compiled.diagnostics) if (d.isError && !editorNodes.contains(d.nodeId)) '$d'];
    expect(rest, isEmpty);
    for (final n in graph.eventGraph.nodes) {
      if (n.registryId.startsWith('editor_') || n.registryId == LuminaBlueprintEditorNodes.comment) continue;
      expect(LuminaBlueprintNodeLibrary.spec(n.registryId), isNotNull, reason: n.registryId);
    }
  });

  test('the graph calls only methods the process answers and listens to the event it sends', () async {
    final methods = {for (final n in nodesOf('editor_call_plugin_process')) n.literals['method'] as String};
    expect(methods, {'status', 'setForceSimulation', 'setTrackingOrigin', 'setStereoMode', 'toggleVrPreview'});
    expect({for (final n in nodesOf(LuminaEditorEventNodes.pluginProcessEvent)) n.literals['event']}, {OpenXrPanel.statusEvent});

    OpenXrBindings.instance.setForceSimulation(false);
    final host = await LoopbackHost.start();
    final process = LuminaPluginOpenxrProcess();
    final exit = runPluginProcessMain(host.launch(OpenXrController.pluginName), process);
    await host.contributions;
    final args = {
      'status': <String, Object?>{},
      'setForceSimulation': {'value': true},
      'setTrackingOrigin': {'value': 'eyeLevel'},
      'setStereoMode': {'value': 'separateViews'},
      'toggleVrPreview': <String, Object?>{},
    };
    for (final m in methods) {
      final answer = await host.channel.call(m, args[m]!) as Map;
      expect(answer.keys, containsAll(['active_runtime', 'simulation_forced', 'vr_preview_active']), reason: m);
    }
    final sent = await host.next(PluginMethods.event, where: (a) => a['name'] == OpenXrPanel.statusEvent);
    expect((sent['data'] as Map).containsKey('session_state'), isTrue);
    await host.call(PluginMethods.shutdown);
    expect(await exit, PluginProcessExitCodes.ok);
    await host.close();
    OpenXrBindings.instance.setForceSimulation(false);
  });
}
