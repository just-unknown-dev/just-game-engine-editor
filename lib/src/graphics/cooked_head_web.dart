// cooked_head.dart on the web, where there are no files to read and the
// editor never runs.
import 'dart:typed_data';

/// Throws: a cooked model's file can't be read on the web.
Uint8List readCookedHead(String path) =>
    throw UnsupportedError('Reading a cooked model needs dart:io.');
