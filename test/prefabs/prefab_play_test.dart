// A prefab instance while the game runs on the level, and the inspector's
// section on it: Apply, Revert, Unpack, Make and Edit wait for Stop, since
// what an instance changes then is what the game did to it; the section
// reads the instance afresh, so an Unpack never leaves it holding one that
// is gone; and what an instance changes is worked out once per step, not on
// every pointer move of a drag.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/inspector/entity_inspector_panel.dart';
import 'package:just_game_engine_editor/src/prefabs/prefab_inspector.dart';
import 'package:just_game_engine_editor/src/prefabs/prefab_instances.dart';

import '../support/test_scope.dart';

Map<String, dynamic> _transform(double x, double y) => {
  'type': 'TransformComponent',
  'fields': {
    'position': {'x': x, 'y': y, 'z': 0.0},
  },
};

const _crate = 'assets/prefabs/crate.prefab.json';

final _crateFile = PrefabFile(
  name: 'Crate',
  entities: [
    PrefabEntity(
      id: 'box',
      name: 'Box',
      components: [
        _transform(0, 0),
        {
          'type': 'HealthComponent',
          'fields': {'maxHealth': 3, 'health': 3},
        },
      ],
    ),
    PrefabEntity(
      id: 'lid',
      name: 'Lid',
      parent: 'box',
      components: [_transform(0, -1)],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late EditorScope scope;
  late PrefabInstances prefabs;
  late File file;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('jge_prefab_play');
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}/$_crate')
      ..createSync(recursive: true)
      ..writeAsStringSync(_crateFile.encode());
    scope = testScope();
    prefabs = PrefabInstances(scope, root: dir.path);
    scope.container.registerSingleton<PrefabInstances>(prefabs);
    scope.context.overrideLoaders(
      prefabs: (path) async =>
          PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
    );
    scope.sceneState.openScene(
      EditorScene(name: 'yard', mode: SceneMode.threeD),
    );
    await prefabs.library.load(_crate);
  });

  Entity named(String name) =>
      scope.world.entities.firstWhere((e) => e.isAlive && e.name == name);

  group('during a play-test', () {
    late Entity top;
    late String before;

    setUp(() {
      top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
      before = file.readAsStringSync();
      scope.isPlayTesting.value = true;
      // The game runs the crate down.
      top.getComponent<HealthComponent>()!.health = 0;
    });

    test('Apply writes nothing into the prefab', () async {
      expect(await prefabs.apply(top), isFalse);
      expect(file.readAsStringSync(), before);
      expect(
        scope.log.entries.value.map((e) => e.message),
        contains(contains('stop the play-test first')),
      );
    });

    test('Revert, Unpack and Edit change nothing', () {
      final steps = scope.history.undoDepth;
      prefabs
        ..revertAll(top)
        ..revertField(top, 'box', 'HealthComponent', 'health')
        ..unpack(top)
        ..edit(top);
      expect(scope.history.undoDepth, steps);
      expect(top.hasComponent<PrefabInstanceComponent>(), isTrue);
      expect(prefabs.editing.value, isNull);
    });

    test('Make makes no prefab file', () async {
      final plain = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Barrel');
      expect(await prefabs.makePrefab(plain), isNull);
      expect(Directory('${dir.path}/${PrefabInstances.folder}').listSync(), [
        isA<File>().having(
          (f) => f.path.replaceAll(r'\', '/'),
          'path',
          endsWith(_crate),
        ),
      ]);
    });

    test('prefab mode is not left with Apply', () async {
      scope.isPlayTesting.value = false;
      prefabs.edit(top);
      scope.isPlayTesting.value = true;
      expect(await prefabs.leave(apply: true), isFalse);
      expect(prefabs.editing.value, top.id, reason: 'still editing it');
      expect(file.readAsStringSync(), before);
    });

    test('the prefab commands are off', () {
      scope.sceneState.selectEntity(top);
      final context = CommandContext(
        scope: scope,
        modifiers: const ModifierKeys(),
      );
      for (final id in [
        'editor.prefab.make',
        'editor.prefab.edit',
        'editor.prefab.apply',
        'editor.prefab.revert',
        'editor.prefab.unpack',
      ]) {
        expect(
          scope.commands.byId(id)!.isEnabled!(context),
          isFalse,
          reason: id,
        );
      }
      scope.isPlayTesting.value = false;
      expect(
        scope.commands.byId('editor.prefab.apply')!.isEnabled!(context),
        isTrue,
      );
    });

    testWidgets('the inspector counts nothing and offers nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: EditorScopeProvider(
                scope: scope,
                child: Builder(
                  builder: (context) =>
                      PrefabInspector.section.build(context, top, scope),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('A play-test is running'), findsOneWidget);
      for (final label in ['Apply all', 'Revert all', 'Unpack']) {
        final button = tester.widget<EditorButton>(
          find.widgetWithText(EditorButton, label),
        );
        expect(button.onPressed, isNull, reason: label);
      }
    });
  });

  group('the inspector section', () {
    Future<void> pumpInspector(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(500, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: EntityInspectorPanel(
                sceneState: scope.sceneState,
                world: scope.world,
                scope: scope,
                onGroupSelection: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('Unpack within the inspector\'s cool-down after another '
        'change builds without an error', (tester) async {
      final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
      scope.sceneState.selectEntity(top);
      await pumpInspector(tester);
      await tester.pump(const Duration(seconds: 1));
      // Something changed the scene a moment ago: the inspector is cooling
      // down for 100 ms, and only the section's own builder runs next.
      scope.sceneState.refresh();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Unpack'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(top.hasComponent<PrefabInstanceComponent>(), isFalse);
      expect(find.text('Unpack'), findsNothing);
    });

    test('what an instance changes is worked out again per step, not per '
        'move of a drag', () {
      final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
      final first = PrefabInspector.changesOf(scope, top);
      // A drag: the scene's revision moves on every pointer move.
      scope.sceneState
        ..setPosition3(named('Lid'), Vector3(5, -4, 0))
        ..refresh();
      expect(PrefabInspector.changesOf(scope, top), same(first));

      // Let go: one step.
      scope.history.push(
        CallbackCommand(label: 'Move Lid', onRedo: () {}, onUndo: () {}),
      );
      final after = PrefabInspector.changesOf(scope, top)!;
      expect(after, isNot(same(first)));
      expect(after.overrides.map((o) => o.target), contains('lid'));
    });

    test('and again when its instances are made again', () async {
      final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
      final first = PrefabInspector.changesOf(scope, top);
      await prefabs.refresh(_crate);
      expect(PrefabInspector.changesOf(scope, top), isNot(same(first)));
    });

    test('an instance unpacked has no changes to show', () {
      final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
      prefabs.unpack(top);
      expect(prefabs.changesOf(top), isNull);
      expect(PrefabInspector.changesOf(scope, top), isNull);
    });
  });
}
