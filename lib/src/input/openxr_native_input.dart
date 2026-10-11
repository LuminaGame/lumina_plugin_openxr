import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/components/lumina_xr_hand.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_bridge_ffi.dart' as b;
import 'package:lumina_plugin_openxr/src/ffi/openxr_error_reporter.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_input_ffi.dart' as ix;
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_backend.dart';
import 'package:lumina_plugin_openxr/src/input/openxr_input_bindings.dart';

final _log = Logger('OpenXR.input');

/// `XrSpaceLocationFlags`: orientation and position valid.
const _poseValid = 0x1 | 0x2;

/// The runtime's input through the native bridge: one action set, its actions
/// per hand, the grip and aim action spaces. Every call is guarded (a native
/// failure is reported, never thrown).
class OpenXrNativeInput implements OpenXrInputBackend {
  OpenXrNativeInput(this.backend);

  final OpenXrNativeBackend backend;
  final Map<String, int> _actions = {};
  final Map<(String, int), int> _spaces = {};
  final List<String> _suggested = [];
  bool _ready = false;

  // Per-frame scratch, allocated once.
  Pointer<Bool>? _bool;
  Pointer<Bool> _active = nullptr;
  Pointer<Float> _f1 = nullptr;
  Pointer<Float> _f2 = nullptr;
  Pointer<b.OpenXrBridgePose> _pose = nullptr;

  @override
  bool get inputReady => _ready;

  @override
  List<String> get suggestedProfiles => List.unmodifiable(_suggested);

  /// The bridge's id of action [name] (0 when unknown).
  int actionId(String name) => _actions[name] ?? 0;

  XrResult _call(String context, int Function() call) {
    final r = XrResult.fromValue(OpenXrErrorReporter.guard(context, call, XrResult.errorRuntimeFailure.value));
    if (r.isFailure) _log.warning('$context failed: ${backend.lastError}');
    return r;
  }

  @override
  XrResult setupInput(OpenXrInputBindings bindings) {
    if (_ready) return XrResult.success;
    if (_bool == null) {
      _bool = calloc<Bool>();
      _active = calloc<Bool>();
      _f1 = calloc<Float>();
      _f2 = calloc<Float>();
      _pose = calloc<b.OpenXrBridgePose>();
    }
    // Actions and suggested bindings belong to the instance: made once, attached to each session.
    if (_actions.isEmpty) {
      final set = OpenXrErrorReporter.guard(
          'createActionSet',
          () => using((arena) => ix.openxr_bridge_create_action_set(bindings.actionSetName.toNativeUtf8(allocator: arena),
              bindings.localizedName.toNativeUtf8(allocator: arena), bindings.priority)),
          -1);
      if (set <= 0) return XrResult.fromValue(set == -1 ? XrResult.errorRuntimeFailure.value : set);
      for (final a in bindings.actions) {
        final id = OpenXrErrorReporter.guard(
            'createAction ${a.name}',
            () => using((arena) => ix.openxr_bridge_create_action(set, a.name.toNativeUtf8(allocator: arena),
                a.localizedName.toNativeUtf8(allocator: arena), a.xrType, true)),
            -1);
        if (id <= 0) return XrResult.errorRuntimeFailure;
        _actions[a.name] = id;
      }
      for (final profile in bindings.profilesToSuggest(backend.extensionEnabled)) {
        final pairs = [
          for (final p in profile.pairs)
            if (_actions.containsKey(p.action)) p,
        ];
        final r = _call(
            'suggestBindings ${profile.shortName}',
            () => using((arena) {
                  final actions = arena<Int64>(pairs.length);
                  final paths = arena<Pointer<Utf8>>(pairs.length);
                  for (var i = 0; i < pairs.length; i++) {
                    actions[i] = _actions[pairs[i].action]!;
                    paths[i] = pairs[i].path.toNativeUtf8(allocator: arena);
                  }
                  return ix.openxr_bridge_suggest_bindings(
                      profile.path.toNativeUtf8(allocator: arena), actions, paths, pairs.length);
                }));
        // A profile the runtime does not know is skipped, not fatal.
        if (r.isSuccess) _suggested.add(profile.path);
      }
    }
    final attached = _call('attachActionSets', ix.openxr_bridge_attach_action_sets);
    if (attached.isFailure) return attached;
    for (final name in const ['grip_pose', 'aim_pose']) {
      final action = _actions[name];
      if (action == null) continue;
      for (final hand in LuminaXRHand.values) {
        final space = OpenXrErrorReporter.guard(
            'createActionSpace $name', () => ix.openxr_bridge_create_action_space(action, hand.index), -1);
        if (space > 0) _spaces[(name, hand.index)] = space;
      }
    }
    _ready = true;
    return XrResult.success;
  }

