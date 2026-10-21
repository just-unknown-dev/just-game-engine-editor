// With no scene open the viewport shows no level — nothing to see, pick or
// play — but a card on how to use the editor: the steps, the keys as they
// are bound, the tools that need no scene, and what the modules advise.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/prefs/recent_scenes.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/quick_snap_bar.dart';
import 'package:just_game_engine_editor/src/ui/overlay/start/start_card.dart';

import 'support/memory_settings_store.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

class _ToolsModule extends EditorModule {
  final List<String> opened = [];

  @override
  String get id => 'tools';
  @override
  String get name => 'Tools';

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'tools.paint',
      icon: Icons.brush,
      tooltip: 'Paint Studio: draw the sprites (Ctrl+Shift+P)',
      onPressed: (_) => opened.add('paint'),
    ),
  ];

  @override
  List<GettingStartedTip> get gettingStartedTips => const [
    GettingStartedTip(id: 'tools.tip', text: 'Paint before you place.'),
  ];
}

void main() {
  test('a module button is named from its tooltip', () {
    expect(
      EditorStartCard.splitTooltip('Sprite Studio: draw and animate sprites'),
      ('Sprite Studio', 'Draw and animate sprites'),
    );
    expect(
      EditorStartCard.splitTooltip("Interface — the game's screens (Ctrl+U)"),
      ('Interface', "The game's screens"),
    );
    expect(EditorStartCard.splitTooltip('Paint'), ('Paint', null));
  });

  group('in the editor', () {
    late Directory root;
    late EditorScope scope;
    late JustGameEditorPlugin plugin;
    late _ToolsModule tools;

    setUp(() async {
      root = Directory.systemTemp.createTempSync('start_card_');
      final store = SceneStore(
        root: root.path,
        codec: SceneCodec(ComponentDefinitionRegistry.core()),
      );
      for (final name in ['level_01', 'level_02']) {
        await store.writeInitialFiles(name);
      }
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<void> start(
      WidgetTester tester, {
      Size size = const Size(1400, 900),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      tools = _ToolsModule();
      scope = EditorScope(
        builtIns: const [BuiltInEditorModule.new],
        engine: engine,
        modules: [tools],
        scenesRoot: root.path,
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

    Finder onCard(Finder f) =>
        find.descendant(of: find.byType(EditorStartCard), matching: f);

    testWidgets('no scene: the card covers the viewport, and the level '
        'tools are gone', (tester) async {
      if (!kDebugMode) return;
      await start(tester);

      expect(find.byType(EditorStartCover), findsOneWidget);
      expect(find.text('Just Game Engine Editor'), findsOneWidget);
      expect(find.byTooltip('Play  (F5)'), findsNothing);
      expect(find.byType(QuickSnapBar), findsNothing);
      expect(find.byTooltip('Move  (W)'), findsNothing);
      // What needs no scene stays: the settings, and the module's tool.
      expect(find.byTooltip('Editor settings  (Ctrl+,)'), findsOneWidget);
      expect(find.byIcon(Icons.brush), findsWidgets);

      // A scene opened: the level and its tools are back.
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      await tester.pump();
      expect(find.byType(EditorStartCover), findsNothing);
      expect(find.byTooltip('Play  (F5)'), findsOneWidget);
      expect(find.byType(QuickSnapBar), findsOneWidget);

      plugin.sceneState.closeScene();
      await tester.pump();
      expect(find.byType(EditorStartCover), findsOneWidget);
      await stop(tester);
    });

    testWidgets('squeezed by the docks, a phone held upright, the card '
        'still lays out', (tester) async {
      if (!kDebugMode) return;
      // The docks leave the card narrower than its own padding: the
      // asset-editor tiles must not ask for a negative width.
      await start(tester, size: const Size(412, 915));
      expect(tester.takeException(), isNull);
      expect(find.text('Just Game Engine Editor'), findsOneWidget);
      await stop(tester);
    });

    testWidgets('the steps show the keys as they are bound', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      for (final key in ['F3', 'F5', 'Ctrl+S', 'W', 'E', 'R', 'F1', 'F2']) {
        expect(onCard(find.text(key)), findsOneWidget, reason: key);
      }
      await stop(tester);
    });

    testWidgets("the modules' tools open from the card, and their tips "
        'show', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      expect(onCard(find.text('Paint Studio')), findsOneWidget);
      expect(onCard(find.text('Draw the sprites')), findsOneWidget);
      expect(onCard(find.text('Paint before you place.')), findsOneWidget);
      await tester.tap(onCard(find.text('Paint Studio')));
      expect(tools.opened, ['paint']);
      await stop(tester);
    });

    testWidgets('Reopen names the scene last worked on; without one, Open '
        'names where the game starts', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      expect(onCard(find.text('Open level_01')), findsOneWidget);
      await scope.prefs.set(RecentScenes.lastScene, 'level_02');
      await tester.pump();
      expect(onCard(find.text('Reopen level_02')), findsOneWidget);
      expect(onCard(find.text('Open level_01')), findsNothing);
      await stop(tester);
    });

    testWidgets('there is nothing to play with no scene: F5 waits for one', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await start(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      expect(plugin.playController.state.value, EditorPlayState.stopped);

      plugin.sceneState.openScene(EditorScene(name: 'level'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      expect(plugin.playController.state.value, EditorPlayState.playing);
      await stop(tester);
    });

    testWidgets('with the Scenes list focused, F2 renames there rather than '
        'opening the docks', (tester) async {
      if (!kDebugMode) return;
      await start(tester);
      final docks = plugin.scope.dockController.openId.value;
      await tester.tap(find.text('PLAY ORDER'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.text('Rename "level_01"'), findsOneWidget);
      expect(plugin.scope.dockController.openId.value, docks);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await stop(tester);
    });
  });
}
