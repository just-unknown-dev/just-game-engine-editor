// The default palette has to be useful for any 2D game, and every component it
// places has to survive the JSON round trip that CreateEntitiesCommand does on
// undo. A prefab whose components do not encode places an entity that quietly
// loses half of itself the first time someone presses Ctrl+Z.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine/graphics_3d.dart' show Graphics3D;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/extension/built_in_audio_contributions.dart';
import 'package:just_game_engine_editor/src/extension/built_in_lighting_2d_contributions.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/shapes/shape_prefabs.dart';

void main() {
  // One scope: the built-in palette and the codec it round-trips through.
  // A world that knows the 3-D shapes, as a 3-D project's does: the default
  // kit's 3-D palette places them.
  final world = jge.World()..initialize();
  Graphics3D.registerSchemas(world.context);
  final scope = EditorScope(
    builtIns: const [BuiltInEditorModule.new],
    world: world,
  );

  const position = Offset(320, 180);
  const size = Size(200, 96);

  test('registers the full default palette', () {
    final ids = scope.prefabs.all.map((p) => p.id).toSet();
    expect(ids, {
      BuiltInPrefabs.rectangleId,
      BuiltInPrefabs.circleId,
      BuiltInPrefabs.spriteId,
      BuiltInPrefabs.emptyId,
      BuiltInPrefabs.solidId,
      BuiltInPrefabs.triggerId,
      BuiltInPrefabs.cameraId,
      BuiltInPrefabs.cameraZoneId,
      BuiltInPrefabs.cameraBoundsId,
      BuiltInPrefabs.targetGroupId,
      BuiltInPrefabs.dollyCameraId,
      BuiltInPrefabs.spawnId,
      BuiltInPrefabs.markerId,
      BuiltInAudioContributions.soundId,
      BuiltInAudioContributions.sound3dId,
      BuiltInAudioContributions.listenerId,
      BuiltInLighting2DContributions.lightingId,
      BuiltInLighting2DContributions.pointId,
      BuiltInLighting2DContributions.spotId,
      // The default 3-D kit's: offered only in a 3-D scene.
      for (final shape in ShapePrefabs.all) shape.id,
    });
  });

  test('every built-in component encodes', () {
    for (final prefab in scope.prefabs.all) {
      for (final component in prefab.build(position, size)) {
        final json = scope.codec.encode(component);
        expect(
          json,
          isNotNull,
          reason:
              '${prefab.id} places a ${component.runtimeType} that does not '
              'encode, so an undo would drop it',
        );
        expect(
          scope.codec.decode(json!),
          isA<jge.Component>(),
          reason: '${prefab.id}: ${component.runtimeType} did not decode',
        );
      }
    }
  });

  test('every built-in prefab places a transform at the drawn position', () {
    for (final prefab in scope.prefabs.all) {
      final transform = prefab
          .build(position, size)
          .whereType<jge.TransformComponent>()
          .firstOrNull;
      expect(transform, isNotNull, reason: '${prefab.id} has no transform');
      expect(transform!.position.x, position.dx, reason: prefab.id);
      expect(transform.position.y, position.dy, reason: prefab.id);
    }
  });

  test('drag-placed prefabs honour the drawn size', () {
    for (final prefab in scope.prefabs.all) {
      if (prefab.placement != PrefabPlacement.dragRect) continue;
      final components = prefab.build(position, size);

      final rect = components.whereType<jge.RectangleComponent>().firstOrNull;
      final circle = components.whereType<jge.CircleComponent>().firstOrNull;
      if (rect == null && circle == null) {
        // Not a shape: a camera zone or camera bounds, drawn by the camera
        // overlay from its extent — which must then be what was drawn.
        final sized = components
            .map(DesignerGeometry.sizeOf)
            .whereType<Size>()
            .firstOrNull;
        expect(
          sized,
          size,
          reason:
              '${prefab.id} draws nothing and has no extent, so the drag has '
              'no visible result',
        );
        continue;
      }
      if (rect != null) {
        expect(rect.width, size.width, reason: prefab.id);
        expect(rect.height, size.height, reason: prefab.id);
      }
      if (circle != null) {
        // Fits inside the drawn rect rather than overflowing it.
        expect(circle.radius * 2, lessThanOrEqualTo(size.shortestSide + 0.001));
      }

      // A body, if any, must match what was drawn — a collider that disagrees
      // with its own rectangle is invisible to the author and wrong in play.
      final collider = components.whereType<jge.Collider2D>().firstOrNull;
      if (collider != null) {
        expect(collider.shape, jge.ColliderShape2D.matchShape, reason: prefab.id);
        final world = jge.World()..initialize();
        final e = world.createEntityWithComponents(components);
        final shape = jge.ColliderGeometry.shapeOf(collider, entity: e);
        expect(shape, isA<jge.RectangleShape>(), reason: prefab.id);
        final box = shape! as jge.RectangleShape;
        expect(box.width, size.width, reason: prefab.id);
        expect(box.height, size.height, reason: prefab.id);
        world.dispose();
      }
    }
  });

  test('the trigger is a sensor and the solid is not', () {
    jge.RigidBody2D bodyOf(String id) => scope.prefabs
        .byId(id)!
        .build(position, size)
        .whereType<jge.RigidBody2D>()
        .single;

    expect(bodyOf(BuiltInPrefabs.triggerId).isSensor, isTrue);
    expect(bodyOf(BuiltInPrefabs.solidId).isSensor, isFalse);
    expect(bodyOf(BuiltInPrefabs.solidId).isStatic, isTrue);
  });

  test('the palette carries no genre assumptions', () {
    // The point of the default designer: nothing here names a platformer
    // concept. A project's own genre arrives through an EditorModule.
    const genreWords = [
      'platform',
      'player',
      'enemy',
      'coin',
      'spike',
      'hazard',
      'checkpoint',
      'goal',
      'collectible',
      'ladder',
    ];
    for (final prefab in scope.prefabs.all) {
      final text =
          '${prefab.id} ${prefab.name} ${prefab.category} '
                  '${prefab.description ?? ''}'
              .toLowerCase();
      for (final word in genreWords) {
        expect(
          text.contains(word),
          isFalse,
          reason: '${prefab.id} mentions "$word"',
        );
      }
      for (final component in prefab.build(position, size)) {
        expect(
          component.runtimeType.toString().toLowerCase(),
          isNot(anyOf(genreWords.map(contains))),
          reason: '${prefab.id} places ${component.runtimeType}',
        );
      }
    }
  });
}
