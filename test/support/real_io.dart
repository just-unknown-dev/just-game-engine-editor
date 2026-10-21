// Waiting for real work — file reads and writes — that the code under test
// starts, by its outcome rather than for a fixed time.
//
// A widget test runs on a fake clock. File I/O started from it finishes on
// the real clock, and what comes after each step (the line after an
// `await`) waits until the fake clock runs again. So a chain of file
// operations moves one step per pump that follows some real time, and how
// many steps fit in a fixed wait depends on how busy the machine is: a test
// that waits "long enough" passes alone and fails under load. These helpers
// wait until what the test needs has happened, and fail — saying what they
// waited for — only after a bound far longer than the work ever takes.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// How long the helpers wait for what they wait for before failing the
/// test: far longer than the work takes on a busy machine, so only work
/// that never finishes fails.
const Duration ioTimeout = Duration(seconds: 10);

/// The time given to a plain `test` that boots an engine and the editor.
///
/// A `testWidgets` gets ten minutes; a plain `test` gets package:test's 30
/// seconds. The first boot in a test file compiles most of the engine and
/// the editor, and with other suites running side by side that alone has
/// taken longer than 30 seconds: such tests failed in their setUp, still
/// waiting on the editor's first file read, while the same boot in a widget
/// test passed.
const Timeout bootTimeout = Timeout(Duration(minutes: 2));

/// One round of waiting: this much real time, then this much fake time.
const Duration _step = Duration(milliseconds: 10);

/// Pumps [tester] until [done] holds; fails the test, naming [what], when it
/// has not within [timeout] of real time.
///
/// Each round gives the real clock a moment, for file I/O to finish, and
/// then the fake clock as long, with a frame: for what that work does next,
/// including a pause it takes on the fake clock (a move tried again because
/// a virus scanner held the file, a debounce). The fake clock never moves
/// on by more than the real one did, so a timer the test relies on not
/// firing (an Undo offered for a few seconds) does not fire early.
///
/// A [done] that throws a [FileSystemException] — a file read while it is
/// replaced — has not happened yet.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration timeout = ioTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (!_holds(done)) {
    if (clock.elapsed > timeout) {
      fail('Waited ${timeout.inSeconds} s for $what, and it never happened.');
    }
    await tester.runAsync(() => Future<void>.delayed(_step));
    await tester.pump(_step);
  }
}

/// [pumpUntil] for code on the real clock: a plain `test`, or the inside of
/// `tester.runAsync`.
Future<void> waitUntil(
  bool Function() done, {
  required String what,
  Duration timeout = ioTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (!_holds(done)) {
    if (clock.elapsed > timeout) {
      fail('Waited ${timeout.inSeconds} s for $what, and it never happened.');
    }
    await Future<void>.delayed(_step);
  }
}

/// What [read] gives, tried again while it throws a [FileSystemException]
/// — on Windows a file just written can be held for a moment by something
/// else, a virus scanner looking at it — for up to [timeout].
///
/// Synchronous (it sleeps between tries), so a test can read on either
/// clock. Read a file the code under test writes only once that code is
/// done with it (see [pumpUntil]): reading it while it is replaced is what
/// holds the writer up.
T readWhenFree<T>(T Function() read, {Duration timeout = ioTimeout}) {
  final clock = Stopwatch()..start();
  while (true) {
    try {
      return read();
    } on FileSystemException {
      if (clock.elapsed > timeout) rethrow;
      sleep(_step);
    }
  }
}

/// Deletes [dir] and everything in it, trying again for up to [timeout]
/// while the system still holds something in it — on Windows a folder
/// watcher, or a read just finished, lets go a moment after it is closed.
Future<void> deleteWhenFree(
  Directory dir, {
  Duration timeout = ioTimeout,
}) async {
  final clock = Stopwatch()..start();
  while (true) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (clock.elapsed > timeout) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Pumps until [provider] has been read and decoded, or has failed to be:
/// an [Image] reads its file on the fake clock, step by step, and a test
/// that ended halfway would leave the file open.
Future<void> pumpUntilImageSettled(
  WidgetTester tester,
  ImageProvider provider, {
  required String what,
}) async {
  var settled = false;
  final stream = provider.resolve(ImageConfiguration.empty);
  final listener = ImageStreamListener(
    (_, _) => settled = true,
    onError: (_, _) => settled = true,
  );
  stream.addListener(listener);
  try {
    await pumpUntil(tester, () => settled, what: what);
  } finally {
    stream.removeListener(listener);
  }
}

bool _holds(bool Function() done) {
  try {
    return done();
  } on FileSystemException {
    return false;
  }
}
