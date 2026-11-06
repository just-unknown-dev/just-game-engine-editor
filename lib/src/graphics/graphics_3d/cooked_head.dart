// The start of a cooked model's file, read with dart:io's RandomAccessFile.
// The web gets cooked_head_web.dart instead: there are no files there, and
// the editor never runs.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show internal;
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show CookedModel;

/// The header of the cooked model at [path]: its first 12 bytes and the
/// header they announce, where the stamp is, without the textures behind it.
///
/// Only the first 12 bytes of a file that is not a cooked model of this
/// version, or whose header would run past the file's end or past
/// [maxHeaderBytes]: no stamp is found in them, so it is cooked again —
/// and nothing is read on the say-so of a stray file's bytes.
@internal
Future<Uint8List> readCookedHead(String path) async {
  final raf = await File(path).open();
  try {
    final first = await raf.read(12);
    if (first.length < 12 || !CookedModel.isCooked(first)) return first;
    final n = ByteData.sublistView(first).getUint32(8, Endian.little);
    if (n > maxHeaderBytes || 12 + n > await raf.length()) return first;
    await raf.setPosition(0);
    return await raf.read(12 + n);
  } finally {
    await raf.close();
  }
}

/// The most a cooked model's header is read for: far more than any model's
/// meshes, materials and nodes take to describe.
@internal
const int maxHeaderBytes = 64 << 20;
