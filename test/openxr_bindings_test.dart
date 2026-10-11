import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_plugin_openxr/runtime.dart';

import '../tool/embed_bindings.dart' as embed;

void main() {
  final bindings = OpenXrInputBindings.defaults;

  test('the Touch Plus profile binds grip to the squeeze value and primary to A on the right hand', () {
    final plus = bindings.profile('meta/touch_controller_plus')!;
    expect(plus.path, OpenXrInteractionProfiles.metaTouchControllerPlus);
    expect(plus.extension, 'XR_META_touch_controller_plus');
    expect(plus.pathsOf('grip'), contains('/user/hand/left/input/squeeze/value'));
    expect(plus.pathsOf('primary'), contains('/user/hand/right/input/a/click'));
    expect(plus.pathsOf('primary'), contains('/user/hand/left/input/x/click'));
    expect(plus.pairs, contains((action: 'haptic', path: '/user/hand/right/output/haptic')));
  });

  test('the oculus/touch_controller fallback binds the same actions', () {
    final plus = bindings.profile('meta/touch_controller_plus')!;
    final touch = bindings.profile('oculus/touch_controller')!;
    expect(touch.extension, isNull);
    expect(touch.bindings.keys.toSet(), plus.bindings.keys.toSet());
    expect(touch.bindings.keys.toSet(), {for (final a in bindings.actions) a.name});
  });

  test('khr/simple_controller maps select/click to trigger', () {
    final simple = bindings.profile('khr/simple_controller')!;
    expect(simple.pathsOf('trigger'), ['/user/hand/left/input/select/click', '/user/hand/right/input/select/click']);
    expect(simple.pathsOf('grip'), isEmpty, reason: 'the simple controller has no squeeze');
  });

  test('an extension profile is suggested only when the instance has its extension', () {
    expect(bindings.profilesToSuggest((_) => false).map((p) => p.shortName),
        ['oculus/touch_controller', 'khr/simple_controller']);
    expect(bindings.profilesToSuggest((e) => e == 'XR_META_touch_controller_plus').map((p) => p.shortName),
        ['meta/touch_controller_plus', 'oculus/touch_controller', 'khr/simple_controller']);
    expect(bindings.extensions, ['XR_META_touch_controller_plus']);
  });

  test('the action set: gameplay with poses, values, buttons and the haptic output', () {
    expect(bindings.actionSetName, 'gameplay');
    expect(bindings.action('grip_pose')!.xrType, 4);
    expect(bindings.action('grip')!.xrType, 2);
    expect(bindings.action('thumbstick')!.xrType, 3);
    expect(bindings.action('primary')!.xrType, 1);
    expect(bindings.action('haptic')!.xrType, 100);
  });

  test('the embedded bindings match bindings.json', () {
    final json = File(embed.jsonPath).readAsStringSync();
    expect(File(embed.dartPath).readAsStringSync().replaceAll('\r\n', '\n'), embed.render(json),
        reason: 'run dart run tool/embed_bindings.dart');
  });

  test('the simulator suggests the core profiles', () {
    final sim = SimulatedOpenXrBackend()..initialize();
    expect(sim.input.setupInput(bindings), XrResult.success);
    expect(sim.input.suggestedProfiles,
        [OpenXrInteractionProfiles.oculusTouch, OpenXrInteractionProfiles.khronosSimple]);
  });
}