  @override
  List<OpenXrControllerSample>? syncInput(int baseSpaceType, int displayTime) {
    if (!_ready) return null;
    return OpenXrErrorReporter.guard('syncInput', () {
      if (ix.openxr_bridge_sync_actions() < 0) return null;
      final base = backend.space(baseSpaceType);
      return [for (final hand in LuminaXRHand.values) _sample(hand.index, base, displayTime)];
    }, null);
  }

  OpenXrControllerSample _sample(int hand, int? base, int time) {
    final poseActive = _poseActive('grip_pose', hand);
    return OpenXrControllerSample(
      grip: poseActive && base != null ? _locate('grip_pose', hand, base, time) : null,
      aim: poseActive && base != null ? _locate('aim_pose', hand, base, time) : null,
      gripValue: _float('grip', hand),
      triggerValue: _float('trigger', hand),
      triggerTouched: _boolean('trigger_touch', hand),
      thumbstick: _vector2('thumbstick', hand),
      thumbstickClick: _boolean('thumbstick_click', hand),
      primary: _boolean('primary', hand),
      secondary: _boolean('secondary', hand),
      menu: _boolean('menu', hand),
    );
  }

  bool _poseActive(String name, int hand) {
    final a = _actions[name];
    if (a == null) return false;
    return ix.openxr_bridge_action_state_pose(a, hand, _active) >= 0 && _active.value;
  }

  OpenXrPose? _locate(String name, int hand, int base, int time) {
    final space = _spaces[(name, hand)];
    if (space == null || b.openxr_bridge_locate_space(space, base, time, _pose) < 0) return null;
    final p = _pose.ref;
    if (p.flags & _poseValid != _poseValid) return null;
    return OpenXrPose(vm.Vector3(p.position[0], p.position[1], p.position[2]),
        vm.Quaternion(p.orientation[0], p.orientation[1], p.orientation[2], p.orientation[3]));
  }

  double _float(String name, int hand) {
    final a = _actions[name];
    if (a == null || ix.openxr_bridge_action_state_float(a, hand, _f1, _active) < 0 || !_active.value) return 0;
    return _f1.value;
  }

  bool _boolean(String name, int hand) {
    final a = _actions[name];
    if (a == null || ix.openxr_bridge_action_state_boolean(a, hand, _bool!, _active) < 0 || !_active.value) return false;
    return _bool!.value;
  }

  vm.Vector2 _vector2(String name, int hand) {
    final a = _actions[name];
    if (a == null || ix.openxr_bridge_action_state_vector2f(a, hand, _f1, _f2, _active) < 0 || !_active.value) {
      return vm.Vector2.zero();
    }
    return vm.Vector2(_f1.value, _f2.value);
  }

  @override
  XrResult applyHaptic(LuminaXRHand hand,
      {required double amplitude, required int durationNs, double frequency = OpenXrHaptics.frequencyUnspecified}) {
    final a = _actions['haptic'];
    if (a == null) return XrResult.errorHandleInvalid;
    return _call('applyHaptic', () => ix.openxr_bridge_apply_haptic(a, hand.index, durationNs, frequency, amplitude));
  }

  @override
  XrResult stopHaptic(LuminaXRHand hand) {
    final a = _actions['haptic'];
    if (a == null) return XrResult.errorHandleInvalid;
    return _call('stopHaptic', () => ix.openxr_bridge_stop_haptic(a, hand.index));
  }

  @override
  String interactionProfile(LuminaXRHand hand) => OpenXrErrorReporter.guard(
      'interactionProfile',
      () => using((arena) {
            final out = arena<Uint8>(256).cast<Utf8>();
            if (ix.openxr_bridge_current_interaction_profile(hand.index, out, 256) < 0) return '';
            return out.toDartString();
          }),
      '');

  /// The session is gone (its action spaces with it); [instance] too: the
  /// actions are gone as well and the next [setupInput] makes them again.
  void forget({bool instance = false}) {
    _ready = false;
    _spaces.clear();
    if (instance) {
      _actions.clear();
      _suggested.clear();
    }
  }

  /// Frees the scratch buffers (the bridge's actions go with the instance).
  void dispose() {
    final scratch = _bool;
    if (scratch == null) return;
    calloc
      ..free(scratch)
      ..free(_active)
      ..free(_f1)
      ..free(_f2)
      ..free(_pose);
    _bool = null;
    _ready = false;
  }
}
