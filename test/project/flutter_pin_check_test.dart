// `just` pins one exact Flutter per project in just.json. The editor says
// so when it runs on another: in the log at start, in Problems (with the
// command to copy) and once per pinned version in a message.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/chrome/editor_overlay.dart';
import 'package:just_game_engine_editor/src/problems/problem_scan.dart';
import 'package:just_game_engine_editor/src/project/flutter_pin_check.dart';

import '../support/memory_settings_store.dart';
import '../support/test_scope.dart';

const _pinned = '{"schema": 1, "title": "Game", "flutter": "3.47.9"}';

/// A project folder holding [files] (path → text), deleted after the test.
String _project(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('flutter_pin_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry(key: path, value: text) in files.entries) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }
  return root.path;
}

String _packageConfig(String flutterVersion) =>
    '{"configVersion": 2, "packages": [], '
    '"flutterVersion": "$flutterVersion"}';

void main() {
  group('compare', () {
    test('the pinned Flutter: nothing to say', () {
      expect(
        FlutterPinCheck.compare(justJson: _pinned, running: '3.47.9'),
        isNull,
      );
    });

    test('another Flutter: both versions, the message and the fix', () {
      final pin = FlutterPinCheck.compare(justJson: _pinned, running: '3.48.0');
      expect(
        pin,
        const FlutterPinMismatch(pinned: '3.47.9', running: '3.48.0'),
      );
      expect(
        pin!.message,
        'This project pins Flutter 3.47.9 (just.json), but the editor is '
        'running on Flutter 3.48.0. The game may not build, and 3D '
        '(Flutter GPU) may draw wrongly.',
      );
      expect(
        pin.fix,
        'Run `just sdk install` in the project folder, then restart the '
        'editor with `just game run --editor`.',
      );
      expect(pin.title, contains('3.47.9'));
      expect(
        pin.notice,
        allOf(contains('3.48.0'), contains('just sdk install')),
      );
    });

    test('versions are compared trimmed', () {
      expect(
        FlutterPinCheck.compare(
          justJson: '{"flutter": " 3.47.9 "}',
          running: '3.47.9\n',
        ),
        isNull,
      );
    });

    test('a pre-release pin is an exact version too', () {
      const json = '{"flutter": "3.48.0-0.1.pre"}';
      expect(
        FlutterPinCheck.compare(justJson: json, running: '3.48.0-0.1.pre'),
        isNull,
      );
      expect(
        FlutterPinCheck.compare(justJson: json, running: '3.47.9')?.pinned,
        '3.48.0-0.1.pre',
      );
    });

    test('no just.json, or no pin in it: nothing to say', () {
      expect(
        FlutterPinCheck.compare(justJson: null, running: '3.48.0'),
        isNull,
      );
      expect(
        FlutterPinCheck.compare(
          justJson: '{"schema": 1, "title": "Game"}',
          running: '3.48.0',
        ),
        isNull,
      );
    });

    test('a just.json that is not a JSON object: nothing to say', () {
      for (final text in ['{"flutter": "3.47.9"', '', '["3.47.9"]', 'null']) {
        expect(
          FlutterPinCheck.compare(justJson: text, running: '3.48.0'),
          isNull,
          reason: text,
        );
      }
    });

    test('a pin that is not one exact version: nothing to say', () {
      for (final value in [
        '"^3.47.0"',
        '">=3.47.0"',
        '"stable"',
        '"3.47"',
        '"3.47.9+1"',
        '""',
        '3.47',
        'null',
        '{"version": "3.47.9"}',
      ]) {
        expect(
          FlutterPinCheck.compare(
            justJson: '{"flutter": $value}',
            running: '3.48.0',
          ),
          isNull,
          reason: value,
        );
      }
    });

    test('no running version: nothing to say', () {
      expect(FlutterPinCheck.compare(justJson: _pinned, running: null), isNull);
      expect(FlutterPinCheck.compare(justJson: _pinned, running: ' '), isNull);
    });
  });

  test('isExactVersion', () {
    expect(FlutterPinCheck.isExactVersion('3.47.9'), isTrue);
    expect(FlutterPinCheck.isExactVersion('3.48.0-0.1.pre'), isTrue);
    expect(FlutterPinCheck.isExactVersion('10.0.12'), isTrue);
    expect(FlutterPinCheck.isExactVersion('v3.47.9'), isFalse);
    expect(FlutterPinCheck.isExactVersion('3.47.x'), isFalse);
    expect(FlutterPinCheck.isExactVersion('3.48.0-'), isFalse);
  });

  test('flutterVersionIn reads package_config.json', () {
    expect(
      FlutterPinCheck.flutterVersionIn(_packageConfig('3.47.9')),
      '3.47.9',
    );
    expect(FlutterPinCheck.flutterVersionIn('{"configVersion": 2}'), isNull);
    expect(FlutterPinCheck.flutterVersionIn('{"flutterVersion": 3}'), isNull);
    expect(FlutterPinCheck.flutterVersionIn('not json'), isNull);
    expect(FlutterPinCheck.flutterVersionIn(null), isNull);
  });

  group('read', () {
    test('the pin in just.json against the running Flutter', () {
      final root = _project({'just.json': _pinned});
      expect(
        FlutterPinCheck.read(root, running: '3.48.0'),
        const FlutterPinMismatch(pinned: '3.47.9', running: '3.48.0'),
      );
      expect(FlutterPinCheck.read(root, running: '3.47.9'), isNull);
      // A Windows path reads the same.
      expect(
        FlutterPinCheck.read(
          root.replaceAll('/', r'\'),
          running: '3.48.0',
        )?.pinned,
        '3.47.9',
      );
    });

    test('no running version: the one package_config.json names', () {
      final other = _project({
        'just.json': _pinned,
        '.dart_tool/package_config.json': _packageConfig('3.48.0'),
      });
      expect(
        FlutterPinCheck.read(other, running: null),
        const FlutterPinMismatch(pinned: '3.47.9', running: '3.48.0'),
      );
      final same = _project({
        'just.json': _pinned,
        '.dart_tool/package_config.json': _packageConfig('3.47.9'),
      });
      expect(FlutterPinCheck.read(same, running: null), isNull);
    });

    test('nothing readable: nothing to say', () {
      // No package_config.json to fall back on.
      expect(
        FlutterPinCheck.read(_project({'just.json': _pinned}), running: null),
        isNull,
      );
      // No just.json.
      expect(FlutterPinCheck.read(_project({}), running: '3.48.0'), isNull);
      // A malformed one.
      expect(
        FlutterPinCheck.read(
          _project({'just.json': '{"flutter": '}),
          running: '3.48.0',
        ),
        isNull,
      );
    });
  });

  group('in the editor', () {
    test('read once per scope', () {
      final scope = testScope();
      final root = _project({'just.json': _pinned});
      final check = FlutterPinCheck(projectRoot: root, running: '3.48.0');
      scope.container.registerSingleton<FlutterPinCheck>(check);
      expect(FlutterPinCheck.of(scope), same(check));
      expect(check.mismatch?.pinned, '3.47.9');
      // Changed on disk: the session keeps what it read.
      File('$root/just.json').writeAsStringSync('{"flutter": "3.48.0"}');
      expect(FlutterPinCheck.of(scope).mismatch?.pinned, '3.47.9');
    });

    test('the check of a scope reads its project folder', () {
      final root = _project({'just.json': _pinned});
      final scope = EditorScope(
        world: World()..initialize(),
        projectRoot: root,
      );
      addTearDown(scope.dispose);
      expect(FlutterPinCheck.of(scope).projectRoot, root.replaceAll(r'\', '/'));
    });

    testWidgets('Problems lists it, and its fix copies the command', (
      tester,
    ) async {
      final scope = testScope();
      scope.container.registerSingleton<FlutterPinCheck>(
        FlutterPinCheck(
          projectRoot: _project({'just.json': _pinned}),
          running: '3.48.0',
        ),
      );
      scope.sceneState.openScene(EditorScene(name: 'level'));
      final problems = ProblemScan.of(scope).problems;
      final pin = problems.singleWhere((p) => p.message.contains('3.47.9'));
      expect(pin.severity, ProblemSeverity.warning);
      expect(pin.hint, contains('just sdk install'));
      expect(pin.fixes.map((f) => f.label), ['Copy command']);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      pin.fixes.single.apply();
      await tester.pump();
      expect(copied, 'just sdk install');
    });

    test('the pinned Flutter: not in Problems', () {
      final scope = testScope();
      scope.container.registerSingleton<FlutterPinCheck>(
        FlutterPinCheck(
          projectRoot: _project({'just.json': _pinned}),
          running: '3.47.9',
        ),
      );
      final context = ValidationContext(scope: scope);
      expect(FlutterPinCheck.problems(context), isEmpty);
    });

    testWidgets('the log says it at start, and a message once per pin', (
      tester,
    ) async {
      if (!kDebugMode) return;
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      final store = MemorySettingsStore();
      final scope = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        engine: engine,
        settingsStore: store,
      );
      scope.container.registerSingleton<FlutterPinCheck>(
        FlutterPinCheck(
          projectRoot: _project({'just.json': _pinned}),
          running: '3.48.0',
        ),
      );
      final plugin = JustGameEditorPlugin(engine: engine, scope: scope);
      await tester.runAsync(() => plugin.attach(plugin.engine));

      final logged = scope.log.entries.value.where(
        (e) => e.category == 'project',
      );
      expect(logged, hasLength(1));
      expect(logged.single.level, DebuggerLogLevel.warning);
      expect(logged.single.message, contains('Flutter 3.48.0'));
      expect(logged.single.details, contains('just sdk install'));

      Widget overlay() => MaterialApp(
        home: Scaffold(
          body: EditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      );
      plugin.setVisible(true);
      await tester.pumpWidget(overlay());
      await tester.pumpAndSettle();
      expect(find.text('This project pins Flutter 3.47.9'), findsOneWidget);
      expect(store.values[FlutterPinCheck.shownPref.key], '3.47.9');

      // Shown for this pin: not again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(overlay());
      await tester.pumpAndSettle();
      expect(find.text('This project pins Flutter 3.47.9'), findsNothing);

      plugin.playController.stop();
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
      scope.dispose();
    });
  });
}
