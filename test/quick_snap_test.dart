// Snapping at hand: a magnet and a grid button standing on the settings
// gear while editing — and one snap switch for the whole editor, the Level
// Designer's included.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/quick_snap_bar.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart';

import 'support/test_scope.dart';

void main() {
  const defaults = OverlayUiSettings.defaults();

  group('in the editor', () {
    late JustGameEditorPlugin plugin;

    Future<void> start(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Engine.resetInstance();
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(plugin.onInitialize);
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
      plugin.sceneState.openScene(Scene(name: 'level'), const {});
      await tester.pump();
    }

    Future<void> stop(WidgetTester tester) async {
      plugin.playController.stop();
      plugin.closeLevelDesigner();
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
      Engine.resetInstance();
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
      expect(
        bar.height,
        closeTo(QuickSnapBar.heightFor(plugin.scope.prefs.settings.value), 1),
      );
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
      expect(find.text('Move step'), findsOneWidget);
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
      // Level with the magnet, at the top of the column.
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
      expect(find.text('Grid size'), findsOneWidget);
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
      expect(find.text('Move step'), findsOneWidget);
      expect(find.text('Grid size'), findsNothing);
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

    testWidgets('gone in a play-test, back after it', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      plugin.play();
      await tester.pump();
      expect(find.byType(QuickSnapBar), findsNothing);
      plugin.pause();
      await tester.pump();
      expect(find.byType(QuickSnapBar), findsNothing, reason: 'still one');
      plugin.stop();
      await tester.pump();
      expect(find.byType(QuickSnapBar), findsOneWidget);
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
