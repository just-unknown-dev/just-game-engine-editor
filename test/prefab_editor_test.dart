// Prefabs in the editor's hands: placed from the palette (undone and done
// again, still an instance), dropped from the Assets dock, edited as the
// prefab with the rest of the scene hidden, and shown in the inspector —
// its section, and a mark on each changed field with Revert.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/prefabs/prefab_files.dart';
import 'package:just_game_engine_editor/src/ui/inspector/prefab_inspector.dart';

import 'support/test_scope.dart';

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
        {'type': 'TagComponent', 'fields': {'tags': ['crate']}},
      ],
    ),
    PrefabEntity(id: 'lid', name: 'Lid', parent: 'box', components: [_transform(0, -1)]),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late EditorScope scope;
  late PrefabInstances prefabs;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('jge_prefab_editor');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/$_crate')
      ..createSync(recursive: true)
      ..writeAsStringSync(_crateFile.encode());
    scope = testScope();
    // Its files in the test's folder, not the package's.
    prefabs = PrefabInstances(scope, root: dir.path);
    scope.container.registerSingleton<PrefabInstances>(prefabs);
    scope.context.overrideLoaders(
      prefabs: (path) async => PrefabFile.parse(File('${dir.path}/$path').readAsStringSync()),
    );
    scope.sceneState.openScene(EditorScene(name: 'yard', mode: SceneMode.threeD));
    await prefabs.library.load(_crate);
  });

  Entity named(String name) => scope.world.entities.firstWhere((e) => e.isAlive && e.name == name);

  test('placed from the palette: an instance, still one after undo and redo', () {
    final entry = PrefabDefinition(
      id: 'file:$_crate',
      name: 'Crate',
      category: PrefabFiles.category,
      icon: Icons.inventory_2_outlined,
      color: PrefabFiles.color,
      dimensions: Dimensions.both,
      instanceOf: _crate,
      build: (_, _) => const [],
    );
    final top = scope.entities.spawnPrefab(entry, SurfacePoint(Vector3(4, 0, 2), Vector3(0, -1, 0)), spin: 90);
    scope.entities.recordPlaced([top], 'Place Crate');
    expect(top.hasComponent<PrefabInstanceComponent>(), isTrue);
    final at = top.getComponent<TransformComponent>()!.position;
    expect([at.x, at.z], [4, 2]);
    expect(top.getComponent<TransformComponent>()!.eulerY.abs(), closeTo(math.pi / 2, 1e-6));

    scope.history.undo();
    expect(scope.world.entities.where((e) => e.isAlive), isEmpty);
    scope.history.redo();
    final again = scope.world.entities.firstWhere((e) => e.isAlive && e.hasComponent<PrefabInstanceComponent>());
    expect(again.getComponent<TransformComponent>()!.position.x, closeTo(4, 1e-6));
    expect(named('Lid').getComponent<PrefabLink>()!.instance, again.id);
  });

  test('dropped from the Assets dock where it landed', () {
    final top = PrefabFiles.drop(
      AssetDrop(
        scope: scope,
        path: _crate,
        at: Vector3(1, 0, 1),
        surface: SurfacePoint(Vector3(1, 0, 1), Vector3(0, -1, 0)),
        place: (_, _) => throw StateError('an instance is made, not one entity'),
      ),
    )!;
    expect(top.hasComponent<PrefabInstanceComponent>(), isTrue);
    expect(scope.history.undoEntries, hasLength(1));
    expect(PrefabFiles.kind.matches('assets/prefabs/crate.prefab.json'), isTrue);
  });

  test('edited as the prefab: the rest hidden; left with Apply, written', () async {
    final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
    final other = scope.world.createEntityWithComponents([TransformComponent()], name: 'Other');
    scope.sceneState.registerEntity(other);
    prefabs.edit(top);
    expect(prefabs.editing.value, top.id);
    expect(scope.view.isHiddenIn(other), isTrue);
    expect(scope.view.isHiddenIn(named('Lid')), isFalse);

    top.getComponent<TagComponent>()!.tags = {'crate', 'heavy'};
    expect(await prefabs.leave(apply: true), isTrue);
    expect(prefabs.editing.value, isNull);
    expect(scope.view.isHiddenIn(other), isFalse);
    final written = PrefabFile.parse(File('${dir.path}/$_crate').readAsStringSync());
    final tags = written.root.components.firstWhere((c) => c['type'] == 'TagComponent')['fields'] as Map;
    expect(tags['tags'], containsAll(['crate', 'heavy']));
  });

  testWidgets('the inspector: its section, a mark on what changed, Revert', (tester) async {
    final top = prefabs.place(_crate, at: Vector3(5, 0, 0))!;
    final lid = named('Lid');
    scope.sceneState.setPosition3(lid, Vector3(5, -3, 0));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: EditorScopeProvider(
              scope: scope,
              child: Builder(builder: (context) => PrefabInspector.section.build(context, lid, scope)),
            ),
          ),
        ),
      ),
    );
    expect(find.text(_crate), findsOneWidget);
    expect(find.textContaining('1 change'), findsOneWidget);
    expect(find.text('Select the instance'), findsOneWidget);

    final definition = scope.definitions.definitionFor(lid.getComponent<TransformComponent>()!)!;
    final mark = PrefabInspector.marks.build!(
      FieldAccessoryContext(
        scope: scope,
        entity: lid,
        component: lid.getComponent<TransformComponent>()!,
        definition: definition,
        fields: definition.fields.where((f) => f.name == 'position').toList(),
      ),
    );
    expect(mark, isNotNull);
    final topMark = PrefabInspector.marks.build!(
      FieldAccessoryContext(
        scope: scope,
        entity: top,
        component: top.getComponent<TransformComponent>()!,
        definition: definition,
        fields: definition.fields.where((f) => f.name == 'position').toList(),
      ),
    );
    expect(topMark, isNull, reason: 'where the instance stands is not a change');

    await tester.tap(find.text('Revert all'));
    await tester.pump();
    expect(named('Lid').getComponent<TransformComponent>()!.position.y, closeTo(-1, 1e-6));
    expect(tester.takeException(), isNull);
  });
}
