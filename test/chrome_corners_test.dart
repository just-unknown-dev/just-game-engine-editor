// What stands where over the viewport: a button that asks to stand apart
// from the modules' tools (the Asset Store's) is in the column down the
// right, in a frame of its own under the transform tools, in space the
// view cube has the bottom left corner to itself, and messages stand to the
// gear's left.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/quick_snap_bar.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/shared_widgets.dart';
import 'package:just_game_engine_editor/src/ui/overlay/shared/transform_toolbar.dart';

import 'support/memory_settings_store.dart';

class _Module extends EditorModule {
  int shopped = 0;

  @override
  String get id => 'corners';
  @override
  String get name => 'Corners';

  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'corners.paint',
      icon: Icons.brush,
      tooltip: 'Paint',
      onPressed: (_) {},
    ),
    ToolbarButton(
      id: 'corners.shop',
      icon: Icons.storefront_rounded,
      tooltip: 'Shop',
      slot: ToolbarSlot.toolColumn,
      onPressed: (_) => shopped++,
    ),
  ];
}

void main() {
  late Directory root;
  late EditorScope scope;
  late JustGameEditorPlugin plugin;
  late _Module module;

  setUp(() {
    root = Directory.systemTemp.createTempSync('chrome_corners_');
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> start(WidgetTester tester, {bool scene = true}) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    module = _Module();
    scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      engine: engine,
      modules: [module],
      scenesRoot: root.path,
      settingsStore: MemorySettingsStore(),
    );
    plugin = JustGameEditorPlugin(engine: engine, scope: scope);
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
    if (scene) plugin.sceneState.openScene(EditorScene(name: 'level'));
    await tester.pump();
  }

  Future<void> stop(WidgetTester tester) async {
    plugin.playController.stop();
    plugin.closeLevelDesigner();
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    scope.dispose();
  }

  Finder inToolbar(Finder f) =>
      find.descendant(of: find.byType(PlayControlsToolbar), matching: f);
  Finder inColumn(Finder f) =>
      find.descendant(of: find.byType(ToolColumnButtons), matching: f);
  Rect frameIn(WidgetTester tester, Type type) => tester.getRect(
    find
        .descendant(
          of: find.byType(type),
          matching: find.byType(FloatingToolFrame),
        )
        .first,
  );

  testWidgets('a button that asks for the column stands in a frame of its '
      'own under the transform tools, as wide as they are', (tester) async {
    if (!kDebugMode) return;
    await start(tester);

    expect(inToolbar(find.byTooltip('Paint')), findsOneWidget);
    expect(inToolbar(find.byTooltip('Shop')), findsNothing);
    expect(inColumn(find.byTooltip('Shop')), findsOneWidget);

    final transform = frameIn(tester, TransformToolbar);
    final store = frameIn(tester, ToolColumnButtons);
    expect(store.top - transform.bottom, 8, reason: 'the gap between frames');
    expect(store.width, transform.width);
    expect(store.right, transform.right);
    expect(
      tester.getSize(inColumn(find.byTooltip('Shop'))).height,
      ToolStripButton.buttonHeight,
      reason: 'the column\'s own buttons',
    );
    // The game camera preview hangs straight below the play toolbar again.
    // The canvas starts at the window's corner: no inset on the left/top.
    final toolbar = tester.getRect(find.byType(PlayControlsToolbar));
    expect(plugin.gamePreviewOrigin.dy, closeTo(toolbar.bottom + 8, 1));

    await tester.tap(inColumn(find.byTooltip('Shop')));
    expect(module.shopped, 1);

    // The designer's tool strip hangs below it.
    plugin.toggleLevelDesigner();
    await tester.pump();
    final strip = tester.getRect(
      find
          .ancestor(
            of: find.byType(ToolPalette),
            matching: find.byType(FloatingToolFrame),
          )
          .first,
    );
    expect(strip.top - frameIn(tester, ToolColumnButtons).bottom, 8);
    await stop(tester);
  });

  testWidgets('with the transform tools gone it takes their place: no '
      'scene, a play-test', (tester) async {
    if (!kDebugMode) return;
    await start(tester, scene: false);
    expect(
      find.descendant(
        of: find.byType(TransformToolbar),
        matching: find.byType(FloatingToolFrame),
      ),
      findsNothing,
    );
    final toolbar = tester.getRect(find.byType(PlayControlsToolbar));
    expect(frameIn(tester, ToolColumnButtons).top, toolbar.top);

    plugin.sceneState.openScene(EditorScene(name: 'level'));
    await tester.pump();
    expect(frameIn(tester, ToolColumnButtons).top, greaterThan(toolbar.top));

    plugin.playController.play();
    await tester.pump();
    expect(frameIn(tester, ToolColumnButtons).top, toolbar.top);
    await stop(tester);
  });

  testWidgets('in space the view cube is bottom left, off the gear\'s '
      'column', (tester) async {
    if (!kDebugMode) return;
    await start(tester, scene: false);
    plugin.sceneState.openScene(
      EditorScene(name: 'deep', mode: SceneMode.threeD),
    );
    await tester.pump();

    final cube = tester.getRect(find.byType(ViewCube));
    final gear = tester.getRect(find.byType(SettingsGearButton));
    final snap = tester.getRect(find.byType(QuickSnapBar));
    expect(cube.left, closeTo(16, 1), reason: 'the left edge');
    expect(cube.bottom, closeTo(gear.bottom, 1), reason: 'the gear\'s line');
    expect(cube.right, lessThan(snap.left), reason: 'not over the snapping');
    // The preview hanging from the top left stops short of it.
    expect(
      plugin.gamePreviewBottomReserve,
      greaterThanOrEqualTo(ViewCube.size + 10 + 16),
    );

    // In the plane, no cube.
    plugin.sceneState.openScene(EditorScene(name: 'flat'));
    await tester.pump();
    expect(find.byType(ViewCube), findsNothing);
    await stop(tester);
  });

  testWidgets("messages stand to the gear's left, the newest level with it, "
      'clear of the snapping above it', (tester) async {
    if (!kDebugMode) return;
    await start(tester);
    final messages = EditorMessenger.of(
      tester.element(find.byType(SettingsGearButton)),
    );
    messages.showSnackBar(const EditorSnackBarEntry(message: 'First'));
    await tester.pump();

    final gear = tester.getRect(find.byType(SettingsGearButton));
    final snap = tester.getRect(find.byType(QuickSnapBar));
    var layer = tester.getRect(find.byType(EditorSnackBarLayer));
    expect(layer.right, closeTo(gear.left - 8, 1), reason: 'beside the gear');
    expect(layer.bottom, closeTo(gear.bottom, 1), reason: "the gear's line");
    expect(layer.right, lessThan(snap.left), reason: 'not over the snapping');

    // A second one: the newest by the gear, the older stacked above it.
    messages.showSnackBar(const EditorSnackBarEntry(message: 'Second'));
    await tester.pump();
    layer = tester.getRect(find.byType(EditorSnackBarLayer));
    expect(layer.bottom, closeTo(gear.bottom, 1));
    expect(
      tester.getRect(find.text('Second')).top,
      greaterThan(tester.getRect(find.text('First')).bottom),
    );
    await tester.pump(const Duration(seconds: 10));
    await stop(tester);
  });
}
