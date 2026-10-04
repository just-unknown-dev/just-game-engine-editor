// Accessibility: each setting does what its row says, in the palette, the
// sizes and timings, and the chrome itself.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_controls.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';

import 'support/test_scope.dart';

double _luminance(Color c) => c.computeLuminance();

void main() {
  const defaults = OverlayUiSettings.defaults();
  tearDown(() {
    EditorMetrics.apply(defaults);
    EditorTheme.apply(EditorThemeData.classic);
  });

  group('the palette', () {
    test('high contrast brightens what was quiet, and keeps the accent', () {
      const classic = EditorThemeData.classic;
      final high = classic.highContrast();
      expect(
        _luminance(high.textMuted),
        greaterThan(_luminance(classic.textMuted)),
      );
      expect(
        _luminance(high.textSecondary),
        greaterThan(_luminance(classic.textSecondary)),
      );
      expect(high.border.a, greaterThan(classic.border.a));
      expect(high.primary, classic.primary);
    });

    test('colour-blind safe status colours do not set red against green', () {
      final safe = EditorThemeData.classic.colourBlindSafe();
      expect(safe.success, isNot(EditorThemeData.classic.success));
      // Sky blue: more blue than green, and nothing like red.
      expect(safe.success.b, greaterThan(safe.success.g));
      expect(safe.success.r, lessThan(0.5));
    });
  });

  group('sizes and timings', () {
    test('bigger targets are 32 px, and what is built on them grows', () {
      expect(EditorMetrics.minTarget, 24);
      EditorMetrics.apply(defaults.copyWith(largeTargets: true));
      expect(EditorMetrics.minTarget, 32);
      expect(EditorMetrics.controlSm, greaterThanOrEqualTo(32));
      expect(EditorToolbar.height, greaterThan(32));
      expect(OverlayLayout.compactDockPanelHeight, greaterThan(26));
    });

    test('reduced motion is no motion', () {
      expect(EditorMetrics.motionMedium, isNot(Duration.zero));
      EditorMetrics.apply(defaults.copyWith(reduceMotion: true));
      expect(EditorMetrics.motionFast, Duration.zero);
      expect(EditorMetrics.motionMedium, Duration.zero);
      expect(EditorMetrics.motionSlow, Duration.zero);
    });

    test('longer timings: tooltips sooner and longer, messages longer', () {
      final wait = EditorMetrics.tooltipWait;
      EditorMetrics.apply(defaults.copyWith(longerTimings: true));
      expect(EditorMetrics.tooltipWait, lessThan(wait));
      expect(EditorMetrics.tooltipLinger, greaterThan(wait));
      expect(EditorMetrics.messageTimeScale, greaterThan(1));
    });

    testWidgets('a message stays longer with longer timings', (tester) async {
      EditorMetrics.apply(defaults.copyWith(longerTimings: true));
      final c = EditorSnackBarController();
      addTearDown(c.dispose);
      c.showSnackBar(
        const EditorSnackBarEntry(
          message: 'hi',
          duration: Duration(seconds: 2),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(c.visible, hasLength(1), reason: 'still there after 3 s');
      await tester.pump(const Duration(seconds: 3));
      expect(c.visible, isEmpty);
    });
  });

  group('the settings', () {
    late EditorScope scope;
    setUp(() => scope = testScope());

    Future<void> pumpDialog(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: EditorSettingsDialog(scope: scope, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an Accessibility page, with text size moved onto it', (
      tester,
    ) async {
      await pumpDialog(tester);
      // Appearance, open first: no text size there now.
      expect(find.text('Text size'), findsNothing);

      await tester.tap(find.text('Accessibility').first);
      await tester.pumpAndSettle();
      for (final row in [
        'Text size',
        'Bolder text',
        'High contrast',
        'Colour-blind safe colours',
        'Reduce motion',
        'Longer timings',
        'Bigger targets',
        'Always-visible focus',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      for (final heading in ['READING', 'SEEING', 'MOVING']) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
    });

    testWidgets('a switch there saves', (tester) async {
      await pumpDialog(tester);
      await tester.tap(find.text('Accessibility').first);
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Reduce motion'),
        matching: find.byType(SettingRow),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(EditorToggle)),
      );
      await tester.pumpAndSettle();
      expect(scope.prefs.settings.value.reduceMotion, isTrue);
    });
  });

  group('in the editor', () {
    late JustGameEditorPlugin plugin;

    Future<void> start(WidgetTester tester) async {
      final engine = Engine();
      addTearDown(engine.dispose);
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
      await tester.pump();
    }

    Future<void> stop(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
    }

    void set(OverlayUiSettings Function(OverlayUiSettings s) change) =>
        unawaited(
          plugin.scope.prefs.update(change(plugin.scope.prefs.settings.value)),
        );

    testWidgets('high contrast and colour-blind colours are the palette', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      final muted = EditorTheme.textMuted;
      set((s) => s.copyWith(highContrast: true, colourBlindSafe: true));
      await tester.pump();
      expect(_luminance(EditorTheme.textMuted), greaterThan(_luminance(muted)));
      expect(EditorTheme.success, const Color(0xFF56B4E9));
      set((s) => s.copyWith(highContrast: false, colourBlindSafe: false));
      await tester.pump();
      expect(EditorTheme.textMuted, muted, reason: 'back as it was');
      await stop(tester);
    });

    testWidgets('bolder text reaches the chrome, and not the game', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      set((s) => s.copyWith(boldText: true));
      await tester.pump();
      final chrome = tester.element(find.text('Just Runtime Editor'));
      expect(MediaQuery.boldTextOf(chrome), isTrue);
      await stop(tester);
    });

    testWidgets('always-visible focus outlines what has the keyboard', (
      tester,
    ) async {
      EditorMetrics.apply(defaults.copyWith(alwaysShowFocus: true));
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: EditorChip(label: 'Errors', selected: false, onTap: () {}),
          ),
        ),
      );
      Border? ring() {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(FocusOutline),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).border as Border?;
      }

      expect(ring(), isNull);
      // Focus the chip the way a click would — no keyboard involved. Asked
      // from inside it: the node is the chip's own.
      Focus.of(tester.element(find.text('Errors'))).requestFocus();
      await tester.pump();
      expect(ring(), isNotNull);
    });
  });
}
