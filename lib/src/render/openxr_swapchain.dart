/// OpenXR swapchain image format.
enum OpenXrSwapchainFormat {
  r8g8b8a8Unorm,
  r8g8b8a8Srgb,
  b8g8r8a8Unorm,
  b8g8r8a8Srgb,
  d24UnormS8Uint,
  d32Float,
}

/// Parameters for creating and managing an OpenXR render swapchain.
class OpenXrSwapchainDescriptor {
  final int width;
  final int height;
  final int sampleCount;
  final OpenXrSwapchainFormat format;
  final int arraySize;

  const OpenXrSwapchainDescriptor({
    required this.width,
    required this.height,
    this.sampleCount = 1,
    this.format = OpenXrSwapchainFormat.r8g8b8a8Srgb,
    this.arraySize = 2, // 2 layers for multiview / stereo texture array
  });
}
