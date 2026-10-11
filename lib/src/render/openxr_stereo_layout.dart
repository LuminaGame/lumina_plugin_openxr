/// How the eyes are laid out in the compositor's swapchains.
class OpenXrStereoLayout {
  const OpenXrStereoLayout._(this.views, this.layers, this.swapchains);

  /// Filament views rendered per frame.
  final int views;

  /// Array layers of each swapchain image.
  final int layers;

  /// Swapchains submitted in the projection layer.
  final int swapchains;

  bool get multiview => views == 1 && layers == 2;

  /// One multiview view into a 2-layer image when the engine can render
  /// stereo and the materials carry multiview code (the engine's own and the
  /// prebuilt glTF ubershaders do); otherwise one view and one swapchain per eye.
  static OpenXrStereoLayout choose({required bool stereoSupported, required bool multiviewMaterials}) =>
      stereoSupported && multiviewMaterials ? const OpenXrStereoLayout._(1, 2, 1) : const OpenXrStereoLayout._(2, 1, 2);

  @override
  String toString() => multiview ? 'multiview (1 view, 2 layers)' : 'per eye ($views views, $swapchains swapchains)';
}
