// The selection box's size comes from what the components say they are —
// their definitions' extents and the shapes the editor knows — and nothing
// is probed for a `size` it may not have: each probe of a type without one
// threw and caught an error, on every frame and for every entity under a
// click.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/gizmo_painter.dart';

/// Counts the members asked of it that it does not have.
class _Spy extends Component {
  int probes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    probes++;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  test('a click over components with no size asks them nothing', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final spy = _Spy();
    final box = world.createEntityWithComponents([
      TransformComponent(),
      RectangleComponent(width: 64, height: 32),
      spy,
    ], name: 'Box');
    final camera = GameCameraEditorView.of(
      Camera()..viewportSize = const Size(400, 300),
    );
    final middle = camera.worldToScreen(Offset.zero);

    final hit = GizmoHitTester().hitTest(
      middle + const Offset(28, 12),
      null,
      [box],
      camera,
      const Size(400, 300),
    );
    expect(hit.entity, same(box), reason: "the rectangle's size still counts");
    expect(spy.probes, 0);

    final miss = GizmoHitTester().hitTest(
      middle + const Offset(40, 0),
      null,
      [box],
      camera,
      const Size(400, 300),
    );
    expect(miss.entity, isNull, reason: 'outside the 64 x 32 box');
    expect(spy.probes, 0);
  });
}
