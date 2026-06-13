import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plugin defaults to hidden editor state', () {
    Engine.resetInstance();
    final plugin = JustGameEditorPlugin(engine: Engine());

    expect(plugin.isVisible, isFalse);

    plugin.dispose();
    Engine.resetInstance();
  });

  test('plugin toggles editor visibility', () {
    Engine.resetInstance();
    final plugin = JustGameEditorPlugin(engine: Engine());

    plugin.toggleVisibility();
    expect(plugin.isVisible, isTrue);

    plugin.toggleVisibility();
    expect(plugin.isVisible, isFalse);

    plugin.dispose();
    Engine.resetInstance();
  });

  test('plugin initialize registers systems only once', () async {
    Engine.resetInstance();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      Engine.resetInstance();
      return;
    }

    await plugin.onInitialize();
    await plugin.onInitialize();

    int countSystem<T>() => engine.world.systems.whereType<T>().length;

    expect(countSystem<SimpleMovementSystem>(), 1);
    expect(countSystem<PhysicsBridgeSystem>(), 1);
    expect(countSystem<PhysicsBodyBindingSystem>(), 1);
    expect(countSystem<PhysicsJointBindingSystem>(), 1);

    plugin.dispose();
    Engine.resetInstance();
  });

  test('plugin reassemble does not duplicate systems', () async {
    Engine.resetInstance();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      Engine.resetInstance();
      return;
    }

    await plugin.onInitialize();
    plugin.reassemble();
    plugin.reassemble();

    int countSystem<T>() => engine.world.systems.whereType<T>().length;

    expect(countSystem<SimpleMovementSystem>(), 1);
    expect(countSystem<PhysicsBridgeSystem>(), 1);
    expect(countSystem<PhysicsBodyBindingSystem>(), 1);
    expect(countSystem<PhysicsJointBindingSystem>(), 1);

    plugin.dispose();
    Engine.resetInstance();
  });

  test('plugin only adds expected editor systems', () async {
    Engine.resetInstance();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      Engine.resetInstance();
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

    await plugin.onInitialize();

    final afterCounts = <Type, int>{};
    for (final system in engine.world.systems) {
      afterCounts.update(
        system.runtimeType,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    const allowedAddedTypes = <Type>{
      SimpleMovementSystem,
      PhysicsBridgeSystem,
      PhysicsBodyBindingSystem,
      PhysicsJointBindingSystem,
    };

    final actuallyAddedTypes = <Type>{};
    for (final entry in afterCounts.entries) {
      final before = beforeCounts[entry.key] ?? 0;
      if (entry.value > before) {
        actuallyAddedTypes.add(entry.key);
      }
    }

    expect(actuallyAddedTypes.difference(allowedAddedTypes), isEmpty);
    expect(engine.world.systems.whereType<SimpleMovementSystem>().length, 1);
    expect(engine.world.systems.whereType<PhysicsBridgeSystem>().length, 1);
    expect(
      engine.world.systems.whereType<PhysicsBodyBindingSystem>().length,
      1,
    );
    expect(
      engine.world.systems.whereType<PhysicsJointBindingSystem>().length,
      1,
    );

    plugin.dispose();
    Engine.resetInstance();
  });

  test('registered descriptors match factory runtime type', () async {
    Engine.resetInstance();
    final engine = Engine();
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);

    if (!kDebugMode) {
      plugin.dispose();
      Engine.resetInstance();
      return;
    }

    await plugin.onInitialize();

    final descriptors = CustomComponentRegistry.instance.descriptors;
    expect(descriptors, isNotEmpty);

    for (final descriptor in descriptors) {
      final instance = descriptor.factory();
      expect(
        instance.runtimeType.toString(),
        descriptor.type,
        reason:
            'Descriptor "${descriptor.name}" factory type and declared type must match.',
      );
    }

    plugin.dispose();
    Engine.resetInstance();
  });

  test(
    'serialization service returns non-blocking draft payload shape',
    () async {
      const service = EditorSerializationService();

      final result = await service.saveDraft(
        const EditorSerializationRequest(
          levelId: 'level_runtime_01',
          ecsSnapshot: <String, dynamic>{
            'entities': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'e_player',
                'components': <String>['Transform', 'Velocity'],
              },
            ],
          },
        ),
      );

      expect(result.jsonDraft, contains('level_runtime_01'));
      expect(result.todos, isNotEmpty);
    },
  );
}
