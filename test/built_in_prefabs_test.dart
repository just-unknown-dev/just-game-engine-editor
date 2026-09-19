// The default palette has to be useful for any 2D game, and every component it
// places has to survive the JSON round trip that CreateEntitiesCommand does on
// undo. A prefab whose components do not encode places an entity that quietly
// loses half of itself the first time someone presses Ctrl+Z.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  // One scope: the built-in palette and the codec it round-trips through.
  final scope = EditorScope(world: jge.World()..initialize());

  const position = Offset(320, 180);
  const size = Size(200, 96);

  test('registers the full default palette', () {
    final ids = scope.prefabs.all.map((p) => p.id).toSet();
    expect(ids, {
      BuiltInPrefabs.rectangleId,
      BuiltInPrefabs.circleId,
      BuiltInPrefabs.spriteId,
      BuiltInPrefabs.textId,
      BuiltInPrefabs.emptyId,
      BuiltInPrefabs.solidId,
      BuiltInPrefabs.triggerId,
      BuiltInPrefabs.cameraId,
      BuiltInPrefabs.spawnId,
      BuiltInPrefabs.markerId,
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
      expect(
        rect ?? circle,
        isNotNull,
        reason: '${prefab.id} draws nothing, so the drag has no visible result',
      );
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
      final body = components.whereType<jge.PhysicsBodyComponent>().firstOrNull;
      if (body != null) {
        final shape = body.shape;
        expect(shape, isA<jge.RectangleShape>(), reason: prefab.id);
        expect(
          (shape as jge.RectangleShape).width,
          size.width,
          reason: prefab.id,
        );
        expect(shape.height, size.height, reason: prefab.id);
      }
    }
  });

  test('the trigger is a sensor and the solid is not', () {
    jge.PhysicsBodyComponent bodyOf(String id) => scope.prefabs
        .byId(id)!
        .build(position, size)
        .whereType<jge.PhysicsBodyComponent>()
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
