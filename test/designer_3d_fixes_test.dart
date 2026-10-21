// The 3-D designer where it used to go wrong: GROUPS' select-all, a
// marquee over a locked floor, an array too big to make, an Alt+click that
// painted on the way, a measurement left behind, a kill height that
// catches every fall, the VIEW section's lens and slice, and the JSON
// viewer's search over text whose letter case changes its length.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/json_viewer/json_viewer.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/aids/level_checks_3d.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/aids/ruler_3d.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/entity/entity_ops.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/array_3d_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/groups_3d_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/view_3d_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/tools/material_paint_3d_tool.dart';

const _wood = 'assets/materials/wood.material.json';

/// A kit whose things are lost below 10 m down.
class _Aids extends LevelAids {
  const _Aids();

  @override
  double killHeight(World world) => 10;
}

class _Kit extends EditorModule {
  @override
  String get id => 'test.kit';
  @override
  String get name => 'Kit';
  @override
  LevelAids get levelAids => const _Aids();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const canvas = Size(400, 400);
  late EditorScope scope;
  late OrbitFlyEditorView view;
  late LevelDesignerSession session;
  var alt = false;

  EditorScope scope3D({List<EditorModule> modules = const []}) {
    final world = World()..initialize();
    Graphics3D.registerSchemas(world.context);
    Physics3D.registerSchemas(world.context);
    final s = testScope(world: world, modules: modules);
    s.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
    return s;
  }

