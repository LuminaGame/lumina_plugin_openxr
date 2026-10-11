import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The Khronos OpenXR loader for Android, from Maven Central
/// (`org.khronos.openxr:openxr_loader_for_android`, Apache-2.0). Fetched at
/// build time and checked against [openXrLoaderAarSha256]; never committed.
const openXrLoaderVersion = '1.1.63';

/// The AAR's download URL.
const openXrLoaderAarUrl = 'https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/'
    '$openXrLoaderVersion/openxr_loader_for_android-$openXrLoaderVersion.aar';

/// SHA-256 of the AAR (its Maven SHA-1 is bb72fea1e7bdd35b381ae2a705206d912a1d5b30).
const openXrLoaderAarSha256 = '622419d2f6741c3443a3beb4779af0764318edd01830de967f24c741ebcded73';

/// A checksum mismatch or a download / archive failure.
class OpenXrLoaderException implements Exception {
  OpenXrLoaderException(this.message);
  final String message;

  @override
  String toString() => 'OpenXrLoaderException: $message';
}

/// `<cacheDir>/<abi>/libopenxr_loader.so`, extracted from the AAR (downloaded
/// into [cacheDir] once, or read from [aar] when given) after checking the
/// AAR's SHA-256 against [sha256].
Future<File> ensureOpenXrLoader({
  required Directory cacheDir,
  required String abi,
  String sha256Hex = openXrLoaderAarSha256,
  String url = openXrLoaderAarUrl,
  File? aar,
}) async {
  final out = File('${cacheDir.path}/$abi/libopenxr_loader.so');
  final stamp = File('${cacheDir.path}/$abi/libopenxr_loader.so.sha256');
  if (out.existsSync() && stamp.existsSync() && stamp.readAsStringSync().trim() == sha256Hex) return out;

  final archive = aar ?? File('${cacheDir.path}/openxr_loader_for_android-$openXrLoaderVersion.aar');
  if (!archive.existsSync()) {
    await cacheDir.create(recursive: true);
    await _download(Uri.parse(url), archive);
  }
  final bytes = await archive.readAsBytes();
  final actual = sha256.convert(bytes).toString();
  if (actual != sha256Hex) {
    if (aar == null) await archive.delete();
    throw OpenXrLoaderException('checksum mismatch for $url: expected $sha256Hex, got $actual');
  }
  final library = zipEntry(bytes, 'jni/$abi/libopenxr_loader.so');
  if (library == null) throw OpenXrLoaderException('the AAR has no jni/$abi/libopenxr_loader.so');
  await out.parent.create(recursive: true);
  await out.writeAsBytes(library);
  await stamp.writeAsString(sha256Hex);
  return out;
}

Future<void> _download(Uri uri, File to) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw OpenXrLoaderException('GET $uri: HTTP ${response.statusCode}');
    }
    final partial = File('${to.path}.part');
    await response.pipe(partial.openWrite());
    await partial.rename(to.path);
  } on SocketException catch (e) {
    throw OpenXrLoaderException('GET $uri: $e');
  } finally {
    client.close(force: true);
  }
}

/// The bytes of [name] in the zip archive [zip] (stored or deflated), or null.
Uint8List? zipEntry(Uint8List zip, String name) {
  final data = ByteData.sublistView(zip);
  // End of central directory: signature 0x06054b50, searched from the end.
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 22 - 0xffff; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw OpenXrLoaderException('not a zip archive');
  final entries = data.getUint16(eocd + 10, Endian.little);
  var at = data.getUint32(eocd + 16, Endian.little);
  for (var e = 0; e < entries; e++) {
    if (data.getUint32(at, Endian.little) != 0x02014b50) throw OpenXrLoaderException('bad central directory');
    final method = data.getUint16(at + 10, Endian.little);
    final compressed = data.getUint32(at + 20, Endian.little);
    final nameLength = data.getUint16(at + 28, Endian.little);
    final extraLength = data.getUint16(at + 30, Endian.little);
    final commentLength = data.getUint16(at + 32, Endian.little);
    final localHeader = data.getUint32(at + 42, Endian.little);
    final entryName = String.fromCharCodes(zip.sublist(at + 46, at + 46 + nameLength));
    if (entryName == name) {
      final localNameLength = data.getUint16(localHeader + 26, Endian.little);
      final localExtraLength = data.getUint16(localHeader + 28, Endian.little);
      final start = localHeader + 30 + localNameLength + localExtraLength;
      final payload = zip.sublist(start, start + compressed);
      if (method == 0) return payload;
      if (method == 8) return Uint8List.fromList(ZLibDecoder(raw: true).convert(payload));
      throw OpenXrLoaderException('unsupported compression $method for $name');
    }
    at += 46 + nameLength + extraLength + commentLength;
  }
  return null;
}
