// The tool's options, at the left of the designer's status bar along the
// foot of the window, follow the tool in hand: its name and key, then its
// settings — or what it does, when it has none.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  late World world;
  late EditorScope scope;
  late LevelDesignerSession session;

  setUp(() {
    world = World()..initialize();
    scope = testScope(world: world);
    session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
  });

  tearDown(() {
    session.dispose();
    world.dispose();
  });

  Future<void> pump(WidgetTester tester, {double width = 1400}) {
    // As wide as an editor window; the status message has its share too.
    tester.view
      ..physicalSize = const Size(1400, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // Where the bar is: at the foot of the window.
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: width,
              height: DesignerStatusBar.height,
              child: DesignerStatusBar(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a tool with no settings says what it does', (tester) async {
    session.setTool(BuiltInTools.measure);
    await pump(tester);
    final measure = session.tools.byId(BuiltInTools.measure)!;
    expect(find.text('Measure'), findsOneWidget);
    expect(find.text('M'), findsOneWidget, reason: 'its key');
    expect(find.text(measure.description!), findsOneWidget);
  });

  testWidgets('the tool comes first in the bar, before the designer\'s own '
      'settings', (tester) async {
    session.setTool(BuiltInTools.measure);
    await pump(tester);
    final tool = tester.getRect(find.byType(ToolOptionsBar));
    expect(tool.left, lessThan(tester.getRect(find.text('Snap')).left));
    expect(tool.bottom, lessThanOrEqualTo(600), reason: 'in the bar');
    expect(tool.top, greaterThanOrEqualTo(600 - DesignerStatusBar.height));
  });

  testWidgets('Paint shows its modes, and the brush size only where it '
      'counts', (tester) async {
    session.setTool(BuiltInTools.paint);
    await pump(tester);
    expect(find.text('Brush'), findsOneWidget);
    expect(find.text('Fill'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);

    await tester.ensureVisible(find.text('3'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();
    expect(session.controller.brushSize.value, 3);

    await tester.ensureVisible(find.text('Rect'));
    await tester.pump();
    await tester.tap(find.text('Rect'));
    await tester.pump();
    expect(session.controller.paintMode.value, PaintMode.rectangle);
    expect(find.text('Size'), findsNothing, reason: 'a rectangle has no width');
    expect(
      find.text(session.controller.activePrefab!.name),
      findsOneWidget,
      reason: 'what is placed',
    );
  });

  testWidgets('a tile tool shows the layer, its own settings and the view '
      'switches', (tester) async {
    final data = BuiltInPrefabs.newLevelMap();
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: 'Map');
    scope.tiles.selectMap(map);
    await pump(tester);
    expect(find.text('Ground'), findsNothing, reason: 'no tile tool yet');

    session.setTool(TileTools.fill);
    await tester.pump();
    expect(find.text('Ground'), findsOneWidget);
    expect(find.text('Bucket'), findsOneWidget);
    expect(find.text('Random'), findsOneWidget);
    expect(
      find.byTooltip('Show the tiles\' collision, coloured by kind'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ellipse'));
    await tester.pump();
    expect(scope.tiles.fillShape.value, TileFillShape.ellipse);

    await tester.tap(find.text('Random'));
    await tester.pump();
    expect(scope.tiles.random.value, isTrue);

    session.setTool(TileTools.select);
    await tester.pump();
    expect(find.text('Bucket'), findsNothing);
    expect(find.text('Wand'), findsOneWidget);
    expect(find.text('Random'), findsNothing);

    session.setTool(TileTools.erase);
    await tester.pump();
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(session.controller.brushSize.value, 5);

    session.setTool(TileTools.terrain);
    await tester.pump();
    expect(find.text('Choose a terrain in the Tileset panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the layer picker paints another layer', (tester) async {
    final data = BuiltInPrefabs.newLevelMap();
    data.addLayer(name: 'Front');
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: 'Map');
    scope.tiles.selectMap(map);
    session.setTool(TileTools.stamp);
    await pump(tester);

    await tester.tap(find.byTooltip('The layer being painted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ground').last);
    await tester.pumpAndSettle();
    expect(scope.tiles.layerId.value, data.layers.first.id);
  });

  testWidgets('in a narrow window it scrolls rather than overflows', (
    tester,
  ) async {
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: BuiltInPrefabs.newLevelMap()),
    ], name: 'Map');
    scope.tiles.selectMap(map);
    session.setTool(TileTools.fill);
    await pump(tester, width: 90);
    expect(tester.takeException(), isNull);
  });
}
