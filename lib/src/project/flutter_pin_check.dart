import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

/// The Flutter a project pins in its `just.json` against the Flutter the
/// editor runs on.
///
/// `just` pins one exact Flutter per project (`"flutter": "3.47.9"`): the
/// engine draws 3-D with Flutter GPU, a preview API that changes from one
/// Flutter to the next. When the editor runs on another, it says so in the
/// log at start, in Problems, and once per pinned version in a message.
///
/// The files are read the first time [mismatch] is asked for, and once per
/// scope ([of]): an editor session reads them once.
class FlutterPinCheck {
  /// The check of [projectRoot]'s pin against [running].
  ///
  /// [running] is the Flutter the editor was built with
  /// (`FlutterVersion.version`); when it is null, the one the project's
  /// `.dart_tool/package_config.json` names (its `flutterVersion`).
  FlutterPinCheck({
    required this.projectRoot,
    this.running = FlutterVersion.version,
  });

  /// The check for [scope]'s project ([EditorScope.projectRoot]), made the
  /// first time it is asked for. One registered in the scope's container
  /// ahead of that, a test's, is used instead.
  static FlutterPinCheck of(EditorScope scope) =>
      scope.service(() => FlutterPinCheck(projectRoot: scope.projectRoot));

  /// The project's folder.
  final String projectRoot;

  /// The Flutter the editor runs on, when it was built knowing it.
  final String? running;

  /// The project's `just` settings file, at its root.
  static const String fileName = 'just.json';

  /// What puts the pinned Flutter in place: the Problems entry's fix
  /// copies it.
  static const String fixCommand = 'just sdk install';

  /// The pinned version the message was last shown for: it is shown once
  /// per pinned version.
  static final SettingPref<String> shownPref = SettingPref.text(
    'editor.flutterPin.shown',
    '',
  );

  /// What is wrong, or null when nothing is: no pin, no known running
  /// Flutter, or the same one. Read the first time it is asked for.
  late final FlutterPinMismatch? mismatch = read(projectRoot, running: running);

  /// The Problems entry, with a fix that copies [fixCommand]: one of
  /// `BuiltInEditorModule.validators`.
  static List<SceneProblem> problems(ValidationContext context) {
    final mismatch = of(context.scope).mismatch;
    if (mismatch == null) return const [];
    return [
      SceneProblem(
        message: mismatch.message,
        hint: mismatch.fix,
        fixes: const [ProblemFix(label: 'Copy command', apply: copyFixCommand)],
      ),
    ];
  }

  /// Puts [fixCommand] on the clipboard.
  static void copyFixCommand() =>
      unawaited(Clipboard.setData(const ClipboardData(text: fixCommand)));

  /// [projectRoot]'s pin against [running], read from the disk: `just.json`
  /// and, when [running] is null, `.dart_tool/package_config.json`.
  /// Anything that cannot be read is no warning.
  static FlutterPinMismatch? read(
    String projectRoot, {
    String? running = FlutterVersion.version,
  }) {
    final root = projectRoot.replaceAll(r'\', '/');
    final justJson = _readText('$root/$fileName');
    // No pin: no need to look for the running Flutter.
    if (pinnedIn(justJson) == null) return null;
    final known = running?.trim();
    return compare(
      justJson: justJson,
      running: known == null || known.isEmpty
          ? flutterVersionIn(_readText('$root/.dart_tool/package_config.json'))
          : known,
    );
  }

  /// The mismatch between the pin in [justJson] (the text of `just.json`)
  /// and [running], or null: no file, no pin, no running version, or the
  /// same one. The versions are compared exactly, trimmed.
  static FlutterPinMismatch? compare({
    required String? justJson,
    required String? running,
  }) {
    final pinned = pinnedIn(justJson);
    final now = running?.trim();
    if (pinned == null || now == null || now.isEmpty || now == pinned) {
      return null;
    }
    return FlutterPinMismatch(pinned: pinned, running: now);
  }

  /// The Flutter version [justJson] pins (its `flutter` key), or null: no
  /// text, not a JSON object, no key, or not an exact version.
  static String? pinnedIn(String? justJson) {
    final value = _decode(justJson)?['flutter'];
    if (value is! String) return null;
    final version = value.trim();
    return isExactVersion(version) ? version : null;
  }

  /// The Flutter version a `package_config.json` names (its
  /// `flutterVersion`, written by `flutter pub get`), or null.
  static String? flutterVersionIn(String? packageConfigJson) {
    final value = _decode(packageConfigJson)?['flutterVersion'];
    if (value is! String) return null;
    final version = value.trim();
    return version.isEmpty ? null : version;
  }

  /// Whether [version] is one exact version, as `just` pins: `3.47.9`,
  /// `3.48.0-0.1.pre`; not a range (`^3.47.0`) or a channel (`stable`).
  static bool isExactVersion(String version) => _exact.hasMatch(version);

  static final RegExp _exact = RegExp(
    r'^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$',
  );

  static Map<String, dynamic>? _decode(String? text) {
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      return json is Map<String, dynamic> ? json : null;
    } on FormatException {
      return null;
    }
  }

  static String? _readText(String path) {
    try {
      final file = File(path);
      return file.existsSync() ? file.readAsStringSync() : null;
    } on Object {
      // Unreadable, or no files at all (the web): no warning.
      return null;
    }
  }
}

/// A project pinned to one Flutter and an editor running on another: what
/// [FlutterPinCheck] finds.
class FlutterPinMismatch {
  const FlutterPinMismatch({required this.pinned, required this.running});

  /// The version `just.json` pins.
  final String pinned;

  /// The version the editor runs on.
  final String running;

  /// What is wrong: the log's line and the Problems entry.
  String get message =>
      'This project pins Flutter $pinned (just.json), but the editor is '
      'running on Flutter $running. The game may not build, and 3D '
      '(Flutter GPU) may draw wrongly.';

  /// What to do about it.
  String get fix =>
      'Run `${FlutterPinCheck.fixCommand}` in the project folder, then '
      'restart the editor with `just game run --editor`.';

  /// The message's title: short enough for the status strip's chip.
  String get title => 'This project pins Flutter $pinned';

  /// The message's text, problem and fix: short enough for its three lines.
  String get notice =>
      'The editor runs on $running: the game may not build, and 3D may draw '
      'wrongly. Run `${FlutterPinCheck.fixCommand}`, then '
      '`just game run --editor`.';

  @override
  bool operator ==(Object other) =>
      other is FlutterPinMismatch &&
      other.pinned == pinned &&
      other.running == running;

  @override
  int get hashCode => Object.hash(pinned, running);

  @override
  String toString() => 'FlutterPinMismatch($pinned, running $running)';
}
