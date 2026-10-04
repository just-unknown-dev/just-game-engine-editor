// Keying from anywhere: Record turns an edit into a key and gives the scene
// its value back; the inspector's diamond keys a field on request.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/field_key_button.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

void main() {
  late EditorScope scope;
  late TimelineSession s;
  late Entity door;
  late TransformComponent transform;

  PropertyTrack? track(
    String path, [
    TrackBinding binding = TrackBinding.owner,
  ]) {
    for (final t in s.asset.value!.propertyTracks) {
      if (t.path == path && t.binding == binding) return t;
    }
    return null;
  }

  Future<void> open(TimelineSession session) async {
    s = session;
    transform = TransformComponent(position: Vector3(100, 50, 0));
    door = scope.world.createEntityWithComponents([
      transform,
      TimelinePlayerComponent(inline: TimelineAsset(duration: 2, fps: 10)),
    ], name: 'Door');
    await s.follow(door);
  }

  group('record', () {
    setUp(() async {
      scope = testScope();
      final session = TimelineSession(scope, root: '.');
      addTearDown(session.dispose);
      await open(session);
    });

    test('an edit becomes a key, and the scene keeps its value', () {
      s.setRecording(true);
      expect(s.captureEdits(), 0, reason: 'nothing has changed yet');

      s.scrubTo(1);
      transform.setPositionXY(300, 50); // a gizmo, the inspector, anything
      expect(s.captureEdits(), 1);

      // Its own position: a relative track, so the key is the offset.
      final x = track('TransformComponent.position.x')!;
      expect(x.isRelative, isTrue);
      expect(x.curve.keys.single.time, 1);
      expect(x.curve.keys.single.value, 200);
      expect(
        track('TransformComponent.position.y'),
        isNull,
        reason: 'y did not change',
      );
      expect(transform.position.x, 300, reason: 'shown where it was put');

      scope.restoreAuthoredState();
      expect(transform.position.x, 100, reason: 'the scene did not move');
      expect(s.captureEdits(), 0, reason: 'going back is not an edit');
    });

    test('a drag is one undo step; a second time is a second key', () {
      s.setRecording(true);
      s.scrubTo(0.5);
      for (final x in [120.0, 160.0, 220.0]) {
        transform.setPositionXY(x, 50);
        s.captureEdits();
      }
      expect(
        track('TransformComponent.position.x')!.curve.keys.single.value,
        120,
      );
      s.scrubTo(1.5);
      transform.setPositionXY(400, 50);
      s.captureEdits();
      expect(
        track('TransformComponent.position.x')!.curve.keys.map((k) => k.value),
        [120, 300],
      );
      // Between the keys the timeline now moves it.
      s.scrubTo(1);
      expect(transform.position.x, closeTo(100 + 210, 15));

      s.undo();
      expect(track('TransformComponent.position.x')!.curve.keys, hasLength(1));
      s.undo();
      expect(s.asset.value!.tracks, isEmpty);
      expect(s.canUndo, isFalse);
    });

    test('an absolute field, and another entity a track is bound to', () {
      final lamp = SpriteAnimationComponent(atlasPath: 'lamp.json');
      scope.world.createEntityWithComponents([
        TransformComponent(),
        lamp,
      ], name: 'Lamp');
      final definition = scope.definitions.definitionByType(
        'SpriteAnimationComponent',
      )!;
      // Lamp is watched once a track is bound to it.
      s.addPropertyTracks(
        const TrackBinding.name('Lamp'),
        definition.type,
        definition.fields.firstWhere((f) => f.name == 'speed'),
      );
      s.setRecording(true);
      s.scrubTo(1);
      lamp
        ..flipX = true
        ..speed = 2.5;
      expect(s.captureEdits(), 2);
      const lampBinding = TrackBinding.name('Lamp');
      expect(
        track(
          'SpriteAnimationComponent.speed',
          lampBinding,
        )!.curve.keys.single.value,
        2.5,
      );
      final flip = track('SpriteAnimationComponent.flipX', lampBinding)!;
      expect(flip.curve.keys.single.value, isTrue);
      expect(flip.curve.keys.single.interpolation, KeyInterpolation.step);

      s.stop();
      expect(lamp.flipX, isFalse);
      expect(lamp.speed, 1.0);
    });

    test('off, or in a play-test, nothing is recorded', () {
      s.scrubTo(1);
      transform.setPositionXY(300, 50);
      expect(s.captureEdits(), 0);
      s.setRecording(true);
      s.isAuthoring = () => false;
      transform.setPositionXY(500, 50);
      expect(s.captureEdits(), 0);
      expect(s.asset.value!.tracks, isEmpty);
    });
  });

  group('the key button', () {
    setUp(() async {
      scope = testScope();
      final session = TimelineSession(scope, root: '.');
      addTearDown(session.dispose);
      await open(session);
    });

    test('keys a field with its value now, and says what it is', () {
      final definition = scope.definitions.definitionFor(transform)!;
      final rotation = definition.fields.firstWhere(
        (f) => f.name == 'rotation',
      );
      final position = definition.fields.firstWhere(
        (f) => f.name == 'position',
      );
      expect(s.keyStateOf(door, transform, rotation), FieldKeyState.none);

      transform.angle = 0.5;
      s.scrubTo(1);
      expect(s.keyField(door, transform, rotation), isTrue);
      // A 2-D scene keys the rotation's angle: its z.
      expect(
        track('TransformComponent.rotation.z')!.curve.keys.single.value,
        0.5,
      );
      expect(s.keyStateOf(door, transform, rotation), FieldKeyState.keyed);
      s.scrubTo(0.5);
      expect(s.keyStateOf(door, transform, rotation), FieldKeyState.animated);

      // Both channels of a vector, in one step; relative, so no offset yet.
      s.keyFields(door, transform, [position]);
      expect(
        track('TransformComponent.position.x')!.curve.keys.single.value,
        0,
      );
      expect(
        track('TransformComponent.position.y')!.curve.keys.single.value,
        0,
      );
      s.undo();
      expect(track('TransformComponent.position.x'), isNull);

      // An entity with no name cannot be bound to.
      final nameless = scope.world.createEntityWithComponents([
        TransformComponent(),
      ]);
      expect(
        s.keyField(
          nameless,
          nameless.getComponent<TransformComponent>()!,
          rotation,
        ),
        isFalse,
      );
    });
  });

  testWidgets('the inspector shows a diamond while a timeline is open, and '
      'an inspector edit is recorded', (tester) async {
    scope = testScope();
    await open(TimelineSession.of(scope));
    addTearDown(s.dispose);

    Future<void> pumpInspector() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: buildComponentSections(
                entity: door,
                sceneState: scope.sceneState,
                scope: scope,
              ),
            ),
          ),
        ),
      ),
    );

    await pumpInspector();
    final diamonds = find.byType(FieldKeyButton);
    expect(diamonds, findsWidgets);
    // Not on the player's own fields.
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Timeline Player'),
          matching: find.byType(DefinitionSection),
        ),
        matching: diamonds,
      ),
      findsNothing,
    );

    s.scrubTo(1);
    await tester.tap(diamonds.first);
    await tester.pump();
    expect(s.asset.value!.propertyTracks, isNotEmpty);

    await s.close();
    await pumpInspector();
    expect(find.byType(FieldKeyButton), findsNothing, reason: 'no timeline');
  });
}
