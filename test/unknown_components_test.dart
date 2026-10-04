// A scene can name a component nothing registered can read — a module that
// is not loaded this session, or one that moved to another package. The
// editor used to drop it on open, and the next save deleted it for good.
// It is kept now, reported, and written back as it came.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

const _stranger = {
  'type': 'SomeoneElsesComponent',
  'fields': {'speed': 3, 'label': 'kept'},
};

const _other = {'type': 'AnotherUnknown', 'fields': <String, dynamic>{}};

const _transform = {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': 4.0, 'y': 8.0},
  },
};

void main() {
  group('the codec', () {
    final codec = SceneCodec(ComponentDefinitionRegistry.core());

    test('keeps every unknown component in one holder', () {
      final components = codec.decodeAll([_stranger, _transform, _other]);

      expect(components.whereType<TransformComponent>(), hasLength(1));
      final unknown = components.whereType<UnknownComponents>().single;
      expect(unknown.types, ['SomeoneElsesComponent', 'AnotherUnknown']);
    });

    test('writes them back exactly as they were read', () {
      final written = codec.encodeAll(
        codec.decodeAll([_stranger, _transform, _other]),
      );

      expect(written, containsAll([_stranger, _other]));
      expect(written.map((c) => c['type']), contains('TransformComponent'));
    });

    test('counts them as saved, so an edit that drops them removes them', () {
      expect(codec.canEncode(UnknownComponents([_stranger])), isTrue);
    });
  });

  group('in a scene', () {
    late Directory project;
    late EditorScope scope;
    late SceneIO io;

    String sceneFile() => '${project.path}/assets/scenes/level_test.scene.json';

    setUp(() {
      project = Directory.systemTemp.createTempSync('unknown_components');
      Directory('${project.path}/assets/scenes').createSync(recursive: true);
      File(sceneFile()).writeAsStringSync(
        jsonEncode({
          'version': SceneFormat.current,
          ...EditorScene(name: 'level_test').toJson(),
          'entities': [
            {
              'name': 'Mixed',
              'parentName': null,
              'components': [_transform, _stranger],
            },
            {
              // Nothing on it can be read at all: it still exists.
              'name': 'Stranger',
              'parentName': 'Mixed',
              'components': [_other],
            },
          ],
        }),
      );
      File('${project.path}/assets/scenes/scenes.json').writeAsStringSync(
        jsonEncode({
          'scenes': ['level_test'],
        }),
      );
      scope = testScope(scenesRoot: '${project.path}/assets/scenes');
      io = SceneIO(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
      );
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
    });

    test('opening keeps them, and the entity that is nothing else', () async {
      await io.open('level_test');

      final mixed = scope.world.findEntityByName('Mixed')!;
      final stranger = scope.world.findEntityByName('Stranger')!;
      expect(mixed.getComponent<UnknownComponents>()!.types, [
        'SomeoneElsesComponent',
      ]);
      expect(mixed.hasComponent<TransformComponent>(), isTrue);
      expect(
        stranger.getComponent<ParentComponent>()?.parentId,
        mixed.id,
        reason: 'still linked to its parent',
      );
    });

    test('saving writes them back', () async {
      await io.open('level_test');
      await io.save();

      final saved = jsonDecode(File(sceneFile()).readAsStringSync());
      final entities = (saved['entities'] as List).cast<Map>();
      final mixed = entities.firstWhere((e) => e['name'] == 'Mixed');
      final stranger = entities.firstWhere((e) => e['name'] == 'Stranger');
      expect(mixed['components'], contains(equals(_stranger)));
      expect(stranger['components'], contains(equals(_other)));
      expect(stranger['parentName'], 'Mixed');
    });

    test('a delete undone brings them back', () async {
      await io.open('level_test');
      final mixed = scope.world.findEntityByName('Mixed')!;

      scope.history.push(
        DeleteEntitiesCommand(
          label: 'Delete Mixed',
          world: scope.world,
          sceneState: scope.sceneState,
          entities: [mixed],
          codec: scope.codec,
        ),
      );
      scope.history.undo();

      final back = scope.world.findEntityByName('Mixed')!;
      expect(back.getComponent<UnknownComponents>()!.entries, [_stranger]);
    });

    test('each one is reported as a problem', () async {
      await io.open('level_test');

      final problems = BuiltInValidators.unknownComponents(
        ValidationContext(scope: scope, projectRoot: project.path),
      );

      expect(problems.map((p) => p.entity?.name), ['Mixed', 'Stranger']);
      expect(problems.first.message, contains('SomeoneElsesComponent'));
      expect(problems.first.severity, ProblemSeverity.error);
    });
  });
}
