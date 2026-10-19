// Snapping at hand: the gizmos, a magnet and a grid button standing on the settings
// gear while editing — and one snap switch for the whole editor, the Level
// Designer's included.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/gizmo_menu.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/quick_snap_bar.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/panels/tool_palette.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

void main() {
  const defaults = OverlayUiSettings.defaults();

  group('in the editor', () {
    late JustGameEditorPlugin plugin;

    Future<void> start(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(() => plugin.attach(plugin.engine));
      plugin.setVisible(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JustGameEditorOverlay(
              plugin: plugin,
              gameChild: const SizedBox.expand(),
            ),
          ),
        ),
      );
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      await tester.pump();
    }

    Future<void> stop(WidgetTester tester) async {
      plugin.playController.stop();
      plugin.closeLevelDesigner();
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
    }

    Finder inBar(Finder f) =>
        find.descendant(of: find.byType(QuickSnapBar), matching: f);

    testWidgets('the bar stands on the gear', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      final bar = tester.getRect(find.byType(QuickSnapBar));
      final gear = tester.getRect(find.byTooltip('Editor settings  (Ctrl+,)'));
      expect(bar.bottom, lessThanOrEqualTo(gear.top), reason: 'above it');
      expect((bar.right - gear.right).abs(), lessThan(12), reason: 'aligned');
      // What the chrome keeps clear of it is how tall it is.
      expect(bar.height, closeTo(QuickSnapBar.heightFor(), 1));
      await stop(tester);
    });

    testWidgets('the column down the right is one width, to the gear', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      Rect frameOf(Finder of) => tester.getRect(
        find.ancestor(of: of, matching: find.byType(FloatingToolFrame)).first,
      );
      final transform = tester.getRect(
        find
            .descendant(
              of: find.byType(TransformToolbar),
              matching: find.byType(FloatingToolFrame),
            )
            .first,
      );
      final snap = frameOf(inBar(find.byType(MagnetGlyph)));
      final gear = frameOf(find.byTooltip('Editor settings  (Ctrl+,)'));

      for (final frame in [snap, gear]) {
        expect(frame.width, transform.width);
        expect(frame.right, transform.right);
      }
      // The strip's own buttons, the same size.
      expect(
        tester.getSize(find.byTooltip('Editor settings  (Ctrl+,)')).height,
        ToolStripButton.buttonHeight,
      );
      expect(gear.top - snap.bottom, 8, reason: 'the gap between frames');
      await stop(tester);
    });

    testWidgets('the magnet switches snapping; the grid button the grid', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      await tester.tap(inBar(find.byType(MagnetGlyph)));
      await tester.pump();
      await tester.pump();
      expect(plugin.scope.prefs.settings.value.gridSnappingEnabled, isFalse);
      expect(plugin.sceneState.gridSnappingEnabled.value, isFalse);
      expect(
        find.byTooltip(
          'Snapping is off — moves in grid cells. Right-click for the step.',
        ),
        findsOneWidget,
      );

      await tester.tap(inBar(find.byIcon(Icons.grid_on_rounded)));
      await tester.pump();
      await tester.pump();
      expect(plugin.scope.prefs.settings.value.showGrid, isFalse);
      expect(plugin.showGrid.value, isFalse);
      expect(inBar(find.byIcon(Icons.grid_off_rounded)), findsOneWidget);
      await stop(tester);
    });

    Finder gizmoButton() =>
        inBar(find.byIcon(Icons.filter_center_focus_rounded));

    testWidgets("the top button, over the magnet, hides and shows the "
        "mode's gizmos, and only that mode's", (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      expect(
        tester.getRect(gizmoButton()).bottom,
        lessThanOrEqualTo(tester.getRect(inBar(find.byType(MagnetGlyph))).top),
        reason: 'on top of the snapping',
      );
      expect(plugin.areGizmosVisible, isTrue, reason: 'the editor: shown');

      await tester.tap(gizmoButton());
      await tester.pump();
      await tester.pump();
      final gizmos = plugin.scope.prefs.settings.value.gizmos;
      expect(gizmos.editor.shown, isFalse);
      expect(gizmos.designer, GizmoSettings.defaults.designer);
      expect(gizmos.play, GizmoSettings.defaults.play);
      expect(plugin.areGizmosVisible, isFalse);
      expect(
        find.byTooltip(
          'Editor gizmos are hidden — markers, camera frames, colliders, '
          'outlines. Right-click for which.',
        ),
        findsOneWidget,
      );

      // The Level Designer's own: hidden as it starts, shown when asked.
      plugin.openLevelDesigner();
      await tester.pump();
      expect(plugin.areGizmosVisible, isFalse);
      await tester.tap(gizmoButton());
      await tester.pump();
      await tester.pump();
      expect(plugin.areGizmosVisible, isTrue);
      expect(
        plugin.scope.prefs.settings.value.gizmos.editor.shown,
        isFalse,
        reason: 'the editor keeps its own',
      );
      await stop(tester);
    });

    testWidgets('in the Level Designer the button brings back the collider '
        'outlines of what is off the Level Map', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      final physics = PhysicsSystem(plugin.engine.physics);
      plugin.engine.world.addSystem(physics);
      final solid = plugin.engine.world.createEntityWithComponents([
        TransformComponent(),
        RigidBody2D(),
        Collider2D(),
      ], name: 'Floor_solid');
      plugin.openLevelDesigner();
      await tester.pump();
      plugin.update(1 / 60);
      expect(physics.drawsOutlines, isFalse, reason: 'hidden as it starts');

      await tester.tap(gizmoButton());
      await tester.pump();
      await tester.pump();
      plugin.update(1 / 60);
      expect(plugin.gizmoMode, GizmoMode.designer);
      expect(physics.drawsOutlines, isTrue);
      expect(physics.outlineFilter!(solid), isTrue, reason: 'off the map');

      await tester.tap(gizmoButton());
      await tester.pump();
      await tester.pump();
      plugin.update(1 / 60);
      expect(physics.drawsOutlines, isFalse);
      await stop(tester);
    });

    testWidgets('a right-click on it slides out the kinds, for the mode now', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      await tester.tap(gizmoButton(), buttons: kSecondaryButton);
      await tester.pump();
      expect(find.byType(GizmoMenu), findsOneWidget);
      expect(find.text('· Editor'), findsOneWidget);
      final menu = tester.getRect(find.byType(GizmoMenu));
      final bar = tester.getRect(
        find
            .descendant(
              of: find.byType(QuickSnapBar),
              matching: find.byType(FloatingToolFrame),
            )
            .last,
      );
      expect(menu.right, lessThanOrEqualTo(bar.left), reason: 'to its left');

      // Colliders off: in the editor only, and counted on the button.
      await tester.tap(find.text('Colliders'));
      await tester.pump();
      await tester.pump();
      var gizmos = plugin.scope.prefs.settings.value.gizmos;
      expect(gizmos.editor.hidden, {GizmoKind.colliders});
      expect(gizmos.play.hidden, isEmpty);
      expect(plugin.showsGizmo(GizmoKind.colliders), isFalse);
      expect(plugin.showsGizmo(GizmoKind.icons), isTrue);
      expect(
        inBar(find.text('${GizmoKind.values.length - 1}')),
        findsOneWidget,
      );

      // The same in every mode, then this mode back as it starts.
      await tester.tap(find.text('Every mode'));
      await tester.pump();
      await tester.pump();
      gizmos = plugin.scope.prefs.settings.value.gizmos;
      expect(gizmos.designer, gizmos.editor);
      expect(gizmos.play, gizmos.editor);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      await tester.pump();
      gizmos = plugin.scope.prefs.settings.value.gizmos;
      expect(gizmos.editor, GizmoSettings.defaults.editor);
      expect(gizmos.play.hidden, {GizmoKind.colliders}, reason: 'its own');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(GizmoMenu), findsNothing);
      await stop(tester);
    });

    testWidgets('a right-click on the magnet slides out the steps', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.scope.prefs.settings.value = defaults.copyWith(
        gridSnappingEnabled: false,
      );
      await tester.pump();
      final magnet = inBar(find.byType(MagnetGlyph));
      await tester.tap(magnet, buttons: kSecondaryButton);
      await tester.pump();
      expect(find.byType(QuickValueRow), findsOneWidget);
      expect(find.text('Step'), findsOneWidget);
      final row = tester.getRect(find.byType(QuickValueRow));
      final bar = tester.getRect(
        find
            .descendant(
              of: find.byType(QuickSnapBar),
              matching: find.byType(FloatingToolFrame),
            )
            .last,
      );
      expect(row.right, lessThanOrEqualTo(bar.left), reason: 'to its left');
      // Level with the magnet, in the middle of the column.
      final at = tester.getRect(magnet);
      expect((row.center.dy - at.center.dy).abs(), lessThan(4));

      await tester.tap(find.text('8'));
      await tester.pump();
      await tester.pump();
      final settings = plugin.scope.prefs.settings.value;
      expect(settings.moveStep, 8);
      expect(settings.gridSnappingEnabled, isTrue, reason: 'asked for one');
      expect(plugin.scope.sceneState.moveStep, 8);
      expect(find.byType(QuickValueRow), findsNothing, reason: 'put away');
      // The step shows on the magnet.
      expect(inBar(find.text('8')), findsOneWidget);

      // A click elsewhere puts it away too; so does Esc.
      await tester.tap(magnet, buttons: kSecondaryButton);
      await tester.pump();
      await tester.tapAt(const Offset(300, 300));
      await tester.pump();
      expect(find.byType(QuickValueRow), findsNothing);
      await tester.tap(magnet, buttons: kSecondaryButton);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(QuickValueRow), findsNothing);
      await stop(tester);
    });

    testWidgets('in a 3-D scene the steps are the 3-D move step, in metres', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.sceneState.openScene(
        EditorScene(name: 'space', mode: SceneMode.threeD),
      );
      plugin.scope.prefs.settings.value = defaults.copyWith(
        moveStep: 4,
        moveStep3D: 0.5,
      );
      await tester.pump();
      final magnet = inBar(find.byType(MagnetGlyph));
      expect(inBar(find.text('0.5')), findsWidgets, reason: 'the 3-D step');
      expect(inBar(find.text('4')), findsNothing, reason: "not the plane's");
      await tester.tap(magnet, buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Step'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(QuickValueRow),
          matching: find.text('2'),
        ),
      );
      await tester.pump();
      await tester.pump();
      final settings = plugin.scope.prefs.settings.value;
      expect(settings.moveStep3D, 2);
      expect(settings.moveStep, 4, reason: 'the 2-D step left alone');
      expect(plugin.scope.sceneState.moveStep3D, 2);
      await stop(tester);
    });

    testWidgets('a right-click on the grid slides out its sizes', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.scope.prefs.settings.value = defaults.copyWith(showGrid: false);
      await tester.pump();
      final button = inBar(find.byIcon(Icons.grid_off_rounded));
      expect(inBar(find.text('32')), findsOneWidget, reason: 'its size');
      await tester.tap(button, buttons: kSecondaryButton);
      await tester.pump();
      expect(find.text('Grid Size'), findsOneWidget);
      // Level with the grid button, at the foot of the column.
      final row = tester.getRect(find.byType(QuickValueRow));
      final at = tester.getRect(button);
      expect((row.center.dy - at.center.dy).abs(), lessThan(4));

      // The magnet's row takes its place.
      await tester.tap(
        inBar(find.byType(MagnetGlyph)),
        buttons: kSecondaryButton,
      );
      await tester.pump();
      expect(find.text('Step'), findsOneWidget);
      expect(find.text('Grid Size'), findsNothing);
      await tester.tap(button, buttons: kSecondaryButton);
      await tester.pump();

      await tester.tap(find.text('64'));
      await tester.pump();
      await tester.pump();
      final settings = plugin.scope.prefs.settings.value;
      expect(settings.gridSize, 64);
      expect(settings.showGrid, isTrue, reason: 'asked for one');
      expect(plugin.gridSize.value, 64);
      expect(find.byType(QuickValueRow), findsNothing, reason: 'put away');
      expect(inBar(find.text('64')), findsOneWidget);
      await stop(tester);
    });

    testWidgets("in a play-test only the gizmos stay, the play-test's own; "
        'snapping is back after it', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.play();
      await tester.pump();
      expect(find.byType(QuickSnapBar), findsOneWidget);
      expect(inBar(find.byType(MagnetGlyph)), findsNothing);
      expect(gizmoButton(), findsOneWidget);
      expect(
        tester.getSize(find.byType(QuickSnapBar)).height,
        closeTo(QuickSnapBar.heightFor(snapping: false), 1),
      );
      expect(plugin.areGizmosVisible, isFalse, reason: 'as it starts');
      await tester.tap(gizmoButton());
      await tester.pump();
      await tester.pump();
      expect(plugin.areGizmosVisible, isTrue);
      expect(plugin.scope.prefs.settings.value.gizmos.play.shown, isTrue);
      plugin.pause();
      await tester.pump();
      expect(inBar(find.byType(MagnetGlyph)), findsNothing, reason: 'still');
      plugin.stop();
      await tester.pump();
      expect(inBar(find.byType(MagnetGlyph)), findsOneWidget);
      expect(plugin.areGizmosVisible, isTrue, reason: "the editor's own");
      await stop(tester);
    });

    testWidgets('the designer\'s Snap and Smart are the same switches', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.scope.prefs.settings.value = defaults.copyWith(
        gridSnappingEnabled: false,
        smartSnap: false,
      );
      plugin.openLevelDesigner();
      await tester.pump();
      final session = plugin.designer.value!;
      expect(session.controller.snapEnabled.value, isFalse, reason: 'opened');
      expect(session.controller.smartSnap.value, isFalse);

      // The magnet reaches the designer...
      await tester.tap(inBar(find.byType(MagnetGlyph)));
      await tester.pump();
      expect(session.controller.snapEnabled.value, isTrue);

      // ...and the designer's own chips reach the settings.
      session.setSnapping(false);
      session.setSmartSnap(true);
      await tester.pump();
      final settings = plugin.scope.prefs.settings.value;
      expect(settings.gridSnappingEnabled, isFalse);
      expect(settings.smartSnap, isTrue);
      expect(
        find.byTooltip(
          'Snapping is off — moves in grid cells. Right-click for the step.',
        ),
        findsOneWidget,
      );
      await stop(tester);
    });
  });

  test('the bar\'s commands switch the same settings, with no keys', () {
    final scope = testScope();
    CommandContext context() =>
        CommandContext(scope: scope, modifiers: const ModifierKeys());
    scope.commands.byId(QuickSnapBar.snapCommandId)!.run(context());
    scope.commands.byId(QuickSnapBar.gridCommandId)!.run(context());
    expect(scope.prefs.settings.value.gridSnappingEnabled, isFalse);
    expect(scope.prefs.settings.value.showGrid, isFalse);
    expect(scope.commands.bindingsFor(QuickSnapBar.snapCommandId), isEmpty);
    expect(scope.commands.bindingsFor(QuickSnapBar.gridCommandId), isEmpty);
  });
}
