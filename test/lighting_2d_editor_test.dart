// 2-D lighting in the editor: the markers, the Lighting prefabs, the reach
// a selected light draws, and Shift+L to see the scene unlit.
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/extension/built_in_lighting_2d_contributions.dart';

/// Counts the lines drawn on it.
class _Lines implements Canvas {
  int count = 0;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => count++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorScope scope({SceneMode mode = SceneMode.twoD, Engine? engine}) {
    final s = engine != null
        ? EditorScope(builtIns: const [BuiltInEditorModule.new], engine: engine)
        : EditorScope(
            builtIns: const [BuiltInEditorModule.new],
            world: World()..initialize(),
          );
    addTearDown(s.dispose);
    s.sceneState.openScene(EditorScene(name: 'cave', mode: mode));
    return s;
  }

  CommandContext context(EditorScope s) =>
      CommandContext(scope: s, modifiers: const ModifierKeys());

  test('every project marks lights and the scene lighting', () {
    final s = scope();
    expect(
      s.markers.map((m) => m.id),
      containsAll(['lighting.light2D', 'lighting.lighting2D']),
    );
    expect(s.viewportOverlays.map((o) => o.id), contains('lighting.lights2D'));
  });

  test('the Lighting prefabs place a light or the lighting, in 2-D', () {
    final s = scope();
    final ids = [
      BuiltInLighting2DContributions.pointId,
      BuiltInLighting2DContributions.spotId,
      BuiltInLighting2DContributions.lightingId,
    ];
    for (final id in ids) {
      final prefab = s.prefabs.byId(id)!;
      expect(prefab.category, 'Lighting');
      expect(prefab.dimensions, Dimensions.twoD, reason: id);
    }
    final spot = s.prefabs
        .byId(BuiltInLighting2DContributions.spotId)!
        .build(const Offset(10, 20), const Size(48, 48));
    expect(spot.whereType<Light2D>().single.kind, Light2DKind.spot);
    final lighting = s.prefabs
        .byId(BuiltInLighting2DContributions.lightingId)!
        .build(Offset.zero, const Size(48, 48));
    expect(lighting.whereType<Lighting2D>(), hasLength(1));
  });

  group('Shift+L', () {
    test('is bound, and does nothing without an engine', () {
      final s = scope();
      const id = BuiltInLighting2DContributions.toggleId;
      final binding = s.commands.bindingsFor(id).single;
      expect((binding.key, binding.shift), (LogicalKeyboardKey.keyL, true));
      expect(s.commands.byId(id)!.enabledIn(context(s)), isFalse);
    });

    test('turns the engine\'s lighting off and back on, in 2-D only', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      expect(
        BuiltInLighting2DContributions.passOf(engine),
        isNull,
        reason: 'not up yet',
      );
      await engine.initialize();
      final pass = BuiltInLighting2DContributions.passOf(engine)!;
      final s = scope(engine: engine);
      final command = s.commands.byId(BuiltInLighting2DContributions.toggleId)!;
      expect(command.enabledIn(context(s)), isTrue);
      command.run(context(s));
      expect(pass.enabled, isFalse);
      command.run(context(s));
      expect(pass.enabled, isTrue);

      final in3d = scope(engine: engine, mode: SceneMode.threeD);
      expect(command.enabledIn(context(in3d)), isFalse);
    });
  });

  test(
    'lights with no Scene lighting light nothing: add it, or turn it on',
    () {
      final s = scope();
      final lamp = s.world.createEntityWithComponents([
        TransformComponent(),
        Light2D(),
      ], name: 'Lamp');
      List<SceneProblem> check() =>
          BuiltInLighting2DContributions.lightsWithoutLighting(
            ValidationContext(scope: s),
          );
      final problem = check().single;
      expect(problem.entity, lamp);
      expect(problem.message, contains('Lamp'));
      expect(problem.fixes.single.label, 'Add Scene lighting');
      problem.fixes.single.apply();
      expect(s.world.query(const [Lighting2D]), hasLength(1));
      expect(check(), isEmpty);
      s.history.undo();
      expect(check(), hasLength(1), reason: 'the fix is one undo step');

      final off = Lighting2D(enabled: false);
      s.world.createEntityWithComponents([off]);
      final again = check().single;
      expect(again.fixes.single.label, 'Turn the Scene lighting on');
      again.fixes.single.apply();
      expect(off.enabled, isTrue);
      expect(check(), isEmpty);
    },
  );

  group('the reach of a selected light', () {
    late EditorScope s;
    late Entity entity;
    late Light2D light;
    final view = GameCameraEditorView.of(
      Camera(viewportSize: const Size(800, 600)),
    );

    int paint() {
      final lines = _Lines();
      Light2DOverlay().paint(
        ViewportOverlayContext(
          canvas: lines,
          size: const Size(800, 600),
          view: view,
          scope: s,
          isShown: (_) => true,
        ),
      );
      return lines.count;
    }

    setUp(() {
      s = scope();
      light = Light2D(radius: 100);
      entity = s.world.createEntityWithComponents([
        TransformComponent(position: Vector3(400, 300, 0)),
        light,
      ]);
    });

    test('a point light: a ring, only while selected', () {
      expect(paint(), 0, reason: 'not selected');
      s.sceneState.selectedEntity.value = entity;
      expect(paint(), 48);
    });

    test('a spot light: its arc, both edges and the way it points', () {
      light.kind = Light2DKind.spot;
      s.sceneState.selectedEntity.value = entity;
      final lines = paint();
      expect(lines, greaterThan(3 + 4));
      expect(lines, lessThan(48), reason: 'only the cone\'s arc');
    });

    test('a selected shadow caster: its outline', () {
      final caster = s.world.createEntityWithComponents([
        TransformComponent(position: Vector3(100, 100, 0)),
        RenderableComponent(
          renderable: RectangleRenderable(
            size: const Size(40, 20),
            fillColor: const Color(0xFF795548),
          ),
        ),
        ShadowCaster2D(),
      ]);
      s.sceneState.selectedEntity.value = caster;
      expect(paint(), 4);
    });
  });
}
