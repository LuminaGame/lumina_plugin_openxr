import 'package:flutter_filament/filament.dart';
import 'package:logging/logging.dart';
import 'package:lumina_plugin_openxr/src/backend/openxr_native_backend.dart';
import 'package:lumina_plugin_openxr/src/ffi/openxr_types.dart';
import 'package:lumina_plugin_openxr/src/render/openxr_stereo_view.dart';

final _log = Logger('OpenXrFilamentBridge');

/// flutter_filament's device-info functions, for [OpenXrSession.vulkanDeviceInfo]:
/// the runtime's Vulkan device is created with what Filament needs.
OpenXrVulkanDeviceInfoFunctions openXrFilamentDeviceInfo() => OpenXrVulkanDeviceInfoFunctions(
      create: ExternalVulkanDeviceInfoFunctions.create,
      createInfo: ExternalVulkanDeviceInfoFunctions.createInfo,
      queueFamily: ExternalVulkanDeviceInfoFunctions.queueFamily,
      filamentQueueIndex: ExternalVulkanDeviceInfoFunctions.filamentQueueIndex,
      multiview: ExternalVulkanDeviceInfoFunctions.multiview,
      destroy: ExternalVulkanDeviceInfoFunctions.destroy,
    );

/// The context `FilamentEngine.createOnExternalVulkan` adopts: the runtime's
/// device, Filament on its own queue.
ExternalVulkanContext openXrFilamentContext(OpenXrVulkanDevice device) => ExternalVulkanContext(
      instance: device.instance,
      physicalDevice: device.physicalDevice,
      device: device.device,
      queueFamily: device.queueFamily,
      queueIndex: device.rendererQueueIndex,
      multiview: device.multiview,
    );

/// Adapts OpenXR stereo views to Google Filament's stereoscopic rendering pipeline.
class OpenXrFilamentBridge {
  OpenXrStereoMode stereoMode;
  bool isStereoEnabled = false;

  OpenXrStereoView? leftEyeView;
  OpenXrStereoView? rightEyeView;

  OpenXrFilamentBridge({
    this.stereoMode = OpenXrStereoMode.instanced,
  });

  /// Maps [OpenXrStereoMode] to Filament's native [StereoscopicType].
  StereoscopicType get filamentStereoType {
    switch (stereoMode) {
      case OpenXrStereoMode.multiview:
        return StereoscopicType.multiview;
      case OpenXrStereoMode.instanced:
        return StereoscopicType.instanced;
      case OpenXrStereoMode.separateViews:
        return StereoscopicType.none;
    }
  }

  /// Creates an [EngineConfig] with the desired stereoscopic parameters.
  EngineConfig createEngineConfig() {
    _log.fine('Creating EngineConfig with stereo: $stereoMode');
    return EngineConfig(
      stereoscopicEyeCount: 2,
      stereoscopicType: isStereoEnabled ? filamentStereoType : StereoscopicType.none,
    );
  }

  /// Updates left and right eye view models.
  void updateEyeViews({
    required OpenXrStereoView left,
    required OpenXrStereoView right,
  }) {
    leftEyeView = left;
    rightEyeView = right;
  }
}
