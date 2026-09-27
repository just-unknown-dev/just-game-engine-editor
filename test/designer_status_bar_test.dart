// The status bar sits flush with the bottom of the window. A Material
// DropdownButton there fails an assertion the moment it opens: Flutter
// centres the selected item over a button shorter than an item, which pushes
// the menu past the bottom edge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

void main() {
  _tileControlTests();

  testWidgets('the grid size picker opens at the bottom edge and changes '
      'the grid', (tester) async {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final session = LevelDesignerSession(
      scope: testScope(world: world),
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);

    double? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: DesignerStatusBar.height,
              child: DesignerStatusBar(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (v) => chosen = v,
              ),
            ),
          ),
        ),
      ),
    );

    // After the tool's options, which may push it along.
    await tester.ensureVisible(find.text('32px'));
    await tester.tap(find.text('32px'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('64px').last);
    await tester.pumpAndSettle();
    expect(chosen, 64);
  });

  testWidgets('a crowded bar in a narrow window does not overflow', (
    tester,
  ) async {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final session = LevelDesignerSession(
      scope: testScope(world: world, modules: [_ManyOverlays()])
        ..selectDesigner('many'),
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    session
      ..setTool(BuiltInTools.paint)
      ..controller.setStatus(
        'That region is open - close it off before filling, and then some '
        'more words so the message is far longer than the bar',
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 700,
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
    expect(tester.takeException(), isNull);
  });
}

class _ManyOverlays extends EditorModule {
  @override
  String get id => 'many';

  @override
  String get name => 'Many';

  @override
  List<DesignerOverlay> get overlays => [
    for (var i = 0; i < 8; i++) _Blank('blank.$i'),
  ];
}

class _Blank extends DesignerOverlay {
  _Blank(this.id);

  @override
  final String id;

  @override
  String get label => 'A long overlay name $id';

  @override
  IconData get icon => Icons.circle;

  @override
  void paint(OverlayPaintContext context) {}
}

void _tileControlTests() {
  testWidgets('with a tile tool the bar shows the cell under the pointer, '
      'and the tool\'s settings at its left', (tester) async {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final scope = testScope(world: world);
    final session = LevelDesignerSession(
      scope: scope,
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: () => const ModifierKeys(),
    );
    addTearDown(session.dispose);
    final data = BuiltInPrefabs.newLevelMap();
    data.layers.single.cells.setCell(1, 2, TileCell.make(0, 7, TileCell.flipH));
    final map = world.createEntityWithComponents([
      TransformComponent(),
      LevelMapComponent(inline: data),
    ], name: 'Map');
    scope.tiles.selectMap(map);
    scope.tiles.hoverCell = const TileCoord(1, 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: DesignerStatusBar.height,
            child: DesignerStatusBar(
              session: session,
              gridSize: 32,
              onGridSizeChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    final readout = find.textContaining('1, 2 · missing tileset #7 (H)');
    expect(readout, findsNothing, reason: 'no tile tool yet');

    session.setTool(TileTools.fill);
    await tester.pump();
    expect(readout, findsOneWidget);
    expect(find.text('Ground'), findsOneWidget, reason: 'the layer painted');
    expect(find.text('Bucket'), findsOneWidget);

    session.setTool(BuiltInTools.paint);
    await tester.pump();
    expect(readout, findsNothing);
    expect(find.text('Brush'), findsOneWidget, reason: 'Paint\'s modes');
    expect(tester.takeException(), isNull);
  });
}
