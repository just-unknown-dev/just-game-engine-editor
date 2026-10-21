// Opening a scene leaves the one open first: its unsaved changes are asked
// about (and never thrown away without asking), and a play-test of it ends,
// so a later save cannot write its snapshot into the other scene's file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/memory_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Engine engine;
  late EditorScope scope;
  late JustGameEditorPlugin plugin;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('open_scene_guard_');
    final store = SceneStore(
      root: root.path,
      codec: SceneCodec(ComponentDefinitionRegistry.core()),
    );
    for (final name in ['level_01', 'level_02']) {
      await store.writeInitialFiles(name);
    }
    engine = Engine();
    await engine.initialize();
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      scenesRoot: root.path,
      settingsStore: MemorySettingsStore(),
    );
    plugin = JustGameEditorPlugin(engine: engine, scope: scope);
    await plugin.attach(plugin.engine);
    await plugin.openScene('level_01');
  });

  tearDown(() {
    plugin.playController.stop();
    plugin.dispose();
    scope.dispose();
    engine.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String open() => plugin.sceneState.activeScene.value!.name;

  Entity addMarker(String name) {
    final e = engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(1, 2, 0)),
    ], name: name);
    plugin.sceneState.markDirty();
    return e;
  }

  List<String> namesIn(String scene) {
    final json =
        jsonDecode(File('${root.path}/$scene.scene.json').readAsStringSync())
            as Map<String, dynamic>;
    return [
      for (final e in json['entities'] as List) (e as Map)['name'] as String,
    ];
  }

  test('unsaved changes are never left without asking', () async {
    expect(open(), 'level_01');
    addMarker('Unsaved');

    // Nobody to ask: the scene stays, its changes with it.
    await plugin.openScene('level_02');
    expect(open(), 'level_01');
    expect(plugin.sceneState.isDirty.value, isTrue);
    expect(
      engine.world.entities.any((e) => e.name == 'Unsaved'),
      isTrue,
      reason: 'the edit is still there',
    );

    // Cancelled: the same.
    final asked = <(String, String)>[];
    plugin.askToLeaveScene = (leaving, opening) async {
      asked.add((leaving, opening));
      return null;
    };
    await plugin.openScene('level_02');
    expect(asked, [('level_01', 'level_02')]);
    expect(open(), 'level_01');
    expect(plugin.sceneState.isDirty.value, isTrue);

    // Don't save: the other scene opens, and level_01's file is untouched.
    plugin.askToLeaveScene = (_, _) async => UnsavedChoice.discard;
    await plugin.openScene('level_02');
    expect(open(), 'level_02');
    expect(namesIn('level_01'), isNot(contains('Unsaved')));
  });

  test('Save writes the scene being left before the other opens', () async {
    addMarker('Kept');
    plugin.askToLeaveScene = (_, _) async => UnsavedChoice.save;
    await plugin.openScene('level_02');
    expect(open(), 'level_02');
    expect(namesIn('level_01'), contains('Kept'));
  });

  test("a play-test ends with its scene: a save afterwards writes the new "
      "scene, not the old one's snapshot", () async {
    addMarker('OnlyInLevel01');
    plugin.askToLeaveScene = (_, _) async => UnsavedChoice.save;
    plugin.play();
    expect(plugin.playController.isRunning, isTrue);

    await plugin.openScene('level_02');
    expect(open(), 'level_02');
    expect(plugin.playController.isRunning, isFalse);
    expect(plugin.playController.snapshot, isNull);

    plugin.sceneState.markDirty();
    expect(await plugin.saveScene(), isTrue);
    expect(namesIn('level_02'), isNot(contains('OnlyInLevel01')));
  });

  test('a clean scene is left without a question', () async {
    var asked = false;
    plugin.askToLeaveScene = (_, _) async {
      asked = true;
      return null;
    };
    await plugin.openScene('level_02');
    expect(asked, isFalse);
    expect(open(), 'level_02');
  });
}
