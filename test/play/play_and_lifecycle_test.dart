// The editor over a running game must leave the game alone when it should:
// authoring holds the game's time still whatever is selected, a play-test
// that cannot start or stop cleanly leaves the level as authored, what was
// done during a play-test is not undone onto the authored level afterwards,
// and an editor taken off its engine (or disposed) hands everything back.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/play/play_snapshot.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/plugin/editor_log_capture_system.dart';
import 'package:just_game_engine_editor/src/physics/physics_2d/physics_2d_body_binding_system.dart';
import 'package:just_game_engine_editor/src/graphics/graphics_2d/built_in_lighting_2d_contributions.dart';
import 'package:just_game_engine_editor/src/plugin/just_game_editor_plugin.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_session.dart';

/// A module that counts how often it is disposed.
class _Counted extends EditorModule {
  _Counted(this.id);

  @override
  final String id;

  int disposed = 0;

  @override
  String get name => 'Counted';

  @override
  void dispose() => disposed++;
}

/// Another class under the same id: what a hot reload hands over.
class _Replacement extends _Counted {
  _Replacement(super.id);
}

/// Records what a built-in module hears.
class _Listening extends EditorModule {
  _Listening(EditorScope _);

  final List<String> assets = [];
  final List<bool> playing = [];

  @override
  String get id => 'test.listening';

  @override
  String get name => 'Listening';

  @override
  void onAssetChanged(String path) => assets.add(path);

  @override
  void onPlayStateChanged(bool isPlaying) => playing.add(isPlaying);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late JustGameEditorPlugin plugin;

  Future<void> start({bool visible = true}) async {
    engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    plugin = JustGameEditorPlugin(engine: engine, startVisible: visible);
    addTearDown(plugin.dispose);
    await plugin.attach(plugin.engine);
  }

  Entity block(String name, double x) =>
      engine.world.createEntityWithComponents([
        TransformComponent(position: Vector3(x, 0, 0)),
      ], name: name);

  group('authoring holds the game still', () {
    test('selecting an animated sprite does not start the game', () async {
      await start();
      if (!kDebugMode) return;
      final coin = engine.world.createEntityWithComponents([
        TransformComponent(),
        SpriteAnimationComponent(atlasPath: 'assets/sprites/coin.json')
          ..isPlaying = true,
      ], name: 'Coin');
      plugin.sceneState.selectEntity(coin);
      plugin.update(1 / 60);
      expect(engine.time.timeScale, 0);
    });

    test('nor does the game setting its own time while authoring', () async {
      await start();
      if (!kDebugMode) return;
      engine.time.timeScale = 1;
      plugin.update(1 / 60);
      expect(engine.time.timeScale, 0);
    });
  });

  group('the game\'s time scale comes back as it was', () {
    test(
      'showing the status panel again does not take 0 for the game\'s',
      () async {
        await start(visible: false);
        if (!kDebugMode) return;
        engine.time.timeScale = 0.5;
        plugin.setVisible(true);
        expect(engine.time.timeScale, 0);
        plugin.isStatusPanelVisible.value = false;
        plugin.setVisible(true);
        plugin.setVisible(false);
        expect(engine.time.timeScale, 0.5);
      },
    );
  });

