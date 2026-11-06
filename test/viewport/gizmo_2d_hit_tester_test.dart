// A click on the 2-D viewport picks what is drawn on top — by layer, then
// z, as the renderer and the Level Designer order them — not what happens
// to be listed last in the world.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/viewport/gizmos/gizmo_2d_painter.dart';

void main() {
  late World world;
  late EditorView view;
  const size = Size(800, 600);

  setUp(() {
    world = World()..initialize();
    addTearDown(world.dispose);
    view = GameCameraEditorView.of(OutputCamera())..viewportSize = size;
  });

  Entity box(String name, double w, {int layer = 0, int z = 0}) =>
      world.createEntityWithComponents([
        TransformComponent(),
        Rectangle2DComponent(width: w, height: w),
        LayerComponent(layer: layer, zOrder: z),
      ], name: name);

  Entity? pick(List<Entity> listed) => Gizmo2DHitTester()
      .hitTest(view.worldToScreen(Offset.zero), null, listed, view, size)
      .entity;

  test('a platform drawn over a backdrop is picked, the backdrop listed '
      'later or not', () {
    final platform = box('Platform', 64, layer: 10);
    final backdrop = box('Backdrop', 400, layer: -10);
    expect(pick([platform, backdrop]), platform);
    expect(pick([backdrop, platform]), platform);
  });

  test('on one layer, the higher z is on top', () {
    final front = box('Front', 64, z: 3);
    final back = box('Back', 200, z: 1);
    expect(pick([front, back]), front);
    expect(pick([back, front]), front);
  });

  test('drawn alike, the one listed last is on top, as before', () {
    final first = box('First', 64);
    final second = box('Second', 64);
    expect(pick([first, second]), second);
  });

  test('what is not under the pointer is never picked, however high', () {
    final under = box('Under', 64, layer: -5);
    final high = world.createEntityWithComponents([
      TransformComponent(position: Vector3(300, 300, 0)),
      Rectangle2DComponent(width: 10, height: 10),
      LayerComponent(layer: 50),
    ], name: 'High');
    expect(pick([under, high]), under);
  });
}