  setUp(() {
    scope = scope3D();
    view = OrbitFlyEditorView.of(Camera(viewportSize: canvas))
      ..viewportSize = canvas
      ..pivot.setValues(0, 0, 0)
      ..distance = 20
      ..yaw = 0
      ..pitch = -math.pi / 2;
    view.sync();
    alt = false;
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: scope.entities.uniqueName.call,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => ModifierKeys(alt: alt),
      camera: () => view,
    );
    addTearDown(session.dispose);
  });

  Entity make(String name, List<Component> components) {
    final e = scope.world.createEntityWithComponents(components, name: name);
    scope.sceneState.registerEntity(e);
    return e;
  }

  Entity cube(double x, String name) =>
      make(name, [TransformComponent(position: Vector3(x, -0.5, 0)), Cube3D()]);

  Offset at(double x) => view.projectToScreen(Vector3(x, -1, 0))!;
  bool press(double x) =>
      session.onPointerDown(Offset.zero, 32, screen: at(x), canvasSize: canvas);
  void move(double x) =>
      session.onPointerMove(Offset.zero, 32, screen: at(x), canvasSize: canvas);
  void release(double x) =>
      session.onPointerUp(Offset.zero, 32, screen: at(x), canvasSize: canvas);

  testWidgets('GROUPS: the arrow selects all a group holds, and only that', (
    tester,
  ) async {
    final a = cube(0, 'A'), b = cube(2, 'B'), c = cube(4, 'C');
    scope.sceneState.selectRange([a, b, c], anchor: a);
    final group = scope.entities.groupSelection()!;
    expect(scope.sceneState.selectedEntity.value, same(group));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 280, child: Groups3DPanel(scope: scope)),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Select what it holds'));
    await tester.pump();
    expect(scope.sceneState.multiSelectedIds.value, {a.id, b.id, c.id});
    expect(scope.sceneState.isInMultiSelection(group.id), isFalse);
  });

  group('Select', () {
    late Entity floor;
    setUp(() {
      floor = make('Floor', [
        TransformComponent(position: Vector3(0, 0.5, 0)),
        Cube3D(width: 40, depth: 40),
      ]);
      session.setTool(BuiltInTools.select);
    });

    test('a press on something pickable is the viewport\'s', () {
      expect(press(0), isFalse);
      expect(session.controller.screenRect.value, isNull);
    });

    test('a marquee starts over a locked floor', () {
      scope.view.toggleLocked(floor.id);
      expect(press(0), isTrue);
      move(3);
      expect(session.controller.screenRect.value, isNotNull);
      release(3);
      expect(session.controller.screenRect.value, isNull);
    });
  });

  group('ARRAY', () {
    test('counts what it makes, children included, and refuses past the '
        'most one array makes', () {
      final crate = cube(0, 'Crate');
      final inside = cube(0, 'Lid');
      scope.entities.reparentEntity(inside, crate);
      scope.sceneState.selectEntity(crate);
      final ops = scope.entities;
      expect(ops.arrayEntityCount3D(const Array3DSpec(count: 3)), 4);

      const huge = Array3DSpec(
        mode: ArrayMode3D.grid,
        columns: 100,
        floors: 100,
        rows: 100,
      );
      expect(
        ops.arrayEntityCount3D(huge),
        greaterThan(EntityOps.maxArrayEntities),
      );
      final before = scope.world.entities.length;
      final steps = scope.history.undoEntries.length;
      ops.arraySelection3D(scope.history, huge, Vector3.zero());
      expect(scope.world.entities.length, before);
      expect(scope.history.undoEntries.length, steps);

      ops.arraySelection3D(
        scope.history,
        const Array3DSpec(count: 3),
        Vector3.zero(),
      );
      expect(scope.world.entities.length, before + 4);
    });

    testWidgets('the button says too many, and is off', (tester) async {
      scope.sceneState.selectEntity(cube(0, 'Crate'));
      scope.designer3D.array.value = const Array3DSpec(
        mode: ArrayMode3D.grid,
        columns: 100,
        floors: 100,
        rows: 100,
      );
      var made = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: Array3DPanel(scope: scope, make: (_) => made++),
            ),
          ),
        ),
      );
      expect(find.text('Too many: 999999 entities'), findsOneWidget);
      await tester.tap(find.text('Too many: 999999 entities'));
      await tester.pump();
      expect(made, 0);
    });
  });

  test('Paint material: an Alt+click that drags paints nothing', () {
    final a = cube(0, 'A'), b = cube(2, 'B'), c = cube(4, 'C');
    a.getComponent<Primitive3D>()!.material = _wood;
    session.setTool(MaterialPaint3DTool.toolId);
    alt = true;
    press(0);
    move(2);
    move(4);
    release(4);
    expect(scope.designer3D.materialInHand.value, _wood);
    String materialOf(Entity e) => e.getComponent<Primitive3D>()!.material;
    expect([materialOf(b), materialOf(c)], ['', '']);
    expect(scope.history.undoEntries, isEmpty);
  });

  test('Measure: the measurement goes with the tool', () {
    session.setTool(BuiltInTools.measure);
    final tool = session.tools.byId(BuiltInTools.measure)! as Measure3DTool;
    press(0);
    move(3);
    release(3);
    expect(tool.measured.value, isNotNull);
    session.setTool(BuiltInTools.select);
    expect(tool.measured.value, isNull);
  });

  test('with a kill height every fall is caught: a ledge over the void is '
      'not a problem', () {
    final killing = scope3D(modules: [_Kit()]);
    final ledge = killing.world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, -5, 0)),
      Cube3D(),
      Collider3D(),
    ], name: 'Ledge');
    killing.sceneState.registerEntity(ledge);
    final problems = [
      for (final p in LevelChecks3D.all(ValidationContext(scope: killing)))
        p.message,
    ];
    expect(problems.where((m) => m.contains('Nothing at all')), isEmpty);

    // Without one, it is.
    final plain = [
      for (final p in LevelChecks3D.all(ValidationContext(scope: scope)))
        p.message,
    ];
    expect(plain, isEmpty, reason: 'nothing in this scene yet');
    cube(0, 'Box').addComponent(Collider3D());
    expect(
      [
        for (final p in LevelChecks3D.all(ValidationContext(scope: scope)))
          p.message,
      ],
      [contains('Nothing at all under Box')],
    );
  });

  testWidgets('VIEW: the lens toggle follows the view; the slice keeps to '
      'a level working plane', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = scope.designer3D;
    state.sliceOn.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: View3DPanel(scope: scope)),
      ),
    );
    bool lens() =>
        tester.widget<EditorToggle>(find.byType(EditorToggle).first).value;
    expect(lens(), isFalse);
    (scope.sceneView as OrbitFlyEditorView).orthographic = true;
    await tester.pump(const Duration(milliseconds: 300));
    expect(lens(), isTrue, reason: 'switched elsewhere: pad 5, the cube');

    state.planeAxis.value = WorkingPlaneAxis.front;
    state.planeOffset.value = 7;
    await tester.pump();
    final before = state.sliceY.value;
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pump();
    expect(state.sliceY.value, before, reason: 'a depth is not a height');

    state.planeAxis.value = WorkingPlaneAxis.ground;
    state.planeOffset.value = -3;
    await tester.pump();
    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pump();
    expect(state.sliceY.value, -5);
  });

  testWidgets('the JSON viewer marks each match where it is in its own '
      'line, whatever its letter case', (tester) async {
    final dir = Directory.systemTemp.createTempSync('jge_json_case');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the system's own clean-up.
      }
    });
    File(
      '${dir.path}/odd.json',
    ).writeAsStringSync('{"İİİ_name": "Name", "other": "NaMe_nAmE"}');
    final key = GlobalKey<JsonViewerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonViewer(
            key: key,
            path: 'odd.json',
            index: AssetIndex(projectRoot: dir.path),
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: 'odd.json',
            ),
            loadOnStart: false,
          ),
        ),
      ),
    );
    final viewer = key.currentState!;
    await tester.runAsync(viewer.load);
    await tester.pump();
    final line = viewer.lines[1], other = viewer.lines[2];
    viewer.search('NAME');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(viewer.matches, [
      (1, line.indexOf('name')),
      (1, line.indexOf('Name')),
      (2, other.indexOf('NaMe')),
      (2, other.indexOf('nAmE')),
    ]);
    // Each line is drawn whole, its own matches lit and no others'.
    List<String> lit(String start) {
      final text = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((t) => t.text)
          .firstWhere((t) => t.toPlainText().startsWith(start));
      expect(text.toPlainText(), start == '  "İ' ? line : other);
      final out = <String>[];
      text.visitChildren((span) {
        if (span is TextSpan &&
            span.text != null &&
            span.style?.backgroundColor != null) {
          out.add(span.text!);
        }
        return true;
      });
      return out;
    }

    expect(lit('  "İ'), ['name', 'Name']);
    expect(lit('  "other'), ['NaMe', 'nAmE']);
  });
}
