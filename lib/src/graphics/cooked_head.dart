// The start of a cooked model's file, read with dart:io's RandomAccessFile.
// The web gets cooked_head_web.dart instead: there are no files there, and
// the editor never runs.
import 'dart:io';
import 'dart:typed_data';

/// The header of the cooked model at [path]: its first 12 bytes and the
/// header they announce, where the stamp is, without the textures behind it.
Uint8List readCookedHead(String path) {
  final raf = File(path).openSync();
  try {
    final first = raf.readSync(12);
    if (first.length < 12) return first;
    final n = ByteData.sublistView(first).getUint32(8, Endian.little);
    raf.setPositionSync(0);
    return raf.readSync(12 + n);
  } finally {
    raf.closeSync();
  }
}
