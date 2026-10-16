// Everything an editor owns lives in its scope. That is only worth anything
// if two scopes really share nothing, if a reload really rebuilds from
// scratch, and if the module lifecycle really fires — each promise is one
// test here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

class _CountingModule extends EditorModule {
  _CountingModule({this.prefabId = 'test.thing'});

  final String prefabId;
  int registered = 0;
  final opened = <String>[];
  double ticked = 0;
  bool disposed = false;

  @override
  String get id => 'test.counting';

  @override
  String get name => 'Counting';

  @override
  List<PrefabDefinition> get prefabs => [
    PrefabDefinition(
      id: prefabId,
      name: 'Mine',
      category: 'Test',
      icon: Icons.circle,
      color: Colors.red,
      build: (_, _) => [TransformComponent()],
    ),
  ];

  @override
  List<String> get componentGroups => const ['Test'];

  @override
  void onRegister(EditorModuleContext context) => registered++;

  @override
  void onSceneOpened(String sceneName) => opened.add(sceneName);

  @override
  void onUpdate(double dt) => ticked += dt;

  @override
  void dispose() => disposed = true;
}

void main() {
  test('a second EditorScope shares no state', () {
    final a = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: World()..initialize(),
      modules: [_CountingModule()],
    );
    a.selectDesigner('test.counting');
    final b = testScope();

    expect(a.prefabs.byId('test.thing'), isNotNull);
    expect(b.prefabs.byId('test.thing'), isNull);
    expect(a.modules.all, hasLength(1));
    expect(b.modules.all, isEmpty);
    expect(identical(a.sceneState, b.sceneState), isFalse);
    expect(identical(a.codec, b.codec), isFalse);

    // Disposing one leaves the other working.
    a.dispose();
    expect(b.prefabs.byId(BuiltInPrefabs.rectangleId), isNotNull);
    expect(b.definitions.definitions, isNotEmpty);
  });

  test('every service resolves, on the same definitions the game uses', () {
    final scope = testScope();
    expect(scope.definitions, same(scope.context.definitions));
    expect(scope.codec.definitions, same(scope.definitions));
    expect(scope.scenes.codec, same(scope.codec));
    expect(scope.fieldEditors.typeIds, isNotEmpty);
    expect(scope.extras.forType('SpriteAnimationComponent'), isNotNull);
    expect(scope.prefabs.all, isNotEmpty);
    expect(scope.layers.all, isNotEmpty);
    expect(scope.modules.all, isEmpty);
    expect(scope.log, isNotNull);
    expect(scope.sceneState, isNotNull);
    expect(scope.world, isNotNull);
    expect(scope.engine, isNull);
  });

  test('reload is idempotent and forgets what a module stopped giving', () {
    final module = _CountingModule();
    final scope = testScope(modules: [module]);
    scope.selectDesigner(module.id);
    final count = scope.prefabs.all.length;

    scope.reload();
    scope.reload();
    expect(scope.prefabs.all.length, count);
    expect(module.registered, 1, reason: 'once, however often it is rebuilt');

    scope.modules.unregister(module.id);
    scope.reload();
    expect(scope.prefabs.byId('test.thing'), isNull);
    expect(scope.prefabs.all.length, count - 1);
    expect(module.disposed, isTrue);
  });

  test('a module replaces a built-in by reusing its id', () {
    final scope = testScope(
      modules: [_CountingModule(prefabId: BuiltInPrefabs.rectangleId)],
    );
    scope.selectDesigner('test.counting');
    expect(scope.prefabs.byId(BuiltInPrefabs.rectangleId)?.name, 'Mine');
    expect(scope.modules.componentGroups, ['Test']);
  });

  test('onSceneOpened and onUpdate reach every module', () {
    final module = _CountingModule();
    final scope = testScope(modules: [module]);
    scope.selectDesigner(module.id);
    scope.modules.notifySceneOpened('level_01');
    scope.modules.notifyUpdate(0.5);
    expect(module.opened, ['level_01']);
    expect(module.ticked, 0.5);
  });

  test('tools are per session; prefabs are per scope', () {
    final scope = testScope();
    LevelDesignerSession open() => LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
    );
    final a = open();
    final b = open();
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    expect(identical(a.tools, b.tools), isFalse);
    expect(a.tools.byId(BuiltInTools.select), isNotNull);
    expect(b.tools.byId(BuiltInTools.select), isNotNull);
    expect(identical(a.controller.prefabs, scope.prefabs), isTrue);
    expect(identical(b.controller.prefabs, scope.prefabs), isTrue);
  });

  test(
    'the plugin forwards its ticks and scene opens to the modules',
    () async {
      final module = _CountingModule();
      final plugin = JustGameEditorPlugin(engine: Engine(), modules: [module]);
      addTearDown(() {
        plugin.dispose();
      });

      // What engine.plugins calls each frame, before the editor is even
      // initialised: modules see wall-clock time regardless.
      plugin.update(0.25);
      plugin.update(0.25);
      expect(module.ticked, 0.5);
      expect(module.registered, 1);
      expect(plugin.scope.modules.byId(module.id), same(module));
    },
  );
}
