// Children stay children through every edit: made under their parent and
// taken out of it on undo, kept there by a resize or an edit to the parent,
// copied beside themselves — and moved with their parent, which a transform
// being a place in the world, not an offset, would otherwise leave behind.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late World world;
  late EditorScope scope;
  late EntityOps ops;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    ops = EntityOps(
      scope: scope,
      world: () => world,
      sceneState: scope.sceneState,
      camera: Camera.new,
    );
    scope.sceneState.openScene(Scene(name: 'level'), const {});
  });

  List<EntityId> childrenOf(Entity entity) =>
      entity.getComponent<ChildrenComponent>()?.childIds ?? const [];
  Entity? parentOf(Entity entity) {
    final id = entity.getComponent<ParentComponent>()?.parentId;
    return id == null ? null : world.getEntity(id);
  }

  Offset at(Entity e) {
    final p = e.getComponent<TransformComponent>()!.position;
    return Offset(p.x, p.y);
  }

  Entity node(String name, {Entity? under, double x = 0, double y = 0}) {
    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3(x, y, 0)),
      RectangleComponent(width: 10, height: 10),
    ], name: name);
    scope.sceneState.registerEntity(entity);
    if (under != null) ops.reparentEntity(entity, under);
    return entity;
  }

  EntitySpec spec(String name, {String? under, double x = 0}) => EntitySpec(
    name: name,
    componentsJson: [
      scope.codec.encode(TransformComponent(position: Vector3(x, 0, 0)))!,
      scope.codec.encode(LayerComponent(mapLayer: 1))!,
    ],
    codec: scope.codec,
    parentName: under,
  );

  test('an entity made under a parent is its child; undo takes it out', () {
    final parent = node('Parent');
    final older = node('Older', under: parent);
    final create = CreateEntitiesCommand(
      label: 'Place',
      world: world,
      sceneState: scope.sceneState,
      specs: [spec('Child', under: 'Parent')],
    );
    scope.history.push(create);
    final child = world.findEntityByName('Child')!;
    expect(parentOf(child), same(parent));
    expect(childrenOf(parent), [older.id, child.id]);

    scope.history.undo();
    expect(childrenOf(parent), [older.id]);
    scope.history.redo();
    final again = world.findEntityByName('Child')!;
    expect(parentOf(again), same(parent));
    expect(again.getComponent<LayerComponent>()!.mapLayer, 1);
  });

  test('a map made for what is put on it, and what was put there, are one '
      'step: redo makes the map first and puts them back in it', () {
    final provision = scope.mapProvision;
    provision.ensure(world);
    final create = CreateEntitiesCommand(
      label: 'Place',
      world: world,
      sceneState: scope.sceneState,
      specs: [spec('Rock', under: LevelMaps.primaryName)],
    )..redo();
    provision.keepWith('Place Rock', create);
    expect(scope.history.undoEntries, hasLength(1));
    final rock = world.findEntityByName('Rock')!;
    expect(parentOf(rock)?.name, LevelMaps.primaryName);

    scope.history.undo();
    expect(world.findEntityByName('Rock'), isNull);
    expect(LevelMaps.primaryEntity(world), isNull);

    scope.history.redo();
    final map = LevelMaps.primaryEntity(world)!;
    final back = world.findEntityByName('Rock')!;
    expect(parentOf(back), same(map));
    expect(childrenOf(map), [back.id]);
  });

  test('rewriting a child in place keeps its parent, and the parent keeps '
      'its children', () {
    final parent = node('Parent');
    final child = node('Child', under: parent);

    void rewrite(Entity e) {
      final before = EntitySpec.of(e, scope.codec);
      (e.getComponent<RenderableComponent>()! as RectangleComponent).width = 40;
      scope.history.pushApplied(
        EntityStateCommand(
          label: 'Resize',
          world: world,
          sceneState: scope.sceneState,
          ids: [e.id],
          before: [before],
          after: [EntitySpec.of(e, scope.codec)],
        ),
      );
      scope.history
        ..undo()
        ..redo();
    }

    rewrite(child);
    expect(parentOf(child), same(parent));
    rewrite(parent);
    expect(childrenOf(parent), [child.id]);
  });

  test('a copy of a child goes beside it, under the same parent, on the same '
      'map layer', () {
    final parent = node('Parent');
    final child = node('Child', under: parent)
      ..addComponent(LayerComponent(mapLayer: 2));
    final last = node('Last', under: parent);
    scope.sceneState.selectEntity(child);

    ops.duplicateSelection(scope.history, gridSize: 32);
    final copy = scope.sceneState.selectedEntity.value!;
    expect(copy, isNot(same(child)));
    expect(parentOf(copy), same(parent));
    expect(childrenOf(parent), [child.id, copy.id, last.id]);
    expect(copy.getComponent<LayerComponent>()!.mapLayer, 2);
  });

  group('moving a parent carries its children', () {
    late LevelDesignerSession session;
    late Entity parent, child, grandchild;

    setUp(() {
      session = LevelDesignerSession(
        scope: scope,
        uniqueName: (p) => p,
        onDuplicate: () {},
        onDelete: () {},
        onArray: (_, _) {},
        readModifiers: () => const ModifierKeys(),
      );
      addTearDown(session.dispose);
      session.controller.snapEnabled.value = false;
      parent = node('Parent', x: 100, y: 100);
      child = node('Child', under: parent, x: 300, y: 100);
      grandchild = node('Grandchild', under: child, x: 300, y: 200);
    });

    test('a drag, as one step', () {
      final steps = scope.history.undoEntries.length;
      session
        ..setTool(BuiltInTools.select)
        ..onPointerDown(const Offset(100, 100), 32)
        ..onPointerMove(const Offset(130, 150), 32)
        ..onPointerUp(const Offset(130, 150), 32);
      expect(at(parent), const Offset(130, 150));
      expect(at(child), const Offset(330, 150));
      expect(at(grandchild), const Offset(330, 250));
      expect(scope.history.undoEntries, hasLength(steps + 1));

      scope.history.undo();
      expect(at(child), const Offset(300, 100));
      expect(at(grandchild), const Offset(300, 200));
    });

    test('a nudge and a quarter turn', () {
      session.ops.nudge([parent], const Offset(10, 0));
      expect(at(grandchild), const Offset(310, 200));
      session.ops.rotateQuarter([parent], 1);
      // About the parent's own middle, (110, 100).
      expect(at(child).dx, closeTo(110, 1e-6));
      expect(at(child).dy, closeTo(300, 1e-6));
      scope.history
        ..undo()
        ..undo();
      expect(at(grandchild), const Offset(300, 200));
    });

    test('a child moved with its parent selected too moves once', () {
      scope.sceneState
        ..selectEntity(parent)
        ..toggleMultiSelect(child);
      session.ops.nudge([parent, child], const Offset(0, 5));
      expect(at(child), const Offset(300, 105));
      expect(at(grandchild), const Offset(300, 205));
    });
  });
}
