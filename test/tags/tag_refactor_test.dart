// Renaming a tag rewrites files across the project, so it says what it
// could not read rather than skipping it, keeps the timelines it rewrites
// (in the line endings they had), and does not run during a play-test,
// whose Stop would put the old values back.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/tags/tag_refactor.dart';

import '../support/test_scope.dart';

void main() {
  late Directory root;
  late EditorScope scope;

  String scenesRoot() => '${root.path}/assets/scenes';

  setUp(() {
    root = Directory.systemTemp.createTempSync('tag_refactor_');
    Directory(scenesRoot()).createSync(recursive: true);
    scope = testScope(scenesRoot: scenesRoot());
    scope.tags.create('coin');
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold it a moment longer.
    }
  });

  void writeScene(String name, String text) =>
      File('${scenesRoot()}/$name.scene.json').writeAsStringSync(text);

  test(
    'a scene that cannot be read is listed and reported, not skipped',
    () async {
      writeScene('broken', '{"entities": [,]}');
      final refactor = TagRefactor(scope, projectRoot: root.path);
      final plan = refactor.plan('coin', renameTo: 'gem');
      expect(plan.unreadable, ['broken']);
      final result = await refactor.apply(plan);
      expect(result.failures.keys, contains('broken'));
    },
  );

  test(
    'a timeline it rewrites is kept first, and keeps its line endings',
    () async {
      final original = const JsonEncoder.withIndent('    ')
          .convert({
            'formatVersion': 2,
            'tracks': [
              {
                'kind': 'event',
                'binding': {'tag': 'coin'},
                'events': <Object>[],
              },
            ],
          })
          .replaceAll('\n', '\r\n');
      final timeline = File('${root.path}/assets/timelines/bob.timeline.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(original);

      final refactor = TagRefactor(scope, projectRoot: root.path);
      final result = await refactor.apply(
        refactor.plan('coin', renameTo: 'gem'),
      );

      expect(result.failures, isEmpty);
      final text = timeline.readAsStringSync();
      expect(text, contains('"gem"'));
      expect(text.contains('\r\n'), isTrue);
      expect(text.replaceAll('\r\n', '').contains('\n'), isFalse);
      final kept = Directory(
        '${root.path}/${TagRefactor.timelineBackups}',
      ).listSync().whereType<File>().single;
      expect(kept.readAsStringSync(), original);
    },
  );

  test('during a play-test it changes nothing, and says so', () async {
    writeScene(
      'level_02',
      jsonEncode({
        'version': SceneFormat.current,
        'name': 'level_02',
        'entities': [
          {
            'name': 'Coin',
            'components': [
              {
                'type': 'TagComponent',
                'fields': {
                  'tags': ['coin'],
                },
              },
            ],
          },
        ],
      }),
    );
    final before = File(
      '${scenesRoot()}/level_02.scene.json',
    ).readAsStringSync();
    scope.isPlayTesting.value = true;
    final refactor = TagRefactor(scope, projectRoot: root.path);
    final result = await refactor.apply(refactor.plan('coin', renameTo: 'gem'));
    expect(result.failures.keys, ['play-test']);
    expect(result.filesWritten, isEmpty);
    expect(scope.tags.names, contains('coin'));
    expect(
      File('${scenesRoot()}/level_02.scene.json').readAsStringSync(),
      before,
    );
  });
}
