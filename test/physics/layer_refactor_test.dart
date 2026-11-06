// Deleting a physics layer rewrites files across the project, so it says
// what it could not read rather than skipping it, and does not run during a
// play-test, whose Stop would put the old values back.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/physics/layer_refactor.dart';

import '../support/test_scope.dart';

void main() {
  late Directory root;
  late EditorScope scope;

  String scenesRoot() => '${root.path}/assets/scenes';

  setUp(() {
    root = Directory.systemTemp.createTempSync('layer_refactor_');
    Directory(scenesRoot()).createSync(recursive: true);
    scope = testScope(scenesRoot: scenesRoot());
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may hold it a moment longer.
    }
  });

  test(
    'a scene that cannot be read is listed and reported, not skipped',
    () async {
      File('${scenesRoot()}/broken.scene.json').writeAsStringSync('[]');
      final refactor = LayerRefactor(scope);
      final plan = refactor.plan(3);
      expect(plan.unreadable, ['broken']);
      final result = await refactor.apply(plan);
      expect(result.failures.keys, contains('broken'));
    },
  );

  test('during a play-test it changes nothing', () async {
    scope.isPlayTesting.value = true;
    final refactor = LayerRefactor(scope);
    final result = await refactor.apply(refactor.plan(3));
    expect(result.failures.keys, ['play-test']);
  });
}
