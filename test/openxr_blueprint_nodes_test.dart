import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/lumina.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  var wires = 0;
  LuminaBlueprintWire wire(String from, String fromPin, String to, String toPin) =>
      LuminaBlueprintWire(id: 'w${wires++}', fromNodeId: from, fromPinId: fromPin, toNodeId: to, toPinId: toPin);

  late SimulatedOpenXrBackend sim;
  late LuminaWorld world;
  late LuminaXROriginActor origin;

  setUp(() {
    sim = SimulatedOpenXrBackend()..initialize();
    world = LuminaWorld(worldType: LuminaWorldType.game);
    origin = LuminaXROriginActor();
    world.persistentLevel.registerActor(origin);
  });
  tearDown(OpenXrBlueprintNodes.unregister);

  LuminaBlueprintActor instantiate(LuminaBlueprintDocument doc, String name) {
    final cls = LuminaBlueprintClass.fromDocument(doc, name: name);
    expect(cls.diagnostics, isEmpty, reason: '${cls.diagnostics}');
    return cls.instantiate() as LuminaBlueprintActor;
  }

  test('On Tick → Get Grip Value(Left) > 0.7 → Play Haptic Pulse: one pulse when the simulated grip crosses 0.7', () {
    final input = OpenXrInputSystem.forOrigin(sim.input, origin)..setup();
    input.attachTo(world);
    final doc = LuminaBlueprintDocument();
    final context = LuminaBlueprintTypeContext.forDocument(doc, className: 'BP_XRHaptics');
    LuminaBlueprintNode p(String id, String nodeId, [Map<String, dynamic>? literals]) =>
        LuminaBlueprintNodeLibrary.place(id, nodeId: nodeId, literals: literals, context: context);
    doc.eventGraph.nodes.addAll([
      p('event_tick', 'tick'),
      p(OpenXrBlueprintNodes.gripValueId, 'grip', {'hand': 'Left'}),
      p('float_greater', 'over', {'b': 0.7}),
      p('branch', 'if'),
      p(OpenXrBlueprintNodes.playHapticPulseId, 'pulse', {'hand': 'Left', 'amplitude': 0.6, 'seconds': 0.05}),
    ]);
    doc.eventGraph.wires.addAll([
      wire('tick', 'exec_tick_out', 'if', 'exec_in'),
      wire('grip', 'return_value', 'over', 'a'),
      wire('over', 'return_value', 'if', 'condition'),
      wire('if', 'true_out', 'pulse', 'exec_in'),
    ]);
    final actor = instantiate(doc, 'BP_XRHaptics');
    world.persistentLevel.registerActor(actor);
    world.beginPlay();
    var time = 0;
    for (final grip in [0.2, 0.5, 0.8, 0.4, 0.1]) {
      sim.setControllerInputs(isLeft: true, grip: grip);
      input.sync(time += 13889000);
      world.tick(1 / 72);
    }
    expect(sim.hapticPulses, hasLength(1));
    expect(sim.hapticPulses.single.hand, LuminaXRHand.left);
    expect(sim.hapticPulses.single.amplitude, closeTo(0.6, 1e-9));
    expect(sim.hapticPulses.single.durationNs, 50000000);
  });

  test('Get Controller Grip Transform, Get Trigger Value and Is Controller Tracked read the right hand', () {
    final input = OpenXrInputSystem.forOrigin(sim.input, origin)..setup();
    input.attachTo(world);
    sim
      ..setControllerPose(isLeft: false, position: Vector3(0.2, 1.1, -0.4), orientation: Quaternion.identity())
      ..setControllerInputs(isLeft: false, trigger: 0.35);
    input.sync(1);
    final self = LuminaActor();
    world.persistentLevel.registerActor(self);
    final call = LuminaBlueprintFunctionRegistry.function;
    final ctx = LuminaBlueprintCallContext(self);
    final t = call(OpenXrBlueprintNodes.gripTransformId)!(ctx, {'hand': 'Right'})['return_value'];
    final broken = LuminaBlueprintFunctionLibrary.breakTransform(t);
    expect([broken.location.x, broken.location.y, broken.location.z],
        [closeTo(20, 1e-4), closeTo(40, 1e-4), closeTo(110, 1e-4)], reason: 'authoring axes (Z up), cm');
    expect(call(OpenXrBlueprintNodes.triggerValueId)!(ctx, {'hand': 'Right'})['return_value'], closeTo(0.35, 1e-6));
    expect(call(OpenXrBlueprintNodes.isTrackedId)!(ctx, {'hand': 'Right'})['return_value'], isTrue);
    expect(call(OpenXrBlueprintNodes.gripValueId)!(ctx, {'hand': 'Left'})['return_value'], 0.0);
    final aim = call(OpenXrBlueprintNodes.aimTransformId)!(ctx, {'hand': 'Right'})['return_value'];
    expect(LuminaBlueprintFunctionLibrary.breakTransform(aim).location.z, closeTo(110, 1e-4));
  });

  test('without an XR input system the nodes read a released, untracked controller', () {
    OpenXrBlueprintNodes.register();
    final self = LuminaActor();
    world.persistentLevel.registerActor(self);
    final ctx = LuminaBlueprintCallContext(self);
    expect(LuminaBlueprintFunctionRegistry.function(OpenXrBlueprintNodes.isTrackedId)!(ctx, {'hand': 'Left'})['return_value'],
        isFalse);
    expect(LuminaBlueprintFunctionRegistry.function(OpenXrBlueprintNodes.playHapticPulseId)!(ctx, {'hand': 'Left'}), isEmpty);
  });
}
