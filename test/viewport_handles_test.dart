// Points a module lets the author drag in the viewport (ViewportHandles):
// a press on one takes it before the gizmo, the drag goes to the module,
// and the drag — or a click — is one undo step. And prefab variants: a
// module offering another module's prefabs again, with more to them.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/input/viewport_input.dart';
import 'package:just_game_engine_editor/src/extension/built_in_audio_contributions.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/shapes/polygon_handles.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/shapes/shape_prefabs.dart';

/// One handle at the selection's position: dragging it slides the entity
/// along the ground; clicking it (Alt: twice) lifts it by a metre.
class _Slide extends ViewportHandles {
  @override
  String get id => 'test.slide';

  @override
  List<ViewportHandle> handlesOf(Entity entity, EditorScope scope) {
    final t = entity.getComponent<TransformComponent>();
    if (t == null) return const [];
    return [
      ViewportHandle(
        position: Vector3.copy(t.position),
        component: t,
        onDrag: (drag) {
          final p = drag.onPlane(drag.start, Vector3(0, -1, 0));
          if (p != null) {
            t.position.setValues(
              drag.snapped(p.x),
              t.position.y,
              drag.snapped(p.z),
            );
          }
        },
        onClick: (click) => t.position.y -= click.alt ? 2 : 1,
      ),
    ];
  }
}

class _Handles extends EditorModule {
  @override
  String get id => 'test.handles';

  @override
  String get name => 'Handles';

  @override
  List<ViewportHandles> get viewportHandles => [_Slide()];
}

/// A look with a shape, as a 3-D shape component is.
class _Solid extends Component implements SolidShapeSource {
  @override
  Object get solidKey => 'solid';

  @override
  List<SolidPart> get solidParts => const [SolidBox(0.5, 0.5, 0.5)];
}

class _Marker extends Component {}

PrefabDefinition _prefab(String id, List<Component> Function() parts) =>
    PrefabDefinition(
      id: id,
      name: id[0].toUpperCase() + id.substring(1),
      category: 'Shapes',
      icon: Icons.square_outlined,
      color: const Color(0xFF26A69A),
      dimensions: Dimensions.threeD,
      build: (_, _) => [TransformComponent(), ...parts()],
      buildAt: (at) => [
        TransformComponent(position: Vector3.copy(at.position)),
        ...parts(),
      ],
    );

class _Shapes extends EditorModule {
  @override
  String get id => 'test.shapes';

  @override
  String get name => 'Shapes';

  @override
  List<PrefabDefinition> get prefabs => [
    _prefab('cube', () => [_Solid()]),
    _prefab('marker', () => [_Marker()]),
  ];
}

class _Solids extends EditorModule {
  @override
  String get id => 'test.solids';

  @override
  String get name => 'Solids';

  @override
  List<PrefabVariant> get prefabVariants => [
    PrefabVariant(
      id: 'solid',
      name: 'Solid',
      category: 'Solid shapes',
      appliesTo: (components) => components.any((c) => c is SolidShapeSource),
      extra: () => [_Marker()],
    ),
  ];
}

