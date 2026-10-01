/// Hand identifier for XR motion controllers and hand tracking.
enum LuminaXRHand {
  left,
  right;

  bool get isLeft => this == LuminaXRHand.left;
  bool get isRight => this == LuminaXRHand.right;
}
