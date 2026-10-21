// A settings slider mid-drag: a limit that drops what is past it is not
// tried out on the way, and a look that is tried out leaves the game's own
// widgets alone.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_controls.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';

import 'support/memory_settings_store.dart';
import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

/// Counts its builds.
class _Game extends StatelessWidget {
  const _Game(this.builds);

  final List<int> builds;

  @override
  Widget build(BuildContext context) {
    builds.add(1);
    return const SizedBox.expand();
  }
}

void main() {
  testWidgets('dragging Undo steps down and back up keeps every step', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = testScope();
    for (var i = 0; i < 150; i++) {
      scope.history.push(
        CallbackCommand(label: 'step $i', onRedo: () {}, onUndo: () {}),
      );
    }
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
    await tester.tap(find.text('Editing').first);
    await tester.pumpAndSettle();
    final slider = find.descendant(
      of: find.ancestor(
        of: find.text('Undo steps'),
        matching: find.byType(SettingRow),
      ),
      matching: find.byType(Slider),
    );
    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(box.center);
    for (final x in [box.left + 4, box.left, box.right - 2, box.right]) {
      await gesture.moveTo(Offset(x, box.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(scope.history.undoEntries, hasLength(150), reason: 'mid-drag');
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.undoLimit, greaterThan(150));
    expect(scope.history.undoEntries, hasLength(150));
  });

  testWidgets("a new look builds the editor again, not the game's widgets", (
    tester,
  ) async {
    if (!kDebugMode) return;
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    final scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      settingsStore: MemorySettingsStore(),
    );
    final plugin = JustGameEditorPlugin(engine: engine, scope: scope);
    await tester.runAsync(() => plugin.attach(plugin.engine));
    final builds = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JustGameEditorOverlay(plugin: plugin, gameChild: _Game(builds)),
        ),
      ),
    );
    await tester.pump();
    builds.clear();

    final s = scope.prefs.settings.value;
    scope.prefs.settings.value = s.copyWith(highContrast: !s.highContrast);
    await tester.pump();
    expect(builds, isEmpty);

    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    scope.dispose();
  });
}
