// ignore_for_file: non_constant_identifier_names
/// The input part of the native bridge's C API (`src/openxr_bridge_c.h`):
/// action sets, actions, bindings, states, action spaces, haptics.
@DefaultAsset('package:lumina_plugin_openxr/openxr_bridge.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

@Native<Int64 Function(Pointer<Utf8>, Pointer<Utf8>, Uint32)>()
external int openxr_bridge_create_action_set(Pointer<Utf8> name, Pointer<Utf8> localizedName, int priority);

@Native<Int64 Function(Int64, Pointer<Utf8>, Pointer<Utf8>, Int32, Bool)>()
external int openxr_bridge_create_action(
    int actionSet, Pointer<Utf8> name, Pointer<Utf8> localizedName, int type, bool perHand);

@Native<Int32 Function(Pointer<Utf8>, Pointer<Int64>, Pointer<Pointer<Utf8>>, Uint32)>()
external int openxr_bridge_suggest_bindings(
    Pointer<Utf8> profile, Pointer<Int64> actions, Pointer<Pointer<Utf8>> paths, int count);

@Native<Int32 Function()>()
external int openxr_bridge_attach_action_sets();

@Native<Bool Function()>()
external bool openxr_bridge_action_sets_attached();

@Native<Int32 Function()>()
external int openxr_bridge_sync_actions();

@Native<Int32 Function(Int64, Int32, Pointer<Bool>, Pointer<Bool>)>()
external int openxr_bridge_action_state_boolean(int action, int hand, Pointer<Bool> value, Pointer<Bool> active);

@Native<Int32 Function(Int64, Int32, Pointer<Float>, Pointer<Bool>)>()
external int openxr_bridge_action_state_float(int action, int hand, Pointer<Float> value, Pointer<Bool> active);

@Native<Int32 Function(Int64, Int32, Pointer<Float>, Pointer<Float>, Pointer<Bool>)>()
external int openxr_bridge_action_state_vector2f(
    int action, int hand, Pointer<Float> x, Pointer<Float> y, Pointer<Bool> active);

@Native<Int32 Function(Int64, Int32, Pointer<Bool>)>()
external int openxr_bridge_action_state_pose(int action, int hand, Pointer<Bool> active);

@Native<Int64 Function(Int64, Int32)>()
external int openxr_bridge_create_action_space(int action, int hand);

@Native<Int32 Function(Int64, Int32, Int64, Float, Float)>()
external int openxr_bridge_apply_haptic(int action, int hand, int durationNs, double frequency, double amplitude);

@Native<Int32 Function(Int64, Int32)>()
external int openxr_bridge_stop_haptic(int action, int hand);

@Native<Int32 Function(Int32, Pointer<Utf8>, Uint32)>()
external int openxr_bridge_current_interaction_profile(int hand, Pointer<Utf8> out, int capacity);
