// The store window as a user meets it: browse, open an item, preview the
// install, install it, see it installed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_asset_store/just_asset_store.dart' show StoreLock, Version;
import 'package:just_editor_core/just_editor_core.dart'
    show EditorButton, EditorDropdown;
import 'package:just_game_engine_editor/src/asset_store/store_controller.dart';
import 'package:just_game_engine_editor/src/asset_store/ui/store_workspace.dart';

import '../support/real_io.dart';
import 'support/store_fixtures.dart';

void main() {
  late StoreController c;

  /// Lets real file and catalog work go on, frame by frame, until [done]
  /// holds — what the next expectation needs — rather than for a
  /// fixed time, which a busy machine can outrun.
  Future<void> settle(
    WidgetTester tester,
    bool Function() done, {
    required String what,
  }) => pumpUntil(tester, done, what: what);

  bool shows(Finder finder) => finder.evaluate().isNotEmpty;

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
        home: Scaffold(body: StoreWorkspace(controller: c)),
      ),
    );
    await settle(
      tester,
      () => shows(find.text('Knight')) && shows(find.text('Handy Tool')),
      what: 'the catalog shown',
    );
  }

  testWidgets('browse, preview and install', (tester) async {
    await open(tester);
    expect(find.text('Asset Store'), findsOneWidget);
    expect(find.text('Knight'), findsOneWidget);
    expect(find.text('Slime'), findsOneWidget);
    expect(find.text('Handy Tool'), findsOneWidget);

    // Its card says what it is.
    expect(find.text('A pixel knight'), findsOneWidget);

    await tester.tap(find.text('Knight'));
    await settle(
      tester,
      () => find.text('A pixel knight').evaluate().length == 2,
      what: 'the details',
    );
    // The card and the details.
    expect(find.text('A pixel knight'), findsNWidgets(2));
    // Two versions: a menu to pick one, the newest first.
    expect(find.byType(EditorDropdown<Version>), findsOneWidget);
    expect(
      tester
          .widget<EditorDropdown<Version>>(find.byType(EditorDropdown<Version>))
          .value
          .toString(),
      '1.1.0',
    );

    await tester.tap(find.widgetWithText(EditorButton, 'Install'));
    await settle(
      tester,
      () => shows(find.text('Install Knight?')),
      what: 'the install preview',
    );
    expect(find.text('Install Knight?'), findsOneWidget);
    expect(find.text('Knight 1.1.0'), findsOneWidget);

    // The dialog's Install: the last "Install" on screen.
    await tester.tap(find.text('Install').last);
    await settle(
      tester,
      () =>
          c.installed('just_art_knight') != null &&
          !c.busy &&
          shows(find.text('INSTALLED 1.1.0')),
      what: 'the install',
    );
    expect(c.installed('just_art_knight')!.version, '1.1.0');
    expect(find.text('INSTALLED 1.1.0'), findsOneWidget);
    expect(find.text('Uninstall'), findsOneWidget);

    // Its card says so, on its picture.
    expect(find.text('Installed'), findsNWidgets(3)); // + sidebar, details

    // The Installed page (the sidebar's) lists it.
    await tester.tap(find.text('Installed').first);
    await settle(
      tester,
      () => !shows(find.text('Slime')),
      what: 'the Installed page',
    );
    expect(find.text('Slime'), findsNothing);
    expect(find.text('Knight'), findsWidgets);
  });

  testWidgets('uninstalling previews the files changed by hand', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(() async {
      await c.apply(
        c.planInstall('just_art_knight', version: Version.parse('1.0.0'))!,
      );
      File(
        '${c.project.root}/packages/characters/just_art_knight/sprites/just_art_knight.png',
      ).writeAsStringSync('painted over');
    });
    await tester.pump();
    await tester.tap(find.text('Knight').first);
    await settle(
      tester,
      () => shows(find.widgetWithText(EditorButton, 'Uninstall')),
      what: 'the details',
    );

    await tester.tap(find.widgetWithText(EditorButton, 'Uninstall'));
    // The project is searched and hashed on other isolates first.
    await settle(
      tester,
      () => shows(find.text('Uninstall Knight?')),
      what: 'the uninstall preview',
    );
    expect(find.text('Uninstall Knight?'), findsOneWidget);
    expect(find.textContaining('sprites/just_art_knight.png'), findsOneWidget);
    expect(find.textContaining('Uninstalling removes the folder'), findsOne);
    await tester.tap(find.text('Cancel'));
    await settle(
      tester,
      () => !c.busy && !shows(find.text('Uninstall Knight?')),
      what: 'the preview put away',
    );
    expect(c.installed('just_art_knight'), isNotNull);
    expect(c.busy, isFalse);
  });

  testWidgets('search narrows the grid; the Sources page shows the catalog', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'slime');
    await settle(
      tester,
      () => !shows(find.text('Knight')),
      what: 'the grid narrowed',
    );
    expect(find.text('Knight'), findsNothing);
    expect(find.text('Slime'), findsOneWidget);

    await tester.tap(find.text('Sources'));
    await settle(
      tester,
      () => shows(find.textContaining('3 items')),
      what: 'the Sources page',
    );
    expect(find.textContaining('3 items'), findsOneWidget);
    expect(find.text('Restore missing packages'), findsOneWidget);
  });

  testWidgets('a restore that fails says why, on the page', (tester) async {
    await open(tester);
    await tester.tap(find.text('Sources'));
    await settle(
      tester,
      () => shows(find.text('Restore missing packages')),
      what: 'the Sources page',
    );
    // A damaged lockfile: the restore throws before it does anything.
    await tester.runAsync(() async {
      File('${c.project.root}/${StoreLock.fileName}').writeAsStringSync('{');
    });
    await tester.tap(find.text('Restore missing packages'));
    await settle(
      tester,
      () => shows(find.textContaining('Could not restore')),
      what: 'the reason shown',
    );
    expect(tester.takeException(), isNull);
    expect(c.busy, isFalse);
  });
}
