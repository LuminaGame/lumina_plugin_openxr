import 'package:lumina_plugin_openxr/src/backend/openxr_backend.dart';

/// `XrCompositionLayerFlagBits` of the projection layer.
abstract final class OpenXrCompositionLayerFlags {
  static const correctChromaticAberration = 0x1;

  /// Blend the layer with its texture's alpha (over an underlay).
  static const blendTextureSourceAlpha = 0x2;

  /// The layer's colours are not premultiplied by alpha.
  static const unpremultipliedAlpha = 0x4;
}

/// A composition layer another plugin owns: a name (for logs and tests) and
/// the address of its `XrCompositionLayerBaseHeader`-derived struct, valid
/// while it is submitted.
class OpenXrCompositionLayer {
  const OpenXrCompositionLayer(this.name, this.address);

  final String name;
  final int address;

  @override
  bool operator ==(Object other) => other is OpenXrCompositionLayer && other.name == name && other.address == address;

  @override
  int get hashCode => Object.hash(name, address);

  @override
  String toString() => name;
}

/// Something that adds composition layers to every frame: a passthrough
/// underlay, a quad overlay. The frame loop asks each contributor every
/// frame (with its predicted display time, ns); the openxr plugin knows no
/// vendor extension itself.
abstract interface class OpenXrLayerContributor {
  /// Layers under the projection layer, in order.
  List<OpenXrCompositionLayer> layersBefore(int displayTime);

  /// Layers over the projection layer, in order.
  List<OpenXrCompositionLayer> layersAfter(int displayTime);

  /// Flags the projection layer needs ([OpenXrCompositionLayerFlags]); 0 for none.
  int get projectionLayerFlags;

  /// An environment blend mode this contributor needs ([OpenXrBlendMode]), or null.
  int? get environmentBlendMode;

  /// Whether the game must clear to alpha 0 (something shows through).
  bool get transparentBackground;
}

/// A renderer that can clear to alpha 0 (so layers under it show through).
abstract interface class OpenXrTransparencyAware {
  set transparentBackground(bool value);
}

/// What the frames end with: the layers before and after the projection
/// layer, its flags, the environment blend mode and whether the game clears
/// to alpha 0.
class OpenXrFrameComposition {
  const OpenXrFrameComposition({
    this.before = const [],
    this.after = const [],
    this.projectionFlags = 0,
    this.environmentBlendMode = OpenXrBlendMode.opaque,
    this.transparentBackground = false,
  });

  /// Collects [contributors] for the frame shown at [displayTime].
  factory OpenXrFrameComposition.of(List<OpenXrLayerContributor> contributors, int displayTime,
      {int environmentBlendMode = OpenXrBlendMode.opaque}) {
    final before = <OpenXrCompositionLayer>[];
    final after = <OpenXrCompositionLayer>[];
    var flags = 0;
    var blend = environmentBlendMode;
    var transparent = false;
    for (final c in contributors) {
      before.addAll(c.layersBefore(displayTime));
      after.addAll(c.layersAfter(displayTime));
      flags |= c.projectionLayerFlags;
      blend = c.environmentBlendMode ?? blend;
      transparent = transparent || c.transparentBackground;
    }
    return OpenXrFrameComposition(
        before: before, after: after, projectionFlags: flags, environmentBlendMode: blend, transparentBackground: transparent);
  }

  final List<OpenXrCompositionLayer> before;
  final List<OpenXrCompositionLayer> after;
  final int projectionFlags;
  final int environmentBlendMode;
  final bool transparentBackground;

  /// The submitted order by name, the projection layer as `projection`.
  List<String> get layerNames => [...before.map((l) => l.name), 'projection', ...after.map((l) => l.name)];

  @override
  bool operator ==(Object other) =>
      other is OpenXrFrameComposition &&
      _same(other.before, before) &&
      _same(other.after, after) &&
      other.projectionFlags == projectionFlags &&
      other.environmentBlendMode == environmentBlendMode &&
      other.transparentBackground == transparentBackground;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(before), Object.hashAll(after), projectionFlags, environmentBlendMode, transparentBackground);

  static bool _same(List<OpenXrCompositionLayer> a, List<OpenXrCompositionLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => '$layerNames, flags 0x${projectionFlags.toRadixString(16)}, '
      'blend ${OpenXrBlendMode.name(environmentBlendMode)}${transparentBackground ? ', transparent' : ''}';
}

/// Instance extensions other plugins need, added before the instance is
/// created (`OpenXrSession.beginSession` asks for them when the runtime
/// offers them).
abstract final class OpenXrExtensionRequests {
  static final Set<String> _requested = {};

  static void add(String extension) => _requested.add(extension);
  static void remove(String extension) => _requested.remove(extension);
  static List<String> get all => List.unmodifiable(_requested);
}
