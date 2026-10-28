// The store page's finish: kind chips with something to show, sorting, an
// installed item no catalog lists, the page when no catalog can be read,
// links, versions, and a checkout of your own's details.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine_editor/src/asset_store/store_controller.dart';
import 'package:just_game_engine_editor/src/asset_store/ui/store_window.dart';

import 'support/store_fixtures.dart';

void main() {
  late Directory project;

  Future<StoreController> controller(List<SourceConfig> sources) async {
    final c = StoreController(
      scope: storeScope(),
      root: project.path,
      sources: sources,
      cacheDir: tempDir('cache').path,
      pub: FakePub(),
    );
    addTearDown(c.dispose);
    await c.load();
    return c;
  }

  /// Lets real file work finish between frames.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  Future<void> show(WidgetTester tester, StoreController c) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StoreWindow(controller: c))),
    );
    await settle(tester);
  }

  /// A checkout of your own at plugins/just_mine, with a picture, which no
  /// catalog lists.
  void linkMine(StoreController c) {
    final folder = Directory('${project.path}/plugins/just_mine')
      ..createSync(recursive: true);
    File('${folder.path}/${ItemManifest.fileName}').writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'id': 'just_mine',
        'name': 'My Tool',
        'version': '0.3.0',
        'kind': 'editor-extension',
        'category': 'editors',
        'stage': 'beta',
        'summary': 'Something of my own.',
        'previews': ['store/card.png'],
      }),
    );
    File('${folder.path}/store/card.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([0x89, 0x50, 0x4e, 0x47]);
    c.project.writeLock(
      StoreLock(
        items: {
          'just_mine': const LockedItem(
            version: '0.3.0',
            kind: ItemKind.editorExtension,
            origin: ItemOrigin.linked,
            path: 'plugins/just_mine',
          ),
        },
      ),
    );
    c.refreshProject();
  }

  setUp(() => project = projectDir());

  test('kinds count what the page would show, whichever kind is picked', () async {
    final c = await controller([standardCatalog()]);
    expect(c.kindCounts, {ItemKind.content: 2, ItemKind.editorExtension: 1});
    c.filterKind(ItemKind.content);
    expect(c.shown.length, 2);
    expect(c.kindCounts, {ItemKind.content: 2, ItemKind.editorExtension: 1});
    c.search('knight');
    expect(c.kindCounts, {ItemKind.content: 1});
  });

  test('sorted by name, or by the newest release first', () async {
    final c = await controller([
      buildCatalog(tempDir('catalog'), const [
        Item('just_art_a', name: 'Apple', published: '2026-09-01'),
        Item('just_art_b', name: 'Banana', published: '2026-10-20'),
        Item('just_art_c', name: 'Cherry'),
      ]),
    ]);
    List<String> names() => [for (final e in c.shown) e.item.name];
    expect(names(), ['Apple', 'Banana', 'Cherry']);
    c.sortBy(StoreSort.updated);
    // Undated last.
    expect(names(), ['Banana', 'Apple', 'Cherry']);
  });

  test('versions newest first', () async {
    final c = await controller([standardCatalog()]);
    expect(
      [for (final v in c.versionsOf('just_art_knight')) '${v.version}'],
      ['1.1.0', '1.0.0'],
    );
  });

  test('an installed item no catalog lists is on the Installed page, as '
      'its manifest describes it, with its own picture', () async {
    final c = await controller([standardCatalog()]);
    linkMine(c);
    expect(c.shown.map((e) => e.item.id), isNot(contains('just_mine')));
    c.show(StoreTab.installed);
    final mine = c.shown.single;
    expect(mine.item.name, 'My Tool');
    expect(mine.item.summary, 'Something of my own.');
    expect(mine.item.stage, ItemStage.beta);
    expect(c.sourceOf(mine), ItemSource.local);
    expect(c.pictureCount(mine), 1);
    final picture = await c.thumbnail(mine);
    expect(picture?.path.replaceAll(r'\', '/'), endsWith('just_mine/store/card.png'));
  });

  test("the editor's own parts are not on the Installed page", () async {
    final c = await controller([standardCatalog()]);
    linkMine(c);
    // What `just create` records: the editor and the store's core, as
    // system items, beside what was added from the store.
    final lock = c.project.readLock();
    c.project.writeLock(
      StoreLock(
        items: {
          ...lock.items,
          for (final id in ['just_game_engine_editor', 'just_asset_store'])
            id: const LockedItem(
              version: '0.1.0',
              kind: ItemKind.editorExtension,
              origin: ItemOrigin.linked,
              path: 'packages/x',
              system: true,
            ),
        },
      ),
    );
    c.refreshProject();
    expect(c.lock.items, hasLength(3), reason: 'the lockfile keeps them');
    expect(c.listedInstalled, ['just_mine']);
    c.show(StoreTab.installed);
    expect(c.shown.map((e) => e.item.id), ['just_mine']);
  });

  test('links: the website only for the official catalog, and only https '
      'opens', () async {
    final c = await controller([standardCatalog()]);
    final listed = c.entry('just_art_knight')!;
    expect(c.webPage(listed), isNull);
    expect(c.reportPage(listed), isNull);
    final official = CatalogEntry(SourceConfig.officialId, listed.item);
    expect(
      '${c.webPage(official)}',
      'https://asset.justunknown.com/items/just_art_knight',
    );
    expect(
      '${c.reportPage(official)}',
      'https://asset.justunknown.com/report?item=just_art_knight',
    );
    expect(await c.openLink(Uri.parse('http://example.com')), isFalse);
    expect(await c.openLink(Uri.parse('file:///C:/Windows')), isFalse);
  });

  test('the name of the catalog an item comes from', () async {
    final c = await controller([standardCatalog()]);
    expect(c.sourceName('test'), 'Test catalog');
    expect(c.sourceName('elsewhere'), 'elsewhere');
  });

  testWidgets('no chip for a kind with nothing to show', (tester) async {
    late StoreController c;
    await tester.runAsync(() async => c = await controller([standardCatalog()]));
    await show(tester, c);
    expect(find.widgetWithText(EditorChip, 'Art & sound'), findsOneWidget);
    expect(find.widgetWithText(EditorChip, 'Editor tools'), findsOneWidget);
    expect(find.widgetWithText(EditorChip, 'Kits'), findsNothing);
    expect(find.widgetWithText(EditorChip, 'Libraries'), findsNothing);
  });

  testWidgets('a version picked is the one installed', (tester) async {
    late StoreController c;
    await tester.runAsync(() async => c = await controller([standardCatalog()]));
    await show(tester, c);
    await tester.tap(find.text('Knight'));
    await settle(tester);
    expect(find.widgetWithText(EditorButton, 'Install'), findsOneWidget);
    await tester.tap(find.byType(EditorDropdown<Version>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.0.0').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(EditorButton, 'Install 1.0.0'), findsOneWidget);
  });

  testWidgets("a checkout of your own: Local, and no buttons to press", (
    tester,
  ) async {
    late StoreController c;
    await tester.runAsync(() async {
      c = await controller([standardCatalog()]);
      linkMine(c);
    });
    c.show(StoreTab.installed);
    await show(tester, c);
    expect(find.text('My Tool'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    // Local says it is installed already.
    expect(find.text('Installed'), findsOneWidget); // the sidebar's
    await tester.tap(find.text('My Tool'));
    await settle(tester);
    expect(find.textContaining('Your own checkout'), findsOneWidget);
    expect(find.byType(EditorButton), findsNothing);
  });

  testWidgets("no catalog read: why, and what still works", (tester) async {
    late StoreController c;
    await tester.runAsync(
      () async => c = await controller([
        SourceConfig('${tempDir('gone').path}/missing/index.json', name: 'Gone'),
      ]),
    );
    expect(c.unreachable, isTrue);
    await show(tester, c);
    expect(find.text("Can't reach the Asset Store"), findsOneWidget);
    expect(find.widgetWithText(EditorButton, 'Try again'), findsOneWidget);
    expect(
      find.textContaining('Everything you have installed still works.'),
      findsOneWidget,
    );
    // The page says it; no banner repeats it.
    expect(find.textContaining('Could not read Gone'), findsNothing);
  });

  testWidgets('every catalog turned off', (tester) async {
    late StoreController c;
    await tester.runAsync(() async => c = await controller(const []));
    expect(c.noSources, isTrue);
    await show(tester, c);
    expect(find.text('No catalogs are turned on'), findsOneWidget);
    expect(find.widgetWithText(EditorButton, 'Sources'), findsOneWidget);
  });
}