/// A view from 10 m above the origin, looking down.
OrbitFlyEditorView _above() {
  final view = OrbitFlyEditorView.of(Camera(viewportSize: const Size(200, 200)))
    ..viewportSize = const Size(200, 200)
    ..pivot.setValues(0, 0, 0)
    ..distance = 10
    ..yaw = 0
    ..pitch = -math.pi / 2;
  return view..sync();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('viewport handles', () {
    late EditorScope scope;
    late Entity entity;
    late OrbitFlyEditorView view;
    late ViewportInput input;
    late HandleDragSession drags;

    TransformComponent transform() =>
        entity.getComponent<TransformComponent>()!;

    setUp(() {
      scope = testScope(modules: [_Handles()]);
      scope.sceneState.openScene(
        EditorScene(name: 'deep', mode: SceneMode.threeD),
      );
      entity = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'thing');
      scope.sceneState.selectEntity(entity);
      view = _above();
      drags = HandleDragSession(scope);
      input = ViewportInput(
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: () => view,
        designer: () => null,
        gridSize: () => 1,
        isActive: () => true,
        isAuthoring: () => true,
        handles: () => [
          for (final p in scope.viewportHandles) ...p.handlesOf(entity, scope),
        ],
        handleDrags: drags,
      )..updateCanvasSize(const Size(200, 200));
    });

    test('the scope gathers what the modules offer', () {
      // The module's, after the default 3-D kit's own.
      expect(scope.viewportHandles.whereType<_Slide>(), hasLength(1));
      expect(scope.viewportHandles.whereType<PolygonHandles>(), hasLength(1));
    });

    test('a drag of a handle goes to the module and is one undo step', () {
      final from = view.projectToScreen(Vector3.zero())!;
      final to = view.projectToScreen(Vector3(2, 0, -1))!;
      input.onPointerDown(PointerDownEvent(position: from));
      expect(drags.isDragging, isTrue);
      expect(drags.activeIndex, 0);
      input
        ..onPointerMove(PointerMoveEvent(position: Offset.lerp(from, to, 0.5)!))
        ..onPointerMove(PointerMoveEvent(position: to))
        ..onPointerUp(PointerUpEvent(position: to));
      expect(drags.isDragging, isFalse);
      expect(transform().position.x, closeTo(2, 1e-6));
      expect(transform().position.z, closeTo(-1, 1e-6));
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect([transform().position.x, transform().position.z], [0, 0]);
      scope.history.redo();
      expect(transform().position.x, closeTo(2, 1e-6));
    });

    test('Ctrl snaps to the grid', () {
      final from = view.projectToScreen(Vector3.zero())!;
      final to = view.projectToScreen(Vector3(1.3, 0, 0.6))!;
      input.onPointerDown(PointerDownEvent(position: from));
      drags.move(to, view, snap: true, grid: 1);
      input.onPointerUp(PointerUpEvent(position: to));
      expect([transform().position.x, transform().position.z], [1, 1]);
    });

    test('a click without a drag is the handle\'s click, one undo step', () {
      final at = view.projectToScreen(Vector3.zero())!;
      input
        ..onPointerDown(PointerDownEvent(position: at))
        ..onPointerUp(PointerUpEvent(position: at));
      expect(transform().position.y, -1);
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(transform().position.y, 0);
    });

    test('a press away from every handle is not taken by them', () {
      input.onPointerDown(const PointerDownEvent(position: Offset(10, 10)));
      expect(drags.isDragging, isFalse);
    });

    test('a drag whose release was lost is still its own undo step', () {
      final from = view.projectToScreen(Vector3.zero())!;
      final to = view.projectToScreen(Vector3(2, 0, 0))!;
      final handles = [
        for (final p in scope.viewportHandles) ...p.handlesOf(entity, scope),
      ];
      drags
        ..down(from, handles, view)
        ..move(Offset.lerp(from, to, 0.5)!, view)
        ..move(to, view);
      // No release: the next press finds the drag still held.
      final again = [
        for (final p in scope.viewportHandles) ...p.handlesOf(entity, scope),
      ];
      drags
        ..down(view.projectToScreen(transform().position)!, again, view)
        ..up();
      expect(scope.history.undoEntries, hasLength(2));
      scope.history.undo();
      scope.history.undo();
      expect(transform().position.x, closeTo(0, 1e-6));
    });

    test('a drag that changes nothing leaves no undo step', () {
      final at = view.projectToScreen(Vector3.zero())!;
      drags.down(at, [
        ViewportHandle(
          position: Vector3.zero(),
          component: transform(),
          onDrag: (_) {},
        ),
      ], view);
      drags.move(at + const Offset(20, 0), view);
      drags.up();
      expect(scope.history.undoEntries, isEmpty);
    });
  });

  group('prefab variants', () {
    test(
      'a variant offers each prefab it applies to again, with more to it',
      () {
        final variant = _Solids().prefabVariants.single;
        final cube = _Shapes().prefabs.first;
        expect(variant.offersFor(cube), isTrue);
        expect(variant.offersFor(_Shapes().prefabs.last), isFalse);
        final solid = variant.of(cube);
        expect(solid.id, 'solid:cube');
        expect(solid.name, 'Solid Cube');
        expect(solid.category, 'Solid shapes');
        expect(solid.namePrefix, 'cube');
        final parts = solid.buildAt!(
          SurfacePoint(Vector3(1, 2, 3), Vector3(0, -1, 0)),
        );
        expect(parts.whereType<_Solid>(), hasLength(1));
        expect(parts.whereType<_Marker>(), hasLength(1));
        expect(parts.whereType<TransformComponent>().single.position.z, 3);
      },
    );

    test('the viewport menu offers the variants after the prefabs', () {
      final plugin = JustGameEditorPlugin(
        engine: Engine(),
        modules: [_Shapes(), _Solids()],
      );
      addTearDown(plugin.dispose);
      expect(plugin.scope.prefabVariants, hasLength(1));
      final shapes = [for (final p in ShapePrefabs.all) p.id];
      expect(
        [for (final p in plugin.prefabsInSpace) p.id],
        [
          // The built-in ones that place in 3-D: sound, the default kit's
          // shapes.
          BuiltInAudioContributions.soundId,
          BuiltInAudioContributions.sound3dId,
          BuiltInAudioContributions.listenerId,
          ...shapes,
          'cube',
          'marker',
          // A variant of everything it applies to, after them all.
          for (final id in shapes) 'solid:$id',
          'solid:cube',
        ],
      );
    });
  });
}
