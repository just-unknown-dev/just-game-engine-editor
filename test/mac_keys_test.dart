// The editor's shortcuts follow the platform: Cmd on macOS, Ctrl on
// Windows and Linux. On a Mac Cmd+Z undoes (it used to run the plain-Z
// command, a quarter turn), Cmd+S saves, Cmd+D duplicates, Backspace — the
// Mac's delete key — deletes, and the tooltips say Cmd. Ctrl there is not a
// shortcut key at all. Everywhere else it is Ctrl, as before.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

void main() {
  late JustGameEditorPlugin plugin;
  late FocusNode field;
  final desktops = TargetPlatformVariant(const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  bool isMac() => defaultTargetPlatform == TargetPlatform.macOS;

  /// The key the editor's shortcuts are made with on this platform.
  LogicalKeyboardKey primary() =>
      isMac() ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

  Future<void> start(WidgetTester tester) async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    plugin = JustGameEditorPlugin(engine: engine);
    await tester.runAsync(() => plugin.attach(plugin.engine));
    plugin
      ..setVisible(true)
      ..sceneState.openScene(EditorScene(name: 'level'));
    field = FocusNode(debugLabel: 'a field in the game');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JustGameEditorOverlay(
            plugin: plugin,
            gameChild: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 120, child: TextField(focusNode: field)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> stop(WidgetTester tester) async {
    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    field.dispose();
    plugin.dispose();
  }

  Entity block(String name) {
    final entity = plugin.engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
      RectangleComponent(width: 64, height: 32),
    ], name: name);
    plugin.sceneState.selectEntity(entity);
    return entity;
  }

  /// A crate on the Level Map, selected, with the Level Designer open: the
  /// designer reaches only what is on the map.
  Future<Entity> designerBlock(WidgetTester tester) async {
    final world = plugin.engine.world;
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: LevelMapData()),
    ], name: LevelMaps.primaryName);
    final crate = world.createEntityWithComponents([
      TransformComponent(position: Vector3(0, 0, 0)),
      RectangleComponent(width: 64, height: 32),
    ], name: 'Crate');
    placeEntity(
      crate,
      world: world,
      sceneState: plugin.sceneState,
      slot: HierarchySlot(parentId: map.id, index: -1),
    );
    plugin.openLevelDesigner();
    await tester.pump();
    plugin.sceneState.selectEntity(crate);
    return crate;
  }

  int entityCount() => plugin.engine.world.entities.length;

  double angleOf(Entity e) => e.getComponent<TransformComponent>()!.angle;

  /// [key] with [held] down around it.
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey held,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(held);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(held);
    await tester.pump();
  }

  testWidgets('the primary modifier undoes, duplicates and saves', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    var saves = 0;
    plugin.scope.commands.register(
      DesignerCommand(
        id: 'editor.save',
        label: 'Save scene',
        scope: CommandScope.always,
        run: (_) => saves++,
      ),
      override: true,
    );
    block('Crate');
    final before = entityCount();

    await chord(tester, primary(), LogicalKeyboardKey.keyD);
    expect(entityCount(), before + 1, reason: 'duplicated');

    await chord(tester, primary(), LogicalKeyboardKey.keyZ);
    expect(entityCount(), before, reason: 'the duplicate undone');

    await chord(tester, primary(), LogicalKeyboardKey.keyS);
    expect(saves, 1);

    await stop(tester);
  }, variant: desktops);

  testWidgets('a letter with the primary modifier is not the bare letter', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    final crate = await designerBlock(tester);
    expect(plugin.scope.history.canUndo.value, isFalse);

    // Nothing to undo: Cmd+Z (Ctrl+Z) does nothing — it does not turn the
    // crate, which is what the bare Z does.
    await chord(tester, primary(), LogicalKeyboardKey.keyZ);
    expect(angleOf(crate), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.pump();
    expect(angleOf(crate), isNot(0), reason: 'Z alone turns it');

    await stop(tester);
  }, variant: desktops);

  testWidgets('on a Mac, Ctrl is no shortcut key: Ctrl+Z neither undoes nor '
      'turns', (tester) async {
    if (!kDebugMode) return;
    await start(tester);
    final crate = await designerBlock(tester);
    final before = entityCount();
    await chord(tester, primary(), LogicalKeyboardKey.keyD);
    expect(entityCount(), before + 1);

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyZ,
    );
    expect(entityCount(), before + 1, reason: 'not undone');
    expect(angleOf(crate), 0, reason: 'not turned');

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyD,
    );
    expect(entityCount(), before + 1, reason: 'not duplicated');

    await stop(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Backspace deletes the selection on a Mac, and only there', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    final crate = block('Crate');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(crate.isAlive, isNot(isMac()));

    if (!isMac()) {
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(crate.isAlive, isFalse, reason: 'Delete deletes everywhere');
    }

    await stop(tester);
  }, variant: desktops);

  testWidgets('typing in a field keeps the primary chords for the field', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    block('Crate');
    final before = entityCount();
    field.requestFocus();
    await tester.pump();

    await chord(tester, primary(), LogicalKeyboardKey.keyD);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(entityCount(), before, reason: 'neither duplicated nor deleted');

    await stop(tester);
  }, variant: desktops);

  testWidgets('tooltips and chords say Cmd on a Mac, Ctrl elsewhere', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await start(tester);
    final label = isMac() ? 'Cmd' : 'Ctrl';

    expect(find.byTooltip('Editor settings  ($label+,)'), findsOneWidget);
    expect(plugin.scope.commands.shortcutOf('editor.undo'), '$label+Z');
    expect(
      plugin.scope.commands.shortcutOf('editor.ungroup'),
      '$label+Shift+G',
    );

    await stop(tester);
  }, variant: desktops);
}
