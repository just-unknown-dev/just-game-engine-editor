// The inspector's editor for a `physicsShape` field: each dimension row
// changes its own value and nothing else the shape saves — a circle keeps
// its centre, a capsule where it sits on the body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/physics/physics_2d/physics_shape_editor.dart';

class _Holder extends Component {
  Shape2D shape = Circle2DShape(10);
}

/// How the scene saves [shape].
Map<String, Object?> _saved(Shape2D shape) => Map<String, Object?>.from(
  PhysicsDefinitions.shapeType.encode(shape)! as Map,
);

void main() {
  late EditorScope scope;

  setUp(() {
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: World()..initialize(),
    );
    addTearDown(scope.dispose);
  });

  // The editor for [start], and what each edit wrote.
  Future<List<Shape2D>> pump(WidgetTester tester, Shape2D start) async {
    final written = <Shape2D>[];
    final holder = _Holder()..shape = start;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: PhysicsShapeEditor(
                ctx: FieldEditorContext(
                  field: FieldDefinition(
                    name: 'shape',
                    kind: PhysicsDefinitions.shapeType,
                    read: (_) => holder.shape,
                  ),
                  hint: const FieldHint(),
                  value: holder.shape,
                  component: holder,
                  editors: scope.fieldEditors,
                  onChanged: (v) => written.add(v! as Shape2D),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return written;
  }

  void scrub(WidgetTester tester, String row, double to) => tester
      .widget<ScrubFieldRow>(
        find.ancestor(of: find.text(row), matching: find.byType(ScrubFieldRow)),
      )
      .onChanged(to);

  void axes(WidgetTester tester, String row, List<double> to) => tester
      .widget<AxesFieldRow>(
        find.ancestor(of: find.text(row), matching: find.byType(AxesFieldRow)),
      )
      .onChanged(to);

  // What changed between how [before] and [after] are saved.
  Set<String> changed(Shape2D before, Shape2D after) {
    final a = _saved(before), b = _saved(after);
    return {
      for (final key in {...a.keys, ...b.keys})
        if ('${a[key]}' != '${b[key]}') key,
    };
  }

  group('a circle', () {
    final start = Circle2DShape(10, center: const Offset(0, 20));

    testWidgets('its radius changes, its centre stays', (tester) async {
      final written = await pump(tester, start);
      scrub(tester, 'Radius', 12);
      final circle = written.single as Circle2DShape;
      expect(circle.radius, 12);
      expect(circle.center, const Offset(0, 20));
      expect(changed(start, circle), {'radius'});
    });

    testWidgets('its centre is a row of its own', (tester) async {
      final written = await pump(tester, start);
      axes(tester, 'Offset', [4, 30]);
      final circle = written.single as Circle2DShape;
      expect(circle.center, const Offset(4, 30));
      expect(circle.radius, 10);
    });
  });

  group('a capsule', () {
    final upright = Capsule2DShape(
      center1: const Offset(0, 10),
      center2: const Offset(0, 40),
      radius: 8,
    );

    testWidgets('its radius changes about where it sits', (tester) async {
      final written = await pump(tester, upright);
      scrub(tester, 'Radius', 12);
      final capsule = written.single as Capsule2DShape;
      expect(capsule.radius, 12);
      expect(
        (capsule.center1 + capsule.center2) / 2,
        const Offset(0, 25),
        reason: 'still where it was on the body',
      );
      expect(
        (capsule.center1 - capsule.center2).distance + 24,
        closeTo(46, 1e-9),
        reason: 'the same height',
      );
    });

    testWidgets('its height and its direction keep its middle', (tester) async {
      final written = await pump(tester, upright);
      scrub(tester, 'Height', 60);
      final taller = written.last as Capsule2DShape;
      expect((taller.center1 + taller.center2) / 2, const Offset(0, 25));
      // 60 tall with a radius of 8: centres 22 either side of the middle.
      expect(taller.center1, const Offset(0, 3));
      expect(taller.center2, const Offset(0, 47));
    });

    testWidgets('its offset is a row of its own', (tester) async {
      final written = await pump(tester, upright);
      axes(tester, 'Offset', [5, 0]);
      final moved = written.single as Capsule2DShape;
      expect(moved.center1, const Offset(5, -15));
      expect(moved.center2, const Offset(5, 15));
      expect(moved.radius, 8);
    });
  });

  testWidgets('every other kind: each row changes only its own value', (
    tester,
  ) async {
    final rect = Rectangle2DShape(40, 20);
    var written = await pump(tester, rect);
    scrub(tester, 'Width', 50);
    expect(changed(rect, written.single), isNot(contains('height')));
    expect((written.single as Rectangle2DShape).height, 20);

    final segment = Segment2DShape(
      const Offset(-10, 0),
      const Offset(10, 5),
      thickness: 3,
    );
    written = await pump(tester, segment);
    scrub(tester, 'Thickness', 4);
    final thicker = written.single as Segment2DShape;
    expect((thicker.point1, thicker.point2), (segment.point1, segment.point2));

    final chain = Chain2DShape(
      const [Offset(0, 0), Offset(10, 0), Offset(20, 5)],
      loop: true,
      thickness: 2,
    );
    written = await pump(tester, chain);
    scrub(tester, 'Thickness', 5);
    final chained = written.single as Chain2DShape;
    expect(chained.loop, isTrue);
    expect(chained.vertices, chain.vertices);
    expect(changed(chain, chained), {'thickness'});

    final rounded = RoundedPolygon2DShape(const [
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
    ], 2);
    written = await pump(tester, rounded);
    scrub(tester, 'Corner radius', 3);
    final round = written.single as RoundedPolygon2DShape;
    expect(round.vertices, rounded.vertices);
    expect(round.cornerRadius, 3);
  });
}
