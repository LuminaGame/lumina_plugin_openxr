import 'package:lumina_editor_api/lumina_editor_api.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'ffi/openxr_bindings.dart';
import 'render/openxr_filament_bridge.dart';
import 'session/openxr_session.dart';
import 'ui/openxr_settings_view.dart';

/// Khronos OpenXR plugin for Lumina Studio.
class LuminaPluginOpenxrPlugin extends LuminaEditorPlugin {
  static const String friendlyName = 'OpenXR Support';
  static const String version = '0.1.0';

  final OpenXrBindings bindings = OpenXrBindings.instance;
  late final OpenXrSession session;
  late final OpenXrFilamentBridge filamentBridge;

  bool _isVrPreviewActive = false;
  EditorLevelAccess? _level;

  LuminaPluginOpenxrPlugin() {
    session = OpenXrSession(bindings: bindings);
    filamentBridge = OpenXrFilamentBridge();
  }

  @override
  String get pluginName => 'lumina_plugin_openxr';

  bool get isVrPreviewActive => _isVrPreviewActive;

  void _showDiagnostic(BuildContext ctx) {
    final status = bindings.isNativeRuntimeAvailable
        ? 'Active Native Runtime: ${bindings.activeRuntimeName}\nPath: ${bindings.activeRuntimePath}'
        : 'No physical OpenXR runtime active. Using internal Simulated HMD backend for development.';
    showOverlay<void>(
      ctx,
      const DialogConfiguration(),
      builder: (c) => AlertDialog(
        title: const Text('OpenXR Runtime Diagnostic'),
        content: Text(status),
        actions: [
          PrimaryButton(onPressed: () => closeOverlay<void>(c), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  void register(LuminaEditorContext context) {
    if (context is LuminaEditorHostContext) {
      _level = context.level;
    }

    // 1. Menu: Check Runtime
    context.registerMenuItem(
      'Plugins/OpenXR/Check Runtime',
      EditorCommand(
        id: 'tools.lumina_plugin_openxr.checkRuntime',
        label: 'Check OpenXR Runtime',
        icon: LucideIcons.search,
        canExecute: () => true,
        execute: (ctx) {
          if (ctx != null) _showDiagnostic(ctx);
        },
      ),
      options: const EditorMenuItemOptions(section: 'status'),
    );

    // 2. Menu: Toggle VR Preview
    context.registerMenuItem(
      'Plugins/OpenXR/Toggle VR Preview',
      EditorCommand(
        id: 'tools.lumina_plugin_openxr.togglePreview',
        label: 'Toggle VR Preview',
        icon: LucideIcons.glasses,
        canExecute: () => true,
        execute: (ctx) {
          _isVrPreviewActive = !_isVrPreviewActive;
          if (_isVrPreviewActive) {
            session.beginSession();
          } else {
            session.endSession();
          }
          _level?.log('VR Preview ${_isVrPreviewActive ? "started" : "stopped"} (${bindings.activeRuntimeName})',
              level: 'info', source: 'OpenXR');
        },
      ),
      options: const EditorMenuItemOptions(section: 'run'),
    );

    // 3. Menu: OpenXR Settings
    context.registerMenuItem(
      'Plugins/OpenXR/OpenXR Settings',
      EditorCommand(
        id: 'tools.lumina_plugin_openxr.settings',
        label: 'OpenXR Settings',
        icon: LucideIcons.settings,
        canExecute: () => true,
        execute: (ctx) {
          if (ctx == null) return;
          showOverlay<void>(
            ctx,
            const DialogConfiguration(),
            builder: (c) => AlertDialog(
              title: const Text('OpenXR Settings'),
              content: SizedBox(
                width: 500,
                child: OpenXrSettingsView(bindings: bindings, session: session),
              ),
              actions: [
                PrimaryButton(onPressed: () => closeOverlay<void>(c), child: const Text('Close')),
              ],
            ),
          );
        },
      ),
      options: const EditorMenuItemOptions(section: 'settings'),
    );

    // 4. Menu: About OpenXR
    context.registerMenuItem(
      'Plugins/OpenXR/About $friendlyName',
      EditorCommand(
        id: 'tools.lumina_plugin_openxr.about',
        label: 'About $friendlyName',
        canExecute: () => true,
        execute: (ctx) {
          if (ctx == null) return;
          showOverlay<void>(
            ctx,
            const DialogConfiguration(),
            builder: (c) => AlertDialog(
              title: const Text(friendlyName),
              content: const Text(
                'Khronos OpenXR 1.0/1.1 runtime management, stereoscopic rendering bridge for Filament, '
                'and XR origin/controller tracking components.\nVersion: $version',
              ),
              actions: [
                PrimaryButton(onPressed: () => closeOverlay<void>(c), child: const Text('Close')),
              ],
            ),
          );
        },
      ),
      options: const EditorMenuItemOptions(section: 'about'),
    );

    // 5. Register Status Bar Indicator Slot
    context.registerSlotButton(
      EditorSlotButton(
        id: 'openxr.status_badge',
        slot: EditorSlot.statusBarRight,
        state: ValueNotifier(
          const EditorButtonState(
            label: 'XR Status',
            tooltip: 'OpenXR Runtime Status',
            icon: LucideIcons.glasses,
          ),
        ),
        command: EditorCommand(
          id: 'tools.lumina_plugin_openxr.statusBadgeClick',
          label: 'OpenXR Status',
          canExecute: () => true,
          execute: (ctx) {
            if (ctx != null) _showDiagnostic(ctx);
          },
        ),
      ),
    );

    // 6. Register MCP tools for AI agents
    context.mcp.registerTool(
      McpTool(
        name: 'get_status',
        description: 'Returns OpenXR runtime diagnostic details and tracking session status.',
        inputSchema: const {'type': 'object', 'properties': <String, Object?>{}},
        risk: McpToolRisk.readOnly,
        groups: const {McpToolGroups.plugin},
        handler: (args) async => McpToolResult.json({
          'active_runtime': bindings.activeRuntimeName,
          'manifest_path': bindings.activeRuntimePath,
          'is_simulated': bindings.isSimulated,
          'session_state': session.state.name,
          'tracking_origin': session.trackingOrigin.name,
          'vr_preview_active': _isVrPreviewActive,
        }),
      ),
    );
  }

  @override
  void unregister(LuminaEditorContext context) {
    session.endSession();
    _level = null;
  }
}
