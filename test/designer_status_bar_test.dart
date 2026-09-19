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
