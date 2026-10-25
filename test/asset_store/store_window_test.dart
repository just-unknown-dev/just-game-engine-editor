// The store window as a user meets it: browse, open an item, preview the
// install, install it, see it installed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart' show EditorButton;
import 'package:just_game_engine_editor/src/asset_store/store_controller.dart';
import 'package:just_game_engine_editor/src/asset_store/ui/store_window.dart';

import 'support/store_fixtures.dart';

void main() {
  late StoreController c;

  /// Lets real file and catalog work finish between frames.
  Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
      if (until != null && until()) break;
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      c = StoreController(
        scope: storeScope(),
        root: projectDir().path,
        sources: [standardCatalog()],
        cacheDir: tempDir('cache').path,
        pub: FakePub(),
      );
      await c.load();
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StoreWindow(controller: c)),
      ),
    );
    await settle(tester);
  }

  testWidgets('browse, preview and install', (tester) async {
    await open(tester);
    expect(find.text('Asset Store'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    expect(find.text('Slime'), findsOneWidget);
    expect(find.text('Handy Tool'), findsOneWidget);

    await tester.tap(find.text('Knight'));
    await settle(tester);
    expect(find.text('A pixel knight'), findsOneWidget);
    expect(find.text('Latest 1.1.0'), findsOneWidget);

    await tester.tap(find.widgetWithText(EditorButton, 'Install'));
    await settle(tester);
    expect(find.text('Install Knight?'), findsOneWidget);
    expect(find.text('Knight 1.1.0'), findsOneWidget);

    // The dialog's Install: the last "Install" on screen.
    await tester.tap(find.text('Install').last);
    await settle(
      tester,
      until: () => c.installed('just_art_knight') != null && !c.busy,
    );
    await tester.pump();
    expect(c.installed('just_art_knight')!.version, '1.1.0');
    expect(find.text('INSTALLED 1.1.0'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);

    // The Installed page lists it.
    await tester.tap(find.text('Installed'));
    await settle(tester);
    expect(find.text('Slime'), findsNothing);
  });

  testWidgets('search narrows the grid; the Sources page shows the catalog', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'slime');
    await settle(tester);
    expect(find.text('Knight'), findsNothing);
    expect(find.text('Slime'), findsOneWidget);

    await tester.tap(find.text('Sources'));
    await settle(tester);
    expect(find.textContaining('3 items'), findsOneWidget);
    expect(find.text('Restore missing packages'), findsOneWidget);
  });
}
