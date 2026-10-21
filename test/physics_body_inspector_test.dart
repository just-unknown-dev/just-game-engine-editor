// The 2-D rigid body and collider in the editor: one body type, only the
// settings that apply, layers by name from the project's file, material
// presets, Fit to visual, the collider's handles in the viewport, and the
// Problems checks.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/validation/physics_checks.dart';
import 'package:just_game_engine_editor/src/ui/inspector/physics/collider_edit_session.dart';
import 'package:just_game_engine_editor/src/ui/inspector/physics/physics_body_extras.dart';

void main() {
  late Directory root;
  late jge.World world;
  late EditorScope scope;

  setUp(() {
    root = Directory.systemTemp.createTempSync('physics_inspector');
    world = jge.World()..initialize();
    scope = testScope(world: world, scenesRoot: root.path);
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold it for a moment; it is a temp one.
    }
  });

  jge.Entity body({
    jge.CollisionShape? shape,
    jge.BodyType type = jge.BodyType.dynamic,
    List<jge.Component> more = const [],
    Offset offset = Offset.zero,
  }) {
    final collider = jge.Collider2D();
    PhysicsBodyExtras.setFrom(collider, shape ?? jge.RectangleShape(40, 20));
    collider.offset += offset;
    return world.createEntityWithComponents([
      jge.TransformComponent(position: jge.Vector3(100, 100, 0)),
      ...more,
      jge.RigidBody2D(bodyType: type),
      collider,
    ], name: 'Thing');
  }

  jge.RigidBody2D rigidOf(jge.Entity e) => e.getComponent<jge.RigidBody2D>()!;
  jge.Collider2D colliderOf(jge.Entity e) => e.getComponent<jge.Collider2D>()!;

  group('the project layer file', () {
    test('a change is written and reaches the engine', () {
      scope.physicsLayers.rename(1, 'Player');
      scope.physicsLayers.setCollision(1, 1, false);
      final file = File('${root.path}/physics.json');
      expect(file.existsSync(), isTrue);
      final saved = jge.PhysicsLayers.fromJson(
        jsonDecode(file.readAsStringSync()),
      );
      expect(saved.nameOf(1), 'Player');
      expect(saved.collides(1, 1), isFalse);
      expect(scope.context.physicsLayers, saved);

      final again = ProjectPhysicsLayers(path: file.path)..load();
      expect(again.layers.value, saved);
    });
  });

  group('the inspector', () {
    Future<void> pump(WidgetTester tester, jge.Entity e) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: SingleChildScrollView(
                child: Column(
                  children: buildComponentSections(
                    entity: e,
                    sceneState: scope.sceneState,
                    scope: scope,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows one body type, and only what applies to it', (
      tester,
    ) async {
      final e = body(type: jge.BodyType.static);
      await pump(tester, e);
      expect(find.text('Body type'), findsOneWidget);
      expect(find.text('Static'), findsNothing, reason: 'no second switch');
      expect(find.text('Mass'), findsNothing, reason: 'a static body has none');
      expect(find.text('Bounciness'), findsOneWidget);
      expect(find.text('Layer'), findsOneWidget);

      rigidOf(e).bodyType = jge.BodyType.dynamic;
      scope.sceneState.refresh();
      await pump(tester, e);
      expect(find.text('Mass'), findsOneWidget);
      expect(find.text('Linear damping'), findsOneWidget);
    });

    testWidgets('keeps rarely needed settings folded until opened', (
      tester,
    ) async {
      await pump(tester, body());
      expect(find.text('ADVANCED'), findsOneWidget);
      expect(find.text('Group'), findsNothing);
      expect(find.text('Continuous'), findsOneWidget, reason: 'with the rest of its motion, as in 3-D');
      await tester.tap(find.text('ADVANCED'));
      await tester.pump();
      expect(find.text('Group'), findsOneWidget);
    });

    testWidgets('offers the layers by the names the project gave them', (
      tester,
    ) async {
      scope.physicsLayers.rename(3, 'Enemies');
      final e = body();
      rigidOf(e).layer = 3;
      await pump(tester, e);
      expect(find.text('Enemies'), findsWidgets);
      expect(find.text('As the grid says for Enemies'), findsOneWidget);
    });

    testWidgets('a slider for bounciness, and a preset row for the material',
        (tester) async {
      await pump(tester, body());
      expect(find.byType(SliderFieldRow), findsNWidgets(2));
      expect(find.text('Preset'), findsOneWidget);
    });
  });

  test('a material preset sets grip and bounce as one undo step', () {
    final e = body();
    final b = rigidOf(e);
    final rubber = PhysicsBodyExtras.materials.firstWhere(
      (m) => m.name == 'Rubber',
    );
    PhysicsBodyExtras.applyMaterial(scope, b, rubber);
    expect((b.friction, b.restitution), (0.9, 0.6));
    scope.history.undo();
    expect((b.friction, b.restitution), (0.5, 0.0));
  });

  test('Fit to visual takes the circle drawn, as one undo step', () {
    final e = body(
      shape: jge.CircleShape(17.4),
      offset: const Offset(3, 0),
      more: [jge.CircleComponent(radius: 16.3)],
    );
    final c = colliderOf(e);
    scope.sceneState.selectEntity(e);
    expect(PhysicsBodyExtras.fitToVisual(scope, c), isTrue);
    expect(c.radius, 16.3);
    expect(c.offset, Offset.zero);
    scope.history.undo();
    expect(c.radius, 17.4);
    expect(c.offset, const Offset(3, 0));
  });

  group('editing the collider in the viewport', () {
    late EditorView view;
    late ColliderEditSession session;

    setUp(() {
      final camera = jge.Camera()..viewportSize = const Size(800, 600);
      view = GameCameraEditorView.of(camera);
      session = ColliderEditSession.of(scope);
    });

    Offset screenOf(ColliderHandle h) =>
        view.worldToScreen(session.toWorld(h.local));

    ColliderHandle handle(ColliderHandleKind kind, int index) => session
        .handles()
        .firstWhere((h) => h.kind == kind && h.index == index);

    void drag(ColliderHandle h, Offset by) {
      final from = screenOf(h);
      expect(session.onPointerDown(from, view), isTrue);
      session
        ..onPointerMove(from + by / 2, view)
        ..onPointerMove(from + by, view)
        ..onPointerUp();
    }

    test("a box's corner resizes it, the other corner staying put", () {
      final e = body();
      final c = colliderOf(e);
      session.toggle(e);
      expect(session.isEditing(e), isTrue);
      // Bottom-right, 10 right and 10 down.
      drag(handle(ColliderHandleKind.corner, 2), const Offset(10, 10));
      expect(c.shape, jge.ColliderShape2D.box);
      expect((c.size.x, c.size.y), (50, 30));
      expect(c.offset, const Offset(5, 5));
      // The whole drag is one step.
      scope.history.undo();
      expect(c.size.x, 40);
      expect(c.offset, Offset.zero);
    });

    test("the diamond moves the collider; a circle's edge sets its radius",
        () {
      final e = body(shape: jge.CircleShape(10));
      final c = colliderOf(e);
      session.toggle(e);
      drag(handle(ColliderHandleKind.center, 0), const Offset(0, 8));
      expect(c.offset, const Offset(0, 8));
      drag(handle(ColliderHandleKind.radius, 0), const Offset(6, 0));
      expect(c.radius, 16);
    });

    test('a point is added between two, and Alt-click takes one away', () {
      final e = body(
        shape: jge.PolygonShape(const [
          Offset(-10, -10),
          Offset(10, -10),
          Offset(10, 10),
          Offset(-10, 10),
        ]),
      );
      final c = colliderOf(e);
      session.toggle(e);
      drag(handle(ColliderHandleKind.insert, 0), const Offset(0, -6));
      expect(c.points, hasLength(5));
      expect(c.points[1], const Offset(0, -16));
      session.onPointerDown(
        screenOf(handle(ColliderHandleKind.vertex, 1)),
        view,
        remove: true,
      );
      expect(c.points, hasLength(4));
    });

    test('a collider matching what is drawn has nothing to edit', () {
      final e = body(more: [jge.RectangleComponent(width: 40, height: 20)]);
      colliderOf(e).shape = jge.ColliderShape2D.matchShape;
      session.toggle(e);
      expect(session.isActive, isFalse);
    });

    test('Esc, or selecting something else, ends it', () {
      final e = body();
      final other = body();
      session.toggle(e);
      expect(session.handleKey(LogicalKeyboardKey.escape), isTrue);
      expect(session.isActive, isFalse);
      session.toggle(e);
      scope.sceneState.selectEntity(other);
      expect(session.isActive, isFalse);
    });
  });

  group('Problems', () {
    List<SceneProblem> check() => [
      for (final v in PhysicsChecks.all)
        ...v(ValidationContext(scope: scope, projectRoot: root.path)),
    ];

    test('a collider bigger than the circle drawn, with Fit as the fix', () {
      final e = body(
        shape: jge.CircleShape(17.4),
        more: [jge.CircleComponent(radius: 16.3)],
      );
      scope.sceneState.selectEntity(e);
      final problems = check();
      expect(problems.single.message, contains('17.4'));
      expect([for (final f in problems.single.fixes) f.label], ['Match what is drawn', 'Fit to visual']);
      problems.single.fixes.first.apply();
      expect(colliderOf(e).shape, jge.ColliderShape2D.matchShape);
      expect(check(), isEmpty);
    });

    test('a body on an unnamed layer, and one colliding with nothing', () {
      final e = body();
      rigidOf(e)
        ..layer = 7
        ..collidesWith = 0;
      final messages = [for (final p in check()) p.message];
      expect(messages, hasLength(2));
      expect(messages.first, contains('layer 7'));
      expect(messages.last, contains('collides with no layer'));
    });

    test('a polygon with a dent', () {
      body(
        shape: jge.PolygonShape(const [
          Offset(-10, -10),
          Offset(0, 0),
          Offset(10, -10),
          Offset(10, 10),
          Offset(-10, 10),
        ]),
      );
      expect(check().single.message, contains('dents inwards'));
    });

    test('a body with no collider, and a collider matching nothing drawn', () {
      final lone = world.createEntityWithComponents([jge.TransformComponent(), jge.RigidBody2D()], name: 'Lone');
      final ghost = world.createEntityWithComponents([
        jge.TransformComponent(),
        jge.Collider2D(shape: jge.ColliderShape2D.matchShape),
      ], name: 'Ghost');
      final problems = check();
      expect(problems.map((p) => p.entity), [lone, ghost]);
      for (final p in problems) {
        p.fixes.first.apply();
      }
      expect(lone.hasComponent<jge.Collider2D>(), isTrue);
      expect(ghost.getComponent<jge.Collider2D>()!.shape, jge.ColliderShape2D.box);
    });

    test('a character that is also a body, kept a character in one step', () {
      final hero = world.createEntityWithComponents([
        jge.TransformComponent(),
        jge.CharacterBody2D(),
        jge.RigidBody2D(),
        jge.Collider2D(),
      ], name: 'Hero');
      final problem = check().single;
      expect(problem.entity, hero);
      expect(problem.message, contains('a character and a rigid body at once'));
      problem.fixes.single.apply();
      expect(hero.hasComponent<jge.RigidBody2D>(), isFalse);
      expect(hero.hasComponent<jge.Collider2D>(), isFalse);
      expect(check(), isEmpty);
      scope.history.undo();
      expect(hero.hasComponent<jge.RigidBody2D>() && hero.hasComponent<jge.Collider2D>(), isTrue);
    });

    test('a layer file the game would not ship', () {
      Directory('${root.path}/assets/project').createSync(recursive: true);
      File('${root.path}/${jge.PhysicsLayers.defaultPath}').writeAsStringSync(
        '{}',
      );
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'flutter:\n  assets:\n    - assets/scenes/\n',
      );
      expect(check().single.message, contains('not shipped'));
    });
  });
}
