import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/ecs/systems/editor_log_capture_system.dart';
import 'package:just_game_engine_editor/src/core/ecs/systems/physics_body_binding_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plugin is hidden until initialized', () {
    final plugin = JustGameEditorPlugin(engine: Engine());

    expect(plugin.isVisible.value, isFalse);

    plugin.dispose();
  });

  test('plugin toggles editor visibility', () {
    final plugin = JustGameEditorPlugin(engine: Engine());

    plugin.toggleVisibility();
    expect(plugin.isVisible.value, isTrue);

    plugin.toggleVisibility();
    expect(plugin.isVisible.value, isFalse);

    plugin.dispose();
  });

  test('initializing opens the editor and its status panel', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);
    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    await plugin.attach(plugin.engine);
    expect(plugin.isVisible.value, isTrue, reason: 'F1 state');
    expect(plugin.isStatusPanelVisible.value, isTrue, reason: 'F2 state');
    expect(engine.time.timeScale, 0, reason: 'authoring pauses the game');

    plugin.dispose();
  });

  test('startVisible: false leaves it closed until F1', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    await plugin.attach(plugin.engine);
    expect(plugin.isVisible.value, isFalse);
    expect(plugin.isStatusPanelVisible.value, isFalse);

    plugin.dispose();
  });

  test('plugin initialize registers systems only once', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    await plugin.attach(plugin.engine);
    await plugin.attach(plugin.engine);

    int countSystem<T>() => engine.world.systems.whereType<T>().length;

    expect(
      countSystem<SimpleMovementSystem>(),
      0,
      reason: "the game's own systems are its boot's to add",
    );
    expect(countSystem<PhysicsBodyBindingSystem>(), 1);
    expect(countSystem<PhysicsJointBindingSystem>(), 1);
    expect(countSystem<EditorLogCaptureSystem>(), 1);

    plugin.dispose();
  });

  test('plugin reassemble does not duplicate systems', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    await plugin.attach(plugin.engine);
    plugin.reassemble();
    plugin.reassemble();

    int countSystem<T>() => engine.world.systems.whereType<T>().length;

    expect(
      countSystem<SimpleMovementSystem>(),
      0,
      reason: "the game's own systems are its boot's to add",
    );
    expect(countSystem<PhysicsBodyBindingSystem>(), 1);
    expect(countSystem<PhysicsJointBindingSystem>(), 1);
    expect(countSystem<EditorLogCaptureSystem>(), 1);

    plugin.dispose();
  });

  test('plugin only adds expected editor systems', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    final beforeCounts = <Type, int>{};
    for (final system in engine.world.systems) {
      beforeCounts.update(
        system.runtimeType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    await plugin.attach(plugin.engine);

    final afterCounts = <Type, int>{};
    for (final system in engine.world.systems) {
      afterCounts.update(
        system.runtimeType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    // Compared by name (not `Type`) because the editor's own systems aren't
    // exported from the package's public barrel, so this test file (which
    // only imports the barrel) has no `Type` literal to reference them with.
    const allowedAddedTypeNames = <String>{
      'PhysicsBodyBindingSystem',
      'PhysicsJointBindingSystem',
      'EditorLogCaptureSystem',
      'SpriteLoadSystem',
      // Tile maps are drawn in the editor as in the game; their collision
      // is built only while a play-test runs.
      'LevelMapSystem',
      'MapCollisionSystem',
      'SpriteAnimationSystem',
      'AnimatorSystem',
      'TimelineSystem',
      'TimelineTriggerSystem',
    };

    final actuallyAddedTypeNames = <String>{};
    for (final entry in afterCounts.entries) {
      final before = beforeCounts[entry.key] ?? 0;
      if (entry.value > before) {
        actuallyAddedTypeNames.add(entry.key.toString());
      }
    }

    expect(actuallyAddedTypeNames.difference(allowedAddedTypeNames), isEmpty);
    expect(engine.world.systems.whereType<SimpleMovementSystem>(), isEmpty);
    expect(
      engine.world.systems.whereType<PhysicsBodyBindingSystem>().length,
      1,
    );
    expect(
      engine.world.systems.whereType<PhysicsJointBindingSystem>().length,
      1,
    );
    expect(engine.world.systems.whereType<EditorLogCaptureSystem>().length, 1);

    plugin.dispose();
  });

  test('what a definition creates resolves back to that definition', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      return;
    }

    await plugin.attach(plugin.engine);

    final definitions = plugin.scope.definitions.definitions;
    expect(definitions, isNotEmpty);

    for (final definition in definitions) {
      final instance = definition.create();
      expect(
        plugin.scope.definitions.definitionFor(instance),
        same(definition),
        reason: 'What "${definition.type}" creates must resolve back to it.',
      );
    }

    plugin.dispose();
  });
}
