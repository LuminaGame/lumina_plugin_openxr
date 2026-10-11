import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';

/// An event the OpenXR runtime posted (`xrPollEvent`), decoded.
sealed class OpenXrRuntimeEvent {
  const OpenXrRuntimeEvent();

  /// Decodes the bridge's `openxr_bridge_event` fields.
  static OpenXrRuntimeEvent fromNative(
          {required int kind, int state = 0, int time = 0, double value = 0, int spaceType = 0, int structureType = 0, int payload = 0}) =>
      switch (kind) {
        1 => OpenXrSessionStateChanged(OpenXrSessionState.fromXr(state), time),
        2 => OpenXrInstanceLossPending(time),
        3 => OpenXrReferenceSpaceChangePending(spaceType, time),
        4 => const OpenXrInteractionProfileChanged(),
        5 => const OpenXrEventsLost(),
        6 => OpenXrDisplayRefreshRateChanged(value),
        _ => OpenXrOtherEvent(structureType: structureType, payload: payload),
      };
}

/// `XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED`.
final class OpenXrSessionStateChanged extends OpenXrRuntimeEvent {
  const OpenXrSessionStateChanged(this.state, [this.time = 0]);
  final OpenXrSessionState state;

  /// XrTime of the change (ns).
  final int time;

  @override
  String toString() => 'state ${state.name}';
}

/// `XR_TYPE_EVENT_DATA_INSTANCE_LOSS_PENDING`.
final class OpenXrInstanceLossPending extends OpenXrRuntimeEvent {
  const OpenXrInstanceLossPending([this.lossTime = 0]);
  final int lossTime;

  @override
  String toString() => 'instance loss pending';
}

/// `XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING` (a recentre, a new boundary).
final class OpenXrReferenceSpaceChangePending extends OpenXrRuntimeEvent {
  const OpenXrReferenceSpaceChangePending(this.spaceType, [this.changeTime = 0]);
  final int spaceType;
  final int changeTime;

  @override
  String toString() => 'reference space $spaceType change pending';
}

/// `XR_TYPE_EVENT_DATA_INTERACTION_PROFILE_CHANGED`.
final class OpenXrInteractionProfileChanged extends OpenXrRuntimeEvent {
  const OpenXrInteractionProfileChanged();

  @override
  String toString() => 'interaction profile changed';
}

/// `XR_TYPE_EVENT_DATA_EVENTS_LOST`.
final class OpenXrEventsLost extends OpenXrRuntimeEvent {
  const OpenXrEventsLost();

  @override
  String toString() => 'events lost';
}

/// `XR_TYPE_EVENT_DATA_DISPLAY_REFRESH_RATE_CHANGED_FB`.
final class OpenXrDisplayRefreshRateChanged extends OpenXrRuntimeEvent {
  const OpenXrDisplayRefreshRateChanged(this.hz);
  final double hz;

  @override
  String toString() => 'display refresh rate $hz Hz';
}

/// Any other event type: its `XrStructureType` and the first 64 bits after
/// its `next` pointer, for the plugin whose extension posts it (for example
/// `XrEventDataPassthroughStateChangedFB::flags`).
final class OpenXrOtherEvent extends OpenXrRuntimeEvent {
  const OpenXrOtherEvent({this.structureType = 0, this.payload = 0});

  final int structureType;
  final int payload;

  @override
  String toString() => 'other event (type $structureType)';
}
