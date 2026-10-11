import 'package:flutter_test/flutter_test.dart';
import 'package:lumina/lumina.dart';
import 'package:lumina_plugin_openxr/runtime.dart';
import 'package:vector_math/vector_math_64.dart';

class _NoRender implements OpenXrEyeRenderer {
  @override
  bool render(OpenXrFrame frame, List<OpenXrEyeView> views) => true;
}

void main() {
  late SimulatedOpenXrBackend sim;
  late LuminaXROriginActor origin;
  late OpenXrInputSystem input;

  setUp(() {
    sim = SimulatedOpenXrBackend()..initialize();
    origin = LuminaXROriginActor();
    input = OpenXrInputSystem.forOrigin(sim.input, origin);
    expect(input.setup(), XrResult.success);
  });

  test('a grip pose (0.2, 1.1, -0.4) m puts the left controller at (20, 110, -40) cm runtime, (20, 40, 110) authored', () {
    sim
      ..setControllerPose(isLeft: true, position: Vector3(0.2, 1.1, -0.4), orientation: Quaternion.identity())
      ..setControllerInputs(isLeft: true, grip: 0.4, trigger: 0.9, thumbstick: Vector2(0.5, -1), primaryButton: true);
    input.sync(1000);
    final left = origin.leftController;
    expect(left.isTracked, isTrue);
    expect(left.location.x, closeTo(20, 1e-4));
    expect(left.location.y, closeTo(110, 1e-4));
    expect(left.location.z, closeTo(-40, 1e-4));
    expect(LuminaAxes.toAuthoringLocation(left.worldLocation), [closeTo(20, 1e-4), closeTo(40, 1e-4), closeTo(110, 1e-4)]);
    expect(left.grip, closeTo(0.4, 1e-6));
    expect(left.triggerAxis.isPressed, isTrue);
    expect(left.thumbstick.x, 0.5);
    expect(left.thumbstick.y, -1);
    expect(left.primaryButton.justPressed, isTrue);
    // The aim follows the grip, pitched like a Touch controller's ray.
    expect(left.aimLocation, left.location);
    expect(left.ray!.direction.y, lessThan(0), reason: 'the ray points down and forward');
    expect(sim.inputSyncTimes, [1000], reason: 'located at the frame\'s predicted display time');
  });

  test('untracked: isTracked false and the last pose kept', () {
    sim.setControllerPose(isLeft: false, position: Vector3(0.3, 1.2, -0.5), orientation: Quaternion.identity());
    input.sync(1);
    final right = origin.rightController;
    final kept = right.location.clone();
    sim
      ..rightTracked = false
      ..setControllerPose(isLeft: false, position: Vector3(9, 9, 9), orientation: Quaternion.identity());
    input.sync(2);
    expect(right.isTracked, isFalse);
    expect(right.location, kept);
  });

  test('the controller is a grabber: id, world transform with unit scale, grip, haptic pulse', () {
    origin.actorLocation = Vector3(100, 0, 0);
    sim
      ..setControllerPose(isLeft: true, position: Vector3(0.2, 1.1, -0.4), orientation: Quaternion.identity())
      ..setControllerInputs(isLeft: true, grip: 0.8);
    input.sync(5);
    final LuminaGrabber grabber = origin.leftController;
    expect(grabber.id, 'left');
    expect(grabber.isTracked, isTrue);
    expect(grabber.grip, closeTo(0.8, 1e-6));
    final t = grabber.worldTransform.getTranslation();
    expect([t.x, t.y, t.z], [closeTo(120, 1e-4), closeTo(110, 1e-4), closeTo(-40, 1e-4)]);
    expect(grabber.worldTransform.getMaxScaleOnAxis(), closeTo(1, 1e-9));
    grabber.pulse(0.5, 0.03);
    expect(sim.hapticPulses.single.amplitude, 0.5);
    expect(sim.hapticPulses.single.durationNs, 30000000);
    expect(sim.hapticPulses.single.hand, LuminaXRHand.left);
  });

  test('the XR keys reach the world\'s input: grip analog, buttons as key down / up', () {
    final world = LuminaWorld(worldType: LuminaWorldType.game);
    final keys = world.getSubsystem<LuminaInputSubsystem>() ?? world.registerSubsystem(LuminaInputSubsystem());
    input.attachTo(world);
    sim.setControllerInputs(isLeft: true, grip: 0.6, primaryButton: true);
    sim.setControllerInputs(isLeft: false, trigger: 0.3, primaryButton: true);
    input.sync(1);
    keys.tick(1 / 72);
    expect(keys.axisValue(LuminaKey.xrLeftGrip), closeTo(0.6, 1e-6));
    expect(keys.axisValue(LuminaKey.xrRightTrigger), closeTo(0.3, 1e-6));
    expect(keys.isKeyDown(LuminaKey.xrLeftX), isTrue);
    expect(keys.isKeyDown(LuminaKey.xrRightA), isTrue);
    expect(keys.lastInputDevice, 'XR');
    sim.setControllerInputs(isLeft: true, grip: 0.6);
    input.sync(2);
    keys.tick(1 / 72);
    expect(keys.isKeyDown(LuminaKey.xrLeftX), isFalse);
  });

  test('the frame loop syncs the controllers before the world tick, at each frame\'s display time', () {
    final pacer = OpenXrSimulatedPacer(sim, automatic: false);
    final loop = OpenXrFrameLoop(pacer: pacer, renderer: _NoRender(), input: input);
    final seen = <bool>[];
    loop.onFrame = (dt, frame) => seen.add(sim.inputSyncTimes.last == frame.predictedDisplayTime);
    loop.start();
    pacer
      ..tick()
      ..tick();
    expect(seen, [true, true]);
    expect(input.frames, 2);
    expect(input.interactionProfile(LuminaXRHand.left), OpenXrInteractionProfiles.oculusTouch);
  });
}
