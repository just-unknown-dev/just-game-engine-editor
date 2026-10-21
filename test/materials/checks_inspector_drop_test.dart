// What the editor says about a scene's materials and how it puts them
// right; an entity's own material values edited in the inspector; and a
// 2-D material dropped on what it should draw.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String root;
  late EditorScope scope;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_checks');
    root = dir.path.replaceAll(r'\', '/');
    final world = World()..initialize();
    Graphics3D.registerSchemas(world.context);
    scope = EditorScope(world: world, modules: const []);
    addTearDown(scope.dispose);
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  void write(String path, Object json) => File('$root/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(json is String ? json : jsonEncode(json));

  List<SceneProblem> check() => [
    for (final v in MaterialChecks.all)
      ...v(ValidationContext(scope: scope, projectRoot: root)),
  ];

  Entity sprite(String name, {String? material, bool drawn = true}) =>
      scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 100, 0)),
        // As the editor places a rectangle: a renderable with a size.
        if (drawn) RectangleComponent(width: 40, height: 40),
        if (material != null) Material2D(material: material),
      ], name: name);

  group('the checks', () {
    test('a clean scene says nothing', () {
      write('fx/flash.material2d.json', {
        'flash': {'amount': 1},
      });
      sprite('Hero', material: 'fx/flash.material2d.json');
      expect(check(), isEmpty);
    });

    test('a screen material on a sprite: made its screen material', () {
      write('fx/crt.material2d.json', {
        'kind': 'screen',
        'crt': {'curvature': 0.1},
      });
      final hero = sprite('Hero', material: 'fx/crt.material2d.json');
      final problem = check().single;
      expect(problem.message, contains('a screen material'));
      problem.fixes.single.apply();
      expect(hero.hasComponent<Material2D>(), isFalse);
      expect(
        hero.getComponent<ScreenMaterial>()!.material,
        'fx/crt.material2d.json',
      );
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(hero.hasComponent<Material2D>(), isTrue);
      expect(hero.hasComponent<ScreenMaterial>(), isFalse);
    });

    test('a 2D material on something that draws nothing: removed', () {
      write('fx/flash.material2d.json', {'flash': {}});
      final ghost = sprite(
        'Ghost',
        material: 'fx/flash.material2d.json',
        drawn: false,
      );
      final problem = check().single;
      expect(problem.message, contains('draws nothing'));
      problem.fixes.single.apply();
      expect(ghost.hasComponent<Material2D>(), isFalse);
    });

    test('a normal map with no Scene lighting: lighting added', () {
      write('fx/bumpy.material2d.json', {
        'normalMap': {'map': 'n.png'},
      });
      write('n.png', 'not really');
      sprite('Rock', material: 'fx/bumpy.material2d.json');
      final problem = check().single;
      expect(problem.message, contains('Scene lighting'));
      problem.fixes.single.apply();
      expect(scope.world.query(const [Lighting2D]), hasLength(1));
      expect(check(), isEmpty);
    });

    test("a material's own problems are said once, for every user", () {
      write('fx/child.material2d.json', {'parent': 'fx/gone.material2d.json'});
      sprite('A', material: 'fx/child.material2d.json');
      sprite('B', material: 'fx/child.material2d.json');
      final problems = check();
      expect(problems, hasLength(1));
      expect(problems.single.message, contains('missing'));
    });

    test('two screen materials on: the lower one is said', () {
      write('fx/a.material2d.json', {'kind': 'screen'});
      final low = scope.world.createEntityWithComponents([
        ScreenMaterial(material: 'fx/a.material2d.json'),
      ], name: 'Low');
      scope.world.createEntityWithComponents([
        ScreenMaterial(material: 'fx/a.material2d.json', order: 2),
      ], name: 'High');
      final problem = check().single;
      expect(problem.entity, low);
      expect(problem.message, contains('High'));
    });

    test('own values no effect has: removed', () {
      write('fx/flash.material2d.json', {'flash': {}});
      final hero = sprite('Hero', material: 'fx/flash.material2d.json');
      hero.getComponent<Material2D>()!
        ..set('flash.amount', 0.5)
        ..set('nothing.here', 1.0);
      final problem = check().single;
      expect(problem.message, contains('nothing.here'));
      problem.fixes.single.apply();
      expect(hero.getComponent<Material2D>()!.overrides, {'flash.amount': 0.5});
    });

    test("a Level Map layer's missing material", () {
      final data = LevelMapData();
      data.addLayer(name: 'Water').material = 'fx/water.material2d.json';
      scope.world.createEntityWithComponents([
        TransformComponent(),
        LevelMapComponent(inline: data),
      ], name: 'Level Map');
      final problem = check().single;
      expect(problem.severity, ProblemSeverity.error);
      expect(problem.message, contains('water.material2d.json'));
    });

    test("3-D: a model's missing material; values a game can't change", () {
      final model = ModelComponent(
        model: 'm.glb',
        materials: {'*': 'gone.material.json'},
      );
      final lamp = scope.world.createEntityWithComponents([
        TransformComponent(),
        model,
        MaterialOverrides3D(values: {'roughness': 0.2, 'colourMap': 'x'}),
      ], name: 'Lamp');
      final problems = check();
      expect(problems, hasLength(2));
      final missing = problems.firstWhere(
        (p) => p.severity == ProblemSeverity.error,
      );
      missing.fixes.single.apply();
      expect(model.materials, isEmpty);
      final unknown = problems.firstWhere(
        (p) => p.message.contains('colourMap'),
      );
      unknown.fixes.single.apply();
      expect(lamp.getComponent<MaterialOverrides3D>()!.values, {
        'roughness': 0.2,
      });
    });
  });

  group('the inspector', () {
    late Directory was;

    setUp(() {
      was = Directory.current;
      Directory.current = dir;
      addTearDown(() => Directory.current = was);
    });

    Future<List<Object?>> pump(
      WidgetTester tester,
      Component component,
      Object? value, {
      required bool flat,
    }) async {
      final changes = <Object?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: MaterialOverridesEditor(
                flat: flat,
                context: FieldEditorContext(
                  field: SchemaField(
                    name: flat ? 'overrides' : 'values',
                    kind: flat
                        ? MaterialOverridesFieldType.material2D
                        : MaterialOverridesFieldType.material3D,
                    read: (_) => value,
                  ),
                  hint: const FieldHint(label: 'Own values'),
                  value: value,
                  component: component,
                  onChanged: changes.add,
                  editors: scope.fieldEditors,
                  world: scope.world,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('the module brings them for both kinds', (tester) async {
      final module = BuiltInMaterialsModule(root: root);
      addTearDown(module.dispose);
      expect(module.fieldEditors.keys, {
        'material2DOverrides',
        'material3DOverrides',
      });
    });

    testWidgets("2-D: what can be added is its material's effects' values", (
      tester,
    ) async {
      write('fx/hit.material2d.json', {
        'flash': {'colour': 0xFFFF0000, 'amount': 0.25},
      });
      final m = Material2D(material: 'fx/hit.material2d.json');
      final editor = MaterialOverridesEditor(
        flat: true,
        context: FieldEditorContext(
          field: SchemaField(
            name: 'overrides',
            kind: MaterialOverridesFieldType.material2D,
            read: (_) => null,
          ),
          hint: const FieldHint(),
          value: const <String, Object>{},
          component: m,
          onChanged: (_) {},
          editors: scope.fieldEditors,
        ),
      );
      expect(editor.addable, ['flash.colour', 'flash.amount']);
      expect(editor.startOf('flash.amount'), 0.25, reason: "the material's");
      final changes = await pump(
        tester,
        m,
        const <String, Object>{},
        flat: true,
      );
      expect(find.textContaining("its material's own values"), findsOne);
      await tester.tap(find.text('Add a value of its own…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flash: Amount').last);
      await tester.pumpAndSettle();
      expect(changes.single, {'flash.amount': 0.25});
    });

    testWidgets('2-D: a value shown with its editor, and removed', (
      tester,
    ) async {
      write('fx/hit.material2d.json', {'flash': {}});
      final m = Material2D(material: 'fx/hit.material2d.json');
      final changes = await pump(tester, m, {
        'flash.amount': 0.5,
        'flash.colour': 0xFF00FF00,
      }, flat: true);
      expect(find.text('Flash: Amount'), findsOneWidget);
      expect(find.text('Flash: Colour'), findsOneWidget);
      expect(find.byType(EditorSlider), findsOneWidget);
      await tester.tap(find.byTooltip("Use the material's own").first);
      await tester.pump();
      expect(changes.single, {'flash.colour': 0xFF00FF00});
    });

    testWidgets("3-D: its shape's material starts the values", (tester) async {
      write(
        'stone.material.json',
        const MaterialFile(roughness: 0.7, tilingX: 2).encode(),
      );
      final overrides = MaterialOverrides3D();
      final cube = Cube3D(material: 'stone.material.json');
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
        cube,
        overrides,
      ]);
      scope.sceneState.selectedEntity.value = e;
      final editor = MaterialOverridesEditor(
        flat: false,
        context: FieldEditorContext(
          field: SchemaField(
            name: 'values',
            kind: MaterialOverridesFieldType.material3D,
            read: (_) => null,
          ),
          hint: const FieldHint(),
          value: const <String, Object>{},
          component: overrides,
          onChanged: (_) {},
          editors: scope.fieldEditors,
          world: scope.world,
          sceneState: scope.sceneState,
        ),
      );
      expect(editor.startOf('roughness'), 0.7);
      expect(editor.startOf('tiling'), [2.0, 1.0]);
      expect(editor.addable, MaterialFile.animatableKeys);
      await pump(tester, overrides, {
        'tiling#0': 3.0,
        'color': 0xFF112233,
      }, flat: false);
      expect(find.text('Repeat (across)'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('a 2-D drop', () {
    late BuiltInMaterialsModule module;
    late List<String> placed;

    setUp(() {
      module = BuiltInMaterialsModule(root: root);
      addTearDown(module.dispose);
      placed = [];
    });

    AssetDrop drop(String path, double x, double y) => AssetDrop(
      scope: scope,
      path: path,
      at: Vector3(x, y, 0),
      place: (components, name) {
        placed.add(name ?? '?');
        return scope.world.createEntityWithComponents(components, name: name);
      },
    );

    test('on a sprite: drawn with it, one undo step; again: changed', () {
      write('fx/a.material2d.json', {'flash': {}});
      write('fx/b.material2d.json', {'tint': {}});
      final hero = sprite('Hero');
      expect(
        module.dropMaterial2D(drop('fx/a.material2d.json', 105, 95)),
        isNull,
      );
      expect(hero.getComponent<Material2D>()!.material, 'fx/a.material2d.json');
      expect(scope.history.undoEntries.single.label, 'Paint Hero');
      module.dropMaterial2D(drop('fx/b.material2d.json', 100, 100));
      expect(hero.getComponent<Material2D>()!.material, 'fx/b.material2d.json');
      scope.history.undo();
      scope.history.undo();
      expect(hero.hasComponent<Material2D>(), isFalse);
      expect(placed, isEmpty);
    });

    test('on nothing: nothing', () {
      write('fx/a.material2d.json', {'flash': {}});
      sprite('Hero');
      module.dropMaterial2D(drop('fx/a.material2d.json', 500, 500));
      expect(scope.history.undoEntries, isEmpty);
      expect(placed, isEmpty);
    });

    test('a screen material: the screen material, made when there is none', () {
      write('fx/crt.material2d.json', {'kind': 'screen'});
      write('fx/night.material2d.json', {'kind': 'screen'});
      module.dropMaterial2D(drop('fx/crt.material2d.json', 0, 0));
      expect(placed, ['Screen']);
      final screen = scope.world
          .query(const [ScreenMaterial])
          .single
          .getComponent<ScreenMaterial>()!;
      expect(screen.material, 'fx/crt.material2d.json');
      module.dropMaterial2D(drop('fx/night.material2d.json', 0, 0));
      expect(placed, ['Screen'], reason: 'not another');
      expect(screen.material, 'fx/night.material2d.json');
    });
  });
}
