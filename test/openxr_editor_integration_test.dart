import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:lumina_plugin_openxr/lumina_plugin_openxr.dart';

class _TestEditorContext implements LuminaEditorContext {
  final List<String> registeredMenuPaths = [];
  final List<EditorCommand> registeredCommands = [];
  final List<EditorSlotButton> registeredSlotButtons = [];
  final List<EditorMenuItemOptions> registeredMenuOptions = [];

  @override
  void registerMenuItem(String menuPath, EditorCommand command,
      {EditorMenuItemOptions options = const EditorMenuItemOptions()}) {
    registeredMenuPaths.add(menuPath);
    registeredCommands.add(command);
    registeredMenuOptions.add(options);
  }

  @override
  void registerMenu(EditorMenuDescriptor menu) {}

  @override
  void registerToolbarButton(EditorToolbarButton button) {}

  @override
  void registerSlotButton(EditorSlotButton button) {
    registeredSlotButtons.add(button);
  }

  @override
  final EditorPanels panels = EditorPanels.detached();

  @override
  final EditorMcp mcp = EditorMcp.detached(pluginName: 'lumina_plugin_openxr');

  @override
  final PluginStorage storage = PluginStorage(
      userDir: Directory('${Directory.systemTemp.path}/lumina_openxr_test_storage'));

  @override
  void registerProjectSettingsSection(ProjectSettingsSection section) {}

  @override
  final ValueNotifier<Map<String, Object?>> pluginSettings = ValueNotifier(const {});

  @override
  void registerPanel(EditorPanelDescriptor panel) {}

  @override
  void registerAssetType(EditorAssetTypeHandler handler) {}

  @override
  void registerImporter(EditorImporter importer) {}

  @override
  void registerDetailsCustomization(DetailsCustomization c) {}

  @override
  void registerConsoleCommand(String name, String help, void Function(List<String> args) handler) {}

  @override
  void registerTab(EditorTabDescriptor tab) {}

  @override
  void openTab(String tabId, {String? title}) {}

  @override
  Future<void> saveAsset({required String relativePath, Uint8List? bytes, bool generateThumbnail = true}) async {}

  @override
  PluginProcessChannel processChannel(String pluginName) => PluginProcessChannel.detached(pluginName);

  @override
  void reportCrash(Object error, StackTrace? stack, {String? plugin, String? context}) {
    LuminaPluginCrashReporter.reportCrash(
      error,
      stack,
      plugin: plugin ?? 'lumina_plugin_openxr',
      context: context,
    );
  }
}

void main() {
  group('OpenXR Editor Integration Tests', () {
    test('LuminaPluginOpenxrPlugin registers menus, status slot, and MCP tool', () async {
      final plugin = LuminaPluginOpenxrPlugin();
      final ctx = _TestEditorContext();

      plugin.register(ctx);

      expect(ctx.registeredMenuPaths, contains('Plugins/OpenXR/Check Runtime'));
      expect(ctx.registeredMenuPaths, contains('Plugins/OpenXR/Toggle VR Preview'));
      expect(ctx.registeredMenuPaths, contains('Plugins/OpenXR/OpenXR Settings'));
      expect(ctx.registeredMenuPaths, contains('Plugins/OpenXR/About OpenXR Support'));

      expect(ctx.registeredSlotButtons.any((s) => s.id == 'openxr.status_badge'), isTrue);

      // Verify MCP tool
      final statusTool = ctx.mcp.listTools().firstWhere((t) => t.name == 'lumina_plugin_openxr.get_status');
      expect(statusTool, isNotNull);

      final result = await ctx.mcp.callTool('lumina_plugin_openxr.get_status', {});
      expect(result.structuredContent, isNotNull);
      expect(result.structuredContent!['active_runtime'], isNotNull);
      expect(result.structuredContent!['is_simulated'], isNotNull);
      expect(result.structuredContent!['session_state'], isNotNull);
    });

    test('Toggle VR preview command toggles preview state', () {
      final plugin = LuminaPluginOpenxrPlugin();
      final ctx = _TestEditorContext();
      plugin.register(ctx);

      expect(plugin.isVrPreviewActive, isFalse);

      final toggleCmd = ctx.registeredCommands.firstWhere((c) => c.id == 'tools.lumina_plugin_openxr.togglePreview');
      toggleCmd.execute(null);
      expect(plugin.isVrPreviewActive, isTrue);

      toggleCmd.execute(null);
      expect(plugin.isVrPreviewActive, isFalse);
    });

    test('the in-editor shell registers nothing and only takes its process channel', () {
      final shell = LuminaPluginOpenxrShell();
      final ctx = _TestEditorContext();
      shell.register(ctx);

      expect(shell.pluginName, 'lumina_plugin_openxr');
      expect(ctx.registeredMenuPaths, isEmpty);
      expect(ctx.registeredSlotButtons, isEmpty);
      expect(ctx.mcp.listTools(), isEmpty);
      expect(shell.channel!.pluginName, 'lumina_plugin_openxr');

      shell.unregister(ctx);
      expect(shell.channel, isNull);
    });
  });
}
