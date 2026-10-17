// Painting materials in a 3-D scene: a click draws what is under the
// pointer with the material in hand, a drag paints several as one undo
// step, Alt+click picks one up, a locked thing is left alone; and the
// MATERIALS section says what is in hand.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

const _stone = 'assets/materials/stone.material.json';
const _wood = 'assets/materials/wood.material.json';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EditorScope scope;
  late OrbitFlyEditorView view;
  late LevelDesignerSession session;
  var alt = false;

  setUp(() {
    final world = World()..initialize();
    Graphics3D.registerSchemas(world.context);
    scope = testScope(world: world);
    scope.sceneState.openScene(EditorScene(name: 'level', mode: SceneMode.threeD));
    view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 400)))
      ..viewportSize = const Size(400, 400)
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
    session.setTool(MaterialPaint3DTool.toolId);
  });

  Entity cube(double x, String name) {
    final e = scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, -0.5, 0)),
      Cube3D(),
    ], name: name);
    scope.sceneState.registerEntity(e);
    return e;
  }

  String materialOf(Entity e) => e.getComponent<Primitive3D>()!.material;

  Offset at(double x) => view.projectToScreen(Vector3(x, -1, 0))!;
  void press(double x) => session.onPointerDown(Offset.zero, 32, screen: at(x), canvasSize: const Size(400, 400));
  void move(double x) => session.onPointerMove(Offset.zero, 32, screen: at(x), canvasSize: const Size(400, 400));
  void release(double x) => session.onPointerUp(Offset.zero, 32, screen: at(x), canvasSize: const Size(400, 400));

  test('the tool is the 3-D designer\'s, on P', () {
    final tool = session.tools.byId(MaterialPaint3DTool.toolId)!;
    expect(tool.shortcut, 'P');
    expect(tool.dimensions, Dimensions.threeD);
  });

  test('nothing in hand: it says where to choose one', () {
    final a = cube(0, 'A');
    press(0);
    release(0);
    expect(materialOf(a), isEmpty);
    expect(session.controller.status.value, contains('MATERIALS'));
  });

  test('a drag paints what it passes over, as one undo step', () {
    final a = cube(0, 'A'), b = cube(2, 'B'), c = cube(4, 'C');
    scope.designer3D.materialInHand.value = _stone;
    press(0);
    move(1);
    move(2);
    release(2);
    expect([materialOf(a), materialOf(b), materialOf(c)], [_stone, _stone, '']);
    expect(scope.history.undoEntries, hasLength(1));
    scope.history.undo();
    expect([materialOf(a), materialOf(b)], ['', '']);
  });

  test('Alt+click picks a material up', () {
    final a = cube(0, 'A');
    a.getComponent<Primitive3D>()!.material = _wood;
    alt = true;
    press(0);
    release(0);
    expect(scope.designer3D.materialInHand.value, _wood);
    expect(scope.history.undoEntries, isEmpty);
  });

  test('a locked thing is left alone', () {
    final a = cube(0, 'A');
    scope.view.toggleLocked(a.id);
    scope.designer3D.materialInHand.value = _stone;
    press(0);
    release(0);
    expect(materialOf(a), isEmpty);
  });

  testWidgets('MATERIALS says what is in hand, and puts it down', (tester) async {
    scope.designer3D.materialInHand.value = _stone;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 300, child: Materials3DPanel(scope: scope, setTool: session.setTool)),
        ),
      ),
    );
    expect(find.textContaining('In hand: stone'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(scope.designer3D.materialInHand.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
