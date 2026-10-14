// The editor and the 3-D shapes: a Solid and a Trigger of every prefab with
// a shape, a matched collider drawn as its parts, and a collider matching a
// shape that isn't there flagged in Problems.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color, Size;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/physics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

/// Stairs of [steps] boxes, as a shape component would be.
class _Steps extends Component implements SolidShapeSource {
  _Steps(this.steps);

  final int steps;

  @override
  Object get solidKey => ('steps', steps);

  @override
  List<SolidPart> get solidParts => [
    for (var i = 0; i < steps; i++) SolidBox(0.5, (i + 1) / 2, 0.5, z: i.toDouble()),
  ];
}

Float32List _points(List<List<double>> points) => Float32List.fromList([for (final p in points) ...p]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorScope scope() {
    final world = World()..initialize();
    Physics3D.registerSchemas(world.context);
    final s = EditorScope(world: world);
    addTearDown(s.dispose);
    s.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    return s;
  }

  test('a Solid and a Trigger of every prefab with a shape', () {
    final s = scope();
    expect(s.prefabVariants.map((v) => v.id), ['solid', 'trigger']);
    final stairs = PrefabDefinition(
      id: 'stairs',
      name: 'Stairs',
      category: 'Shapes',
      icon: Icons.stairs_outlined,
      color: const Color(0xFF26A69A),
      dimensions: Dimensions.threeD,
      build: (_, _) => [TransformComponent(), _Steps(3)],
    );
    final plain = PrefabDefinition(
      id: 'empty',
      name: 'Empty',
      category: 'Other',
      icon: Icons.add,
      color: const Color(0xFF26A69A),
      build: (_, _) => [TransformComponent()],
    );
    final solid = BuiltInPhysics3DContributions.solid;
    expect(solid.offersFor(stairs), isTrue);
    expect(solid.offersFor(plain), isFalse);
    final parts = solid.of(stairs).build(Offset.zero, Size.zero);
    expect(parts.whereType<RigidBody3D>().single.bodyType, BodyType3D.static);
    expect(parts.whereType<Collider3D>().single.shape, ColliderShape3D.matchShape);
    final trigger = BuiltInPhysics3DContributions.trigger.of(stairs);
    expect(trigger.name, 'Trigger Stairs');
    expect(trigger.build(Offset.zero, Size.zero).whereType<RigidBody3D>().single.isSensor, isTrue);
  });

  group('hull outlines', () {
    test('a box of eight points has its twelve edges, no diagonals', () {
      final cube = HullOutline.of(_points([
        for (final x in [0.0, 1.0])
          for (final y in [0.0, 1.0])
            for (final z in [0.0, 1.0]) [x, y, z],
      ]));
      expect(cube, hasLength(12));
      expect(cube.every((l) => (l.$1.distanceTo(l.$2) - 1).abs() < 1e-9), isTrue);
    });

    test('a wedge has nine edges, a tetrahedron six', () {
      final wedge = HullOutline.of(_points([
        [0, 1, 0], [1, 1, 0], [1, 1, 2], [0, 1, 2], [1, 0, 2], [0, 0, 2],
      ]));
      expect(wedge, hasLength(9));
      final tetra = HullOutline.of(_points([[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]]));
      expect(tetra, hasLength(6));
    });

    test('a point inside the hull adds no edge', () {
      final lines = HullOutline.of(_points([[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [0.1, 0.1, 0.1]]));
      expect(lines, hasLength(6));
    });
  });

  test('a matched collider draws its parts', () {
    final lines = [
      for (final part in _Steps(3).solidParts) ...ColliderOverlay3D.partLines(part),
    ];
    expect(lines, hasLength(36), reason: 'three boxes');
    final deepest = lines.map((l) => l.$2.z).reduce((a, b) => a > b ? a : b);
    expect(deepest, 2.5);
  });

  test('a collider matching a shape that is not there is an error; its fix makes it a box', () {
    final s = scope();
    final c = Collider3D(shape: ColliderShape3D.matchShape);
    s.world.createEntityWithComponents([TransformComponent(), c], name: 'Ghost');
    final problems = Physics3DChecks.all(ValidationContext(scope: s, projectRoot: Directory.systemTemp.path));
    expect(problems.single.message, contains('no 3-D shape'));
    problems.single.fixes.single.apply();
    expect(c.shape, ColliderShape3D.box);
    s.world.createEntityWithComponents([
      TransformComponent(),
      _Steps(2),
      Collider3D(shape: ColliderShape3D.matchShape),
    ]);
    expect(Physics3DChecks.all(ValidationContext(scope: s, projectRoot: Directory.systemTemp.path)), isEmpty);
  });
}
