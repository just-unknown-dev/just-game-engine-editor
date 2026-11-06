// Runs the tests that draw with Flutter GPU — the 3-D material pictures,
// the model thumbnails — which skip themselves in a plain `flutter test`:
//
//   dart run tool/test_gpu.dart [more flutter test arguments]
//
// from the package folder. It is the command CONTRIBUTING.md gives for the
// `gpu` tag, one test file at a time, as the GPU is one device. Run it for
// any change to the pictures, the thumbnails or the 3-D Material window's
// preview, and before a release.

import 'dart:io';

Future<void> main(List<String> args) async {
  final run = await Process.start(
    'flutter',
    [
      'test',
      '--enable-impeller',
      '--enable-flutter-gpu',
      '--tags',
      'gpu',
      '--concurrency=1',
      ...args,
    ],
    mode: ProcessStartMode.inheritStdio,
    // flutter is a batch file on Windows.
    runInShell: Platform.isWindows,
  );
  exitCode = await run.exitCode;
}
