// The editor's gizmos (markers, camera frames, outlines, the designer's
// aids) are kept per mode: shown while editing, hidden in the Level
// Designer and a play-test, until the Gizmos button says otherwise there,
// and each kind can be turned off within a mode. The engine's collider
// outlines go with them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/built_in_docks.dart';

/// An aid a module draws over the level: a gizmo of the default kind.
class _Aid extends DesignerOverlay {
  @override
  String get id => 'test.aid';
  @override
  String get label => 'Aid';
  @override
  IconData get icon => Icons.route;
  @override
  void paint(OverlayPaintContext context) {}
}

/// What a module's tool draws while in hand: not a gizmo.
class _Brush extends DesignerOverlay {
  @override
  GizmoKind? get gizmoKind => null;
  @override
  String get id => 'test.brush';
  @override
  String get label => 'Brush';
  @override
  IconData get icon => Icons.brush;
  @override
  void paint(OverlayPaintContext context) {}
}

void main() {
  // play() and attach need a binding, though none of these are
  // widget tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late JustGameEditorPlugin plugin;

  const defaults = GizmoSettings.defaults;

  void gizmos(GizmoSettings settings) => plugin.applyOverlaySettings(
    showGrid: true,
    gridSnappingEnabled: true,
    gridSize: 32,
    gizmos: settings,
  );

  /// [mode]'s gizmos shown or hidden; the rest as they start.
  GizmoSettings shown(GizmoMode mode, {required bool on}) => defaults
      .withMode(mode, defaults.of(mode).copyWith(shown: on));

  setUp(() async {
    engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    plugin = JustGameEditorPlugin(engine: engine);
    await plugin.attach(plugin.engine);
    plugin.setVisible(true);
    gizmos(defaults);
    plugin.sceneState.openScene(EditorScene(name: 'level'));
  });

  tearDown(() {
    plugin.closeLevelDesigner();
    plugin.dispose();
  });

  test('as they start: shown while editing, hidden in the Level Designer '
      'and in a play-test, paused too', () {
    expect(plugin.gizmoMode, GizmoMode.editor);
    expect(plugin.areGizmosVisible, isTrue);

    plugin.openLevelDesigner();
    expect(plugin.gizmoMode, GizmoMode.designer);
    expect(plugin.areGizmosVisible, isFalse);
    plugin.closeLevelDesigner();

    plugin.play();
    expect(plugin.gizmoMode, GizmoMode.play);
    expect(plugin.areGizmosVisible, isFalse);
    plugin.pause();
    expect(plugin.gizmoMode, GizmoMode.play, reason: 'still a test');
    plugin.stop();
    expect(plugin.areGizmosVisible, isTrue);

    plugin.setVisible(false);
    expect(plugin.gizmoMode, isNull, reason: 'the editor closed');
    expect(plugin.areGizmosVisible, isFalse);
  });

  test('turning one mode on or off leaves the others as they were', () {
    gizmos(shown(GizmoMode.play, on: true));
    plugin.openLevelDesigner();
    expect(plugin.gizmoMode, GizmoMode.designer);
    expect(plugin.areGizmosVisible, isFalse, reason: 'its own still');
    plugin.closeLevelDesigner();
    expect(plugin.areGizmosVisible, isTrue, reason: 'the editor');
    plugin.play();
    expect(plugin.areGizmosVisible, isTrue, reason: 'asked for');
    plugin.stop();
    // After a play-test the designer is heard opening again: a Computed
    // here once kept what the play-test read and missed it.
    expect(plugin.areGizmosVisible, isTrue, reason: 'the editor');
    plugin.openLevelDesigner();
    expect(plugin.areGizmosVisible, isFalse, reason: 'the designer again');
    plugin.closeLevelDesigner();

    gizmos(shown(GizmoMode.editor, on: false));
    expect(plugin.areGizmosVisible, isFalse);
    plugin.play();
    expect(plugin.areGizmosVisible, isFalse, reason: 'as it starts');
  });

  test('a kind turned off in a mode is left out there only', () {
    final noColliders = defaults.withMode(
      GizmoMode.editor,
      defaults.editor.withKind(GizmoKind.colliders, on: false),
    );
    gizmos(
      noColliders.withMode(GizmoMode.play, defaults.play.copyWith(shown: true)),
    );
    expect(plugin.showsGizmo(GizmoKind.colliders), isFalse);
    expect(plugin.showsGizmo(GizmoKind.icons), isTrue);
    plugin.play();
    expect(plugin.showsGizmo(GizmoKind.colliders), isTrue);
  });

  test("the command switches the mode now's gizmos, and only those", () {
    BuiltInDocks.runCommand(plugin, 'editor.gizmos.toggle');
    var settings = plugin.scope.prefs.settings.value.gizmos;
    expect(settings.editor.shown, isFalse);
    expect(settings.designer, defaults.designer);
    expect(settings.play, defaults.play);

    plugin.openLevelDesigner();
    BuiltInDocks.runCommand(plugin, 'editor.gizmos.toggle');
    settings = plugin.scope.prefs.settings.value.gizmos;
    expect(settings.designer.shown, isTrue);
    expect(settings.editor.shown, isFalse, reason: 'left as it was');
  });

  group("the engine's collider outlines", () {
    PhysicsSystem physics() => engine.world.getSystem<PhysicsSystem>()!;
    void tick() => plugin.update(1 / 60);

    // A bare engine has none: a game adds it, or asks for the defaults.
    setUp(() => engine.world.addSystem(PhysicsSystem(engine.physics)));

    test('a game is drawn without them unless it asks', () {
      expect(PhysicsSystem(engine.physics).drawsOutlines, isFalse);
    });

    test('drawn while the mode shows colliders: editing as it starts; a '
        'play-test or the Level Designer once asked', () {
      tick();
      expect(physics().drawsOutlines, isTrue);

      plugin.play();
      tick();
      expect(physics().drawsOutlines, isFalse, reason: 'a play-test');
      gizmos(shown(GizmoMode.play, on: true));
      tick();
      expect(physics().drawsOutlines, isTrue, reason: 'asked for');
      plugin.stop();
      gizmos(defaults);

      plugin.openLevelDesigner();
      tick();
      expect(physics().drawsOutlines, isFalse, reason: 'the designer');
      gizmos(shown(GizmoMode.designer, on: true));
      tick();
      expect(physics().drawsOutlines, isTrue);
      plugin.closeLevelDesigner();

      gizmos(
        defaults.withMode(
          GizmoMode.editor,
          defaults.editor.withKind(GizmoKind.colliders, on: false),
        ),
      );
      tick();
      expect(physics().drawsOutlines, isFalse, reason: 'that kind off');

      gizmos(defaults);
      plugin.setVisible(false);
      tick();
      expect(physics().drawsOutlines, isFalse, reason: 'the editor closed');
    });

    test('not for what the eye hid; in the Level Designer, once asked for, '
        'for what is off its Level Map too', () {
      final solid = engine.world.createEntityWithComponents([
        TransformComponent(),
        Collider2D(),
      ], name: 'solid');
      tick();
      expect(physics().outlineFilter!(solid), isTrue);
      plugin.scope.view.setHidden([solid.id], hidden: true);
      expect(physics().outlineFilter!(solid), isFalse);
      plugin.scope.view.setHidden([solid.id], hidden: false);

      // Off the Level Map: out of reach and out of sight while designing,
      // yet its outline is what the designer's Gizmos button brings back.
      gizmos(shown(GizmoMode.designer, on: true));
      plugin.openLevelDesigner();
      tick();
      expect(plugin.keepsToLevelMap.value, isTrue);
      expect(plugin.designer.value!.controller.isShownInViewport(solid), isFalse);
      expect(physics().drawsOutlines, isTrue);
      expect(physics().outlineFilter!(solid), isTrue);
      plugin.scope.view.setHidden([solid.id], hidden: true);
      expect(physics().outlineFilter!(solid), isFalse, reason: 'the eye');
    });
  });

  group('the Level Designer', () {
    late LevelDesignerSession session;

    setUp(() {
      plugin.openLevelDesigner();
      session = plugin.designer.value!;
    });

    test("a gizmo is drawn, and offered the pointer, only while its mode "
        "and kind are shown; a tool's overlay always", () {
      final aid = _Aid(), brush = _Brush();
      expect(session.isOverlayDrawn(aid), isFalse, reason: 'as it starts');
      expect(session.isOverlayDrawn(brush), isTrue);

      gizmos(shown(GizmoMode.designer, on: true));
      expect(session.isOverlayDrawn(aid), isTrue);

      gizmos(
        defaults.withMode(
          GizmoMode.designer,
          const GizmoModeSettings(shown: true, hidden: {GizmoKind.aids}),
        ),
      );
      expect(session.isOverlayDrawn(aid), isFalse, reason: 'its kind off');
      expect(session.isOverlayDrawn(brush), isTrue);
    });

    test('its rulers, guides, drag box and handles are not gizmos; its '
        'outlines and camera frames are', () {
      final byId = {for (final o in session.overlays.all) o.id: o};
      for (final id in ['rulers', 'guides', 'drag_rect', 'selectionHandles']) {
        expect(byId.containsKey(id), isTrue, reason: id);
        expect(byId[id]!.gizmoKind, isNull, reason: id);
      }
      expect(byId['selection']?.gizmoKind, GizmoKind.selection);
      expect(byId['camera.rigs']?.gizmoKind, GizmoKind.cameras);
    });
  });
}
