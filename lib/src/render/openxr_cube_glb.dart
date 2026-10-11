import 'dart:convert';
import 'dart:typed_data';

/// A cube (side [size] metres) as a binary glTF: positions, normals and
/// indices per face, one PBR material of [color] (linear RGBA). The glTF
/// loader computes the tangents; the ubershader materials carry a multiview
/// variant, so the cube renders in both eyes in one pass.
Uint8List openXrCubeGlb({double size = 0.3, List<double> color = const [0.9, 0.35, 0.1, 1.0], double roughness = 0.4}) {
  final h = size / 2;
  // Each face: normal, then its four corners (counter-clockwise seen from outside).
  final faces = <(List<double>, List<List<double>>)>[
    ([1, 0, 0], [[h, -h, h], [h, -h, -h], [h, h, -h], [h, h, h]]),
    ([-1, 0, 0], [[-h, -h, -h], [-h, -h, h], [-h, h, h], [-h, h, -h]]),
    ([0, 1, 0], [[-h, h, h], [h, h, h], [h, h, -h], [-h, h, -h]]),
    ([0, -1, 0], [[-h, -h, -h], [h, -h, -h], [h, -h, h], [-h, -h, h]]),
    ([0, 0, 1], [[-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]]),
    ([0, 0, -1], [[h, -h, -h], [-h, -h, -h], [-h, h, -h], [h, h, -h]]),
  ];
  final positions = <double>[];
  final normals = <double>[];
  final indices = <int>[];
  for (final (normal, corners) in faces) {
    final base = positions.length ~/ 3;
    for (final c in corners) {
      positions.addAll(c);
      normals.addAll(normal);
    }
    indices.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }
  final posBytes = Float32List.fromList(positions).buffer.asUint8List();
  final normalBytes = Float32List.fromList(normals).buffer.asUint8List();
  final indexBytes = Uint16List.fromList(indices).buffer.asUint8List();
  final bin = BytesBuilder()
    ..add(posBytes)
    ..add(normalBytes)
    ..add(indexBytes);
  while (bin.length % 4 != 0) {
    bin.addByte(0);
  }
  final json = {
    'asset': {'version': '2.0', 'generator': 'lumina_plugin_openxr'},
    'scene': 0,
    'scenes': [
      {'nodes': [0]},
    ],
    'nodes': [
      {'mesh': 0},
    ],
    'meshes': [
      {
        'primitives': [
          {
            'attributes': {'POSITION': 0, 'NORMAL': 1},
            'indices': 2,
            'material': 0,
          },
        ],
      },
    ],
    'materials': [
      {
        'pbrMetallicRoughness': {'baseColorFactor': color, 'metallicFactor': 0.0, 'roughnessFactor': roughness},
      },
    ],
    'buffers': [
      {'byteLength': bin.length},
    ],
    'bufferViews': [
      {'buffer': 0, 'byteOffset': 0, 'byteLength': posBytes.length, 'target': 34962},
      {'buffer': 0, 'byteOffset': posBytes.length, 'byteLength': normalBytes.length, 'target': 34962},
      {'buffer': 0, 'byteOffset': posBytes.length + normalBytes.length, 'byteLength': indexBytes.length, 'target': 34963},
    ],
    'accessors': [
      {
        'bufferView': 0,
        'componentType': 5126,
        'count': positions.length ~/ 3,
        'type': 'VEC3',
        'min': [-h, -h, -h],
        'max': [h, h, h],
      },
      {'bufferView': 1, 'componentType': 5126, 'count': normals.length ~/ 3, 'type': 'VEC3'},
      {'bufferView': 2, 'componentType': 5123, 'count': indices.length, 'type': 'SCALAR'},
    ],
  };
  final jsonBytes = BytesBuilder()..add(utf8.encode(jsonEncode(json)));
  while (jsonBytes.length % 4 != 0) {
    jsonBytes.addByte(0x20);
  }
  final binBytes = bin.takeBytes();
  final jsonChunk = jsonBytes.takeBytes();
  final total = 12 + 8 + jsonChunk.length + 8 + binBytes.length;
  final out = ByteData(total);
  var o = 0;
  void u32(int v) {
    out.setUint32(o, v, Endian.little);
    o += 4;
  }

  u32(0x46546C67); // glTF
  u32(2);
  u32(total);
  u32(jsonChunk.length);
  u32(0x4E4F534A); // JSON
  final bytes = out.buffer.asUint8List();
  bytes.setRange(o, o + jsonChunk.length, jsonChunk);
  o += jsonChunk.length;
  u32(binBytes.length);
  u32(0x004E4942); // BIN
  bytes.setRange(o, o + binBytes.length, binBytes);
  return bytes;
}
