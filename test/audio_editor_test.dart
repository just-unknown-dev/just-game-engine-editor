// Sound in the editor: the markers and range rings it draws, the Audio
// prefabs (2-D and 3-D), and an audio file dropped on a 3-D scene.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

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

  EditorScope scope({SceneMode mode = SceneMode.threeD}) {
    final world = World()..initialize();
    final s = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: world,
    );
    addTearDown(s.dispose);
    s.sceneState.openScene(EditorScene(name: 'sound', mode: mode));
    return s;
  }

  test('every project marks sources and the listener, and shows ranges', () {
    for (final mode in SceneMode.values) {
      final s = scope(mode: mode);
      expect(s.markers.map((m) => m.id), containsAll(['audio.source', 'audio.listener']));
      expect(s.viewportOverlays.map((o) => o.id), contains('audio.ranges'));
    }
  });

  group('the range rings', () {
    late EditorScope s;
    late Entity entity;
    late AudioSourceComponent source;

    int paint(EditorView view) {
      final lines = _Lines();
      AudioRangeOverlay().paint(
        ViewportOverlayContext(canvas: lines, size: const Size(800, 600), view: view, scope: s, isShown: (_) => true),
      );
      return lines.count;
    }

    setUp(() {
      s = scope(mode: SceneMode.twoD);
      source = AudioSourceComponent(clipPath: 'a.wav', is3d: true, minDistance: 50, maxDistance: 200);
      entity = s.world.createEntityWithComponents([TransformComponent(position: Vector3(400, 300, 0)), source]);
    });

    test('a selected 3-D source: one ring near, one far, in 2-D', () {
      final view = GameCameraEditorView.of(Camera(viewportSize: const Size(800, 600)));
      expect(paint(view), 0, reason: 'not selected');
      s.sceneState.selectedEntity.value = entity;
      expect(paint(view), 2 * 48);
      source.is3d = false;
      expect(paint(view), 0, reason: 'a flat sound carries everywhere');
    });

    test('in 3-D, three of each round the axes', () {
      final in3d = scope();
      final e = in3d.world.createEntityWithComponents([
        TransformComponent(position: Vector3(0, -1, 6)),
        AudioSourceComponent(clipPath: 'a.wav', is3d: true, minDistance: 1, maxDistance: 3),
      ]);
      in3d.sceneState.selectedEntity.value = e;
      in3d.editorView.viewportSize = const Size(800, 600);
      final lines = _Lines();
      AudioRangeOverlay().paint(
        ViewportOverlayContext(canvas: lines, size: const Size(800, 600), view: in3d.editorView, scope: in3d, isShown: (_) => true),
      );
      expect(lines.count, greaterThan(2 * 48));
      expect(lines.count, lessThanOrEqualTo(6 * 48));
    });
  });

  group('the Audio prefabs', () {
    PrefabDefinition prefab(String id) => BuiltInPrefabs.all.singleWhere((p) => p.id == id);

    test('are a group of their own, in 2-D and 3-D scenes', () {
      expect(BuiltInPrefabs.categories.map((c) => c.label), contains('Audio'));
      for (final id in [BuiltInAudioContributions.soundId, BuiltInAudioContributions.sound3dId, BuiltInAudioContributions.listenerId]) {
        final p = prefab(id);
        expect(p.category, 'Audio');
        expect(p.dimensions, Dimensions.both);
        expect(p.buildAt, isNotNull, reason: id);
      }
    });

    test('a 3-D sound carries in pixels in 2-D, in metres in 3-D', () {
      final flat = prefab(BuiltInAudioContributions.sound3dId).build(const Offset(10, 20), const Size(48, 48));
      final source2d = flat.whereType<AudioSourceComponent>().single;
      expect(flat.whereType<LayerComponent>(), hasLength(1));
      expect((source2d.is3d, source2d.minDistance, source2d.maxDistance, source2d.dopplerLevel), (true, 64.0, 1024.0, 0.0));

      final ground = SurfacePoint(Vector3(2, 0, 3), Vector3(0, -1, 0));
      final deep = prefab(BuiltInAudioContributions.sound3dId).buildAt!(ground);
      final source3d = deep.whereType<AudioSourceComponent>().single;
      expect((source3d.is3d, source3d.minDistance, source3d.maxDistance, source3d.dopplerLevel), (true, 1.0, 20.0, 1.0));
      expect(source3d.farCutoff, greaterThan(0), reason: 'muffled far away');
      final at = deep.whereType<TransformComponent>().single.position;
      expect([at.x, at.y, at.z], [2, -1, 3], reason: 'a metre above the ground (up is -Y)');
    });

    test('the listener is a listener, and a flat sound is flat', () {
      final listener = prefab(BuiltInAudioContributions.listenerId).build(Offset.zero, const Size(48, 48));
      expect(listener.whereType<AudioListenerComponent>(), hasLength(1));
      final sound = prefab(BuiltInAudioContributions.soundId).build(Offset.zero, const Size(48, 48));
      expect(sound.whereType<AudioSourceComponent>().single.is3d, isFalse);
    });
  });

  test('an audio file dropped on a 3-D scene is a 3-D source above the ground', () {
    final s = scope();
    late List<Component> placed;
    late String? name;
    final drop = AssetDrop(
      scope: s,
      path: 'assets/audio/orb_hum.wav',
      at: Vector3(1, 0, 4),
      place: (components, n) {
        placed = components;
        name = n;
        return s.world.createEntityWithComponents(components);
      },
    );
    AudioDrop.place(drop);
    expect(name, 'orb_hum');
    final source = placed.whereType<AudioSourceComponent>().single;
    expect((source.clipPath, source.loop, source.is3d), ('assets/audio/orb_hum.wav', true, true));
    final at = placed.whereType<TransformComponent>().single.position;
    expect([at.x, at.y, at.z], [1, -1, 4]);
  });
}
