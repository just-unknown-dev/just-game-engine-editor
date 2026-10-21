// The right panel: a drag of its edge does not build the inspector again,
// a save that fails says so, and opening another scene asks about the
// unsaved changes first.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/memory_settings_store.dart';
import 'support/real_io.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';
import 'package:just_game_engine_editor/src/ui/panels/entity_inspector_panel.dart';

void main() {
  late Directory root;
  late EditorScope scope;
  late JustGameEditorPlugin plugin;

  setUp(() {
    root = Directory.systemTemp.createTempSync('right_panel_');
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> start(WidgetTester tester, {required String scenesRoot}) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      scenesRoot: scenesRoot,
      settingsStore: MemorySettingsStore(),
    );
    plugin = JustGameEditorPlugin(engine: engine, scope: scope);
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
    await tester.pump();
  }

  Future<void> stop(WidgetTester tester) async {
    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    scope.dispose();
  }

  testWidgets("dragging the panel's edge leaves the inspector as it was", (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester, scenesRoot: root.path);
    plugin.sceneState.openScene(EditorScene(name: 'level'));
    await tester.pumpAndSettle();
    final before = tester.widget(find.byType(EntityInspectorPanel));
    scope.chrome.rightPanelWidth.value += 24;
    await tester.pump();
    scope.chrome.rightPanelWidth.value += 24;
    await tester.pump();
    expect(
      identical(tester.widget(find.byType(EntityInspectorPanel)), before),
      isTrue,
      reason: 'not built again for the new width',
    );
    await stop(tester);
  });

  testWidgets('Save says when the scene could not be saved', (tester) async {
    if (!kDebugMode) return;
    // Where the scenes folder should be, a file: nothing can be written.
    final blocked = File('${root.path}/scenes')..writeAsStringSync('');
    await start(tester, scenesRoot: blocked.path);
    plugin.sceneState
      ..openScene(EditorScene(name: 'level'))
      ..markDirty();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    // The save is real file I/O, refused by the disk: said once it is.
    await pumpUntil(
      tester,
      () => find.text('Could not save level').evaluate().isNotEmpty,
      what: 'the failed save to be said',
    );
    expect(find.text('Could not save level'), findsOneWidget);
    expect(plugin.sceneState.isDirty.value, isTrue);
    await tester.pump(const Duration(seconds: 10));
    await stop(tester);
  });

  testWidgets('opening another scene with unsaved changes asks first', (
    tester,
  ) async {
    if (!kDebugMode) return;
    final store = SceneStore(
      root: root.path,
      codec: SceneCodec(ComponentDefinitionRegistry.core()),
    );
    await tester.runAsync(() async {
      await store.writeInitialFiles('level_01');
      await store.writeInitialFiles('level_02');
    });
    await start(tester, scenesRoot: root.path);
    plugin.sceneState
      ..openScene(EditorScene(name: 'level_01'))
      ..markDirty();
    await tester.pumpAndSettle();

    final opening = plugin.openScene('level_02');
    await tester.pumpAndSettle();
    expect(find.text('Save changes to level_01?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => opening);
    expect(plugin.sceneState.activeScene.value?.name, 'level_01');
    expect(plugin.sceneState.isDirty.value, isTrue);
    await stop(tester);
  });
}