  group('a play-test', () {
    test('a spawner that throws leaves no play-test, no snapshot and '
        'nothing half-spawned', () async {
      await start();
      if (!kDebugMode) return;
      engine.world.createEntityWithComponents([
        TransformComponent(),
        SpawnComponent(spawner: 'good'),
      ], name: 'Start 1');
      engine.world.createEntityWithComponents([
        TransformComponent(),
        SpawnComponent(spawner: 'bad'),
      ], name: 'Start 2');
      plugin.scope.spawners.value = [
        Spawner(
          id: 'good',
          spawn: (world, point) => world.createEntityWithComponents([
            TransformComponent(),
          ], name: 'Player'),
        ),
        Spawner(id: 'bad', spawn: (_, _) => throw StateError('no sprite')),
      ];
      final before = engine.world.entities.where((e) => e.isAlive).length;

      plugin.play();

      expect(plugin.playController.isRunning, isFalse);
      expect(
        plugin.playController.snapshot,
        isNull,
        reason: 'a save goes on writing the level as it stands',
      );
      expect(engine.world.entities.where((e) => e.isAlive), hasLength(before));
      expect(
        engine.world.entities.where((e) => e.isAlive && e.name == 'Player'),
        isEmpty,
      );
      expect(
        plugin.logService.entries.value.map((e) => e.message),
        contains(contains('a spawner threw')),
      );
    });

    test(
      'what was done during it is not undone onto the level after Stop',
      () async {
        await start();
        if (!kDebugMode) return;
        final crate = block('Crate', 10);
        plugin.history.push(
          CallbackCommand(label: 'authored', onRedo: () {}, onUndo: () {}),
        );

        plugin.play();
        final t = crate.getComponent<TransformComponent>()!;
        final before = TransformSnapshot.of(crate);
        t.setPositionXY(500, 0);
        plugin.viewport.commitTransform!(
          TransformCommand(
            label: 'Move Crate',
            entities: [crate],
            before: [before],
            after: [TransformSnapshot.of(crate)],
            sceneState: plugin.sceneState,
          ),
        );
        expect(plugin.history.nextUndoLabel.value, 'Move Crate');
        plugin.stop();

        // Read afresh: Stop may put the transform back as a new instance.
        double x() => crate.getComponent<TransformComponent>()!.position.x;
        expect(x(), 10, reason: 'Stop put it back');
        expect(plugin.history.nextUndoLabel.value, 'authored');
        plugin.history.undo();
        expect(x(), 10, reason: 'the play-time move is not a step');
      },
    );

    test('a step undone during it is a step again after Stop', () async {
      await start();
      if (!kDebugMode) return;
      plugin.history.push(
        CallbackCommand(label: 'authored', onRedo: () {}, onUndo: () {}),
      );
      plugin.play();
      plugin.history.undo();
      plugin.stop();
      expect(plugin.history.nextUndoLabel.value, 'authored');
      expect(plugin.history.canRedo.value, isFalse);
    });

    test('a save during it writes the roots in the tree\'s order', () async {
      await start();
      if (!kDebugMode) return;
      final a = block('A', 0);
      final b = block('B', 0);
      plugin.sceneState.openScene(
        EditorScene(name: 'order'),
        rootOrder: [b.id, a.id],
      );
      plugin.play();
      expect(
        [for (final e in plugin.playController.snapshot!.entities) e['name']],
        ['B', 'A'],
      );
      plugin.stop();
    });

    test('the snapshot is taken in the order it is given', () {
      final world = World()..initialize();
      addTearDown(world.dispose);
      final scope = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        world: world,
      );
      addTearDown(scope.dispose);
      final a = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'A');
      final b = world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'B');
      final snapshot = PlaySnapshot.capture(
        world,
        scope.codec,
        rootOrder: [b.id, a.id],
      );
      expect([for (final e in snapshot.entities) e['name']], ['B', 'A']);
    });
  });

  group('taken off the engine', () {
    test('detach closes the editor and gives the game back; attach takes '
        'up again', () async {
      await start(visible: false);
      if (!kDebugMode) return;
      engine.time.timeScale = 0.75;
      plugin.setVisible(true);
      expect(plugin.debuggerController.isBound, isTrue);
      plugin.play();

      plugin.detach();

      expect(plugin.isVisible.value, isFalse);
      expect(plugin.playController.isRunning, isFalse);
      expect(engine.time.timeScale, 0.75);
      expect(plugin.debuggerController.isBound, isFalse);
      final collision = engine.world.getSystem<MapCollisionSystem>();
      expect(
        collision?.isActive ?? true,
        isTrue,
        reason: 'play-only systems run again for the game',
      );

      await plugin.attach(engine);
      plugin.setVisible(true);
      expect(plugin.isVisible.value, isTrue);
    });

    test('the debugger is fed only while the editor is shown', () async {
      await start();
      if (!kDebugMode) return;
      expect(plugin.debuggerController.isBound, isTrue);
      plugin.setVisible(false);
      expect(plugin.debuggerController.isBound, isFalse);
      plugin.setVisible(true);
      expect(plugin.debuggerController.isBound, isTrue);
    });
  });

  group('disposed', () {
    test('takes back what it put on the engine', () async {
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      engine.world.addSystem(RenderSystem());
      final p = JustGameEditorPlugin(engine: engine);
      if (!kDebugMode) {
        p.dispose();
        return;
      }
      await p.attach(p.engine);
      p.play();
      expect(engine.world.getSystem<RenderSystem>()?.shouldRender, isNotNull);

      p.dispose();

      expect(engine.world.getSystem<RenderSystem>()?.shouldRender, isNull);
      expect(engine.world.systems.whereType<EditorLogCaptureSystem>(), isEmpty);
      expect(
        engine.world.systems.whereType<Physics2DBodyBindingSystem>(),
        isEmpty,
      );
      expect(engine.time.timeScale, isNot(0), reason: 'the game runs again');
      // Another editor on the same engine starts cleanly.
      final again = JustGameEditorPlugin(engine: engine);
      addTearDown(again.dispose);
      await again.attach(again.engine);
      again.update(1 / 60);
      expect(again.isVisible.value, isTrue);
    });
  });

  group('what modules hear', () {
    test('built-in modules hear changed files and play-tests', () async {
      await start();
      if (!kDebugMode) return;
      plugin.scope.addBuiltIn(_Listening.new);
      final listening = plugin.scope.modules.withBuiltIns
          .whereType<_Listening>()
          .single;
      plugin.reloadAsset('assets/sprites/coin.png');
      plugin.reloadAssets(['assets/sprites/gem.png']);
      expect(listening.assets, [
        'assets/sprites/coin.png',
        'assets/sprites/gem.png',
      ]);
      plugin.play();
      plugin.stop();
      expect(listening.playing, [true, false]);
    });
  });

  group('undo and redo during a play-test', () {
    test(
      'reach only what was done in it, not a step from before Play',
      () async {
        await start();
        if (!kDebugMode) return;
        var undone = 0;
        plugin.history.push(
          CallbackCommand(
            label: 'Paint tiles',
            onRedo: () {},
            onUndo: () => undone++,
          ),
        );
        plugin.play();
        expect(plugin.history.canUndo.value, isFalse);
        plugin.history.undo();
        expect(undone, 0, reason: 'Stop would not put a map file back');

        var playUndone = 0;
        plugin.history.push(
          CallbackCommand(
            label: 'Move',
            onRedo: () {},
            onUndo: () => playUndone++,
          ),
        );
        plugin.history.undo();
        plugin.history.undo();
        expect((undone, playUndone), (0, 1));

        plugin.stop();
        expect(plugin.history.nextUndoLabel.value, 'Paint tiles');
        expect(plugin.history.canRedo.value, isFalse);
      },
    );

    test('a step undone before Play is not redone during it', () async {
      await start();
      if (!kDebugMode) return;
      var redone = 0;
      plugin.history.push(
        CallbackCommand(
          label: 'Paint tiles',
          onRedo: () => redone++,
          onUndo: () {},
        ),
      );
      plugin.history.undo();
      final before = redone;
      plugin.play();
      expect(plugin.history.canRedo.value, isFalse);
      plugin.history.redo();
      expect(redone, before);
      plugin.stop();
      expect(plugin.history.nextRedoLabel.value, 'Paint tiles');
    });
  });

  group('the selection after Stop', () {
    test('an entity play destroyed is selected as it was made again', () async {
      await start();
      if (!kDebugMode) return;
      plugin.sceneState.openScene(EditorScene(name: 'yard'));
      final crate = block('Crate', 10);
      plugin.sceneState.selectEntity(crate);
      plugin.play();
      engine.world.destroyEntity(crate);
      plugin.stop();
      final selected = plugin.sceneState.selectedEntity.value!;
      expect(selected.isAlive, isTrue);
      expect(selected.name, 'Crate');
      expect(plugin.sceneState.multiSelectedIds.value, {selected.id});
      expect(plugin.sceneState.isDirty.value, isFalse);
    });

    test('one the play-test made is let go of', () async {
      await start();
      if (!kDebugMode) return;
      plugin.sceneState.openScene(EditorScene(name: 'yard'));
      plugin.play();
      plugin.sceneState.selectEntity(block('Player', 0));
      plugin.stop();
      expect(plugin.sceneState.hasAnySelection, isFalse);
      expect(plugin.entities.selectionEntities, isEmpty);
    });
  });

  group('Play waits for a drag', () {
    test('Play and Restart, while a ruler guide is pulled', () async {
      await start();
      if (!kDebugMode) return;
      plugin.sceneState.openScene(EditorScene(name: 'yard'));
      plugin.openLevelDesigner();
      final session = plugin.designer.value!;
      CommandContext context() => CommandContext(
        scope: plugin.scope,
        session: session,
        host: plugin,
        modifiers: const ModifierKeys(),
      );
      void run(String id) => plugin.scope.commands.byId(id)!.run(context());

      expect(
        session.onChromePointerDown(const Offset(300, 5), const Size(800, 600)),
        isTrue,
      );
      expect(session.hasChromeGesture, isTrue);
      run('editor.playToggle');
      expect(plugin.playController.isRunning, isFalse);

      session.onPointerCancel();
      run('editor.playToggle');
      expect(plugin.playController.isRunning, isTrue);
      plugin.stop();
      plugin.closeLevelDesigner();
    });
  });

  group('Play from here', () {
    test('when Play did not start, the authored player stays put', () async {
      await start();
      if (!kDebugMode) return;
      final player = engine.world.createEntityWithComponents([
        TransformComponent(),
        TagComponent('player'),
      ], name: 'Player');
      engine.world.createEntityWithComponents([
        TransformComponent(),
        SpawnComponent(spawner: 'bad'),
      ], name: 'Start');
      plugin.scope.spawners.value = [
        Spawner(id: 'bad', spawn: (_, _) => throw StateError('no sprite')),
      ];
      expect(plugin.playFrom(Vector3(500, 40, 0)), isFalse);
      expect(plugin.playController.isRunning, isFalse);
      final at = player.getComponent<TransformComponent>()!.position;
      expect((at.x, at.y), (0.0, 0.0));
    });
  });

  group('modules handed over again', () {
    test('one replaced by another class is disposed once', () async {
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      final old = _Counted('test.counted');
      plugin = JustGameEditorPlugin(engine: engine, modules: [old]);
      addTearDown(plugin.dispose);
      final replacement = _Replacement('test.counted');
      plugin.syncModules([replacement]);
      expect(old.disposed, 1);
      expect(plugin.scope.modules.byId('test.counted'), same(replacement));
    });
  });

  group('starting', () {
    test('before the engine has started: nothing is done, and it starts '
        'once the engine has', () async {
      if (!kDebugMode) return;
      engine = Engine();
      addTearDown(engine.dispose);
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      addTearDown(plugin.dispose);
      await plugin.attach(engine);
      expect(plugin.isInitialized, isFalse);

      await engine.initialize();
      await plugin.attach(engine);
      expect(plugin.isInitialized, isTrue);
      expect(
        engine.world.systems.whereType<EditorLogCaptureSystem>(),
        hasLength(1),
      );
    });

    test('started twice at once, it starts once', () async {
      if (!kDebugMode) return;
      engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      addTearDown(plugin.dispose);
      await Future.wait([plugin.attach(engine), plugin.attach(engine)]);
      expect(plugin.isInitialized, isTrue);
      expect(
        engine.world.systems.whereType<EditorLogCaptureSystem>(),
        hasLength(1),
      );
    });
  });

  group('data files are not sprite atlases', () {
    test('prefabs, project settings and input actions', () {
      for (final path in [
        'assets/prefabs/crate.prefab.json',
        'assets/project/tags.json',
        'assets/project/physics.json',
        'tags.json',
        'assets/input/game.input.json',
      ]) {
        expect(
          JustGameEditorPlugin.isSpriteAtlasPath(path),
          isFalse,
          reason: path,
        );
        // Not as a sprite; a prefab file drops as an instance of itself.
        if (!path.endsWith('.prefab.json')) {
          expect(
            JustGameEditorPlugin.canDropAsset(path),
            isFalse,
            reason: path,
          );
        }
      }
      expect(
        JustGameEditorPlugin.isSpriteAtlasPath('assets/sprites/coin.json'),
        isTrue,
      );
    });
  });

  group('Shift+L', () {
    test('the scene is unlit only while authoring', () async {
      await start();
      if (!kDebugMode) return;
      final pass = BuiltInLighting2DContributions.passOf(engine)!;
      expect(pass.enabled, isTrue);
      plugin.scope.sceneState.openScene(EditorScene(name: 'cave'));
      plugin.scope.commands
          .byId(BuiltInLighting2DContributions.toggleId)!
          .run(
            CommandContext(
              scope: plugin.scope,
              modifiers: const ModifierKeys(),
            ),
          );
      plugin.update(1 / 60);
      expect(pass.enabled, isFalse);

      plugin.play();
      plugin.update(1 / 60);
      expect(pass.enabled, isTrue, reason: 'the play-test is lit');

      plugin.stop();
      plugin.update(1 / 60);
      expect(pass.enabled, isFalse, reason: 'back to the unlit view');

      plugin.setVisible(false);
      plugin.update(1 / 60);
      expect(pass.enabled, isTrue, reason: 'the game, without the editor');
    });
  });
}
