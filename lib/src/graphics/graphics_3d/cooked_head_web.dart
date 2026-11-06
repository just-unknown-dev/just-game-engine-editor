// cooked_head.dart on the web, where there are no files to read and the
// editor never runs.
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show internal;

/// Throws: a cooked model's file can't be read on the web.
@internal
Future<Uint8List> readCookedHead(String path) async =>
    throw UnsupportedError('Reading a cooked model needs dart:io.');

/// The most a cooked model's header is read for.
@internal
const int maxHeaderBytes = 64 << 20;
