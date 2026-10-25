// The store window's state: catalogs, filters, plans, installs, updates,
// the restart flag, and the Problems dock's checks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/asset_store.dart';
import 'package:just_game_engine_editor/src/asset_store/store_checks.dart';
import 'package:just_game_engine_editor/src/asset_store/store_controller.dart';

import 'support/store_fixtures.dart';

void main() {
  late Directory project;
  late StoreController c;
  late FakePub pub;
  late List<String> reloaded;

  setUp(() async {
    project = projectDir();
    pub = FakePub();
    final scope = storeScope();
    reloaded = [];
    scope.assetReloader = reloaded.addAll;
    c = StoreController(
      scope: scope,
      root: project.path,
      sources: [standardCatalog()],
      cacheDir: tempDir('cache').path,
      pub: pub,
    );
    addTearDown(c.dispose);
    await c.load();
  });

  test('loads the catalog and filters it', () {
    expect(c.catalog!.sources.single.loaded, isTrue);
    expect(c.shown.map((e) => e.item.name), ['Handy Tool', 'Knight', 'Slime']);
    c.search('knight');
    expect(c.shown.single.item.id, 'just_art_knight');
    c.search('pixel');
    expect(c.shown.single.item.id, 'just_art_knight', reason: 'summary');
    c.search('');
    c.filterKind(ItemKind.editorExtension);
    expect(c.shown.single.item.id, 'just_tool');
    c.filterKind(null);
    c.show(StoreTab.browse, category: 'characters');
    expect(c.shown.map((e) => e.item.id), [
      'just_art_knight',
      'just_art_slime',
    ]);
    expect(c.categoryCounts, {'characters': 2, 'editors': 1});
    c.show(StoreTab.installed);
    expect(c.shown, isEmpty);
  });

  test(
    'installs, shows it installed, reloads its assets, updates, removes',
    () async {
      final plan = c.planInstall(
        'just_art_knight',
        version: Version.parse('1.0.0'),
      )!;
      expect(plan.canApply, isTrue);
      final result = await c.apply(plan);
      expect(pub.calls, ['get']);
      expect(c.installed('just_art_knight')!.version, '1.0.0');
      expect(
        reloaded,
        contains('packages/just_art_knight/sprites/just_art_knight.png'),
      );
      expect(result.needsRestart, isFalse);
      expect(c.restartPending, isFalse);
      expect(
        File(
          '${project.path}/packages/characters/just_art_knight/sprites/just_art_knight.png',
        ).existsSync(),
        isTrue,
      );

      expect(c.updates, ['just_art_knight']);
      expect('${c.updateFor('just_art_knight')!.version}', '1.1.0');
      c.show(StoreTab.updates);
      expect(c.shown.single.item.id, 'just_art_knight');
      await c.apply(c.planUpdate('just_art_knight')!);
      expect(c.installed('just_art_knight')!.version, '1.1.0');
      expect(c.updates, isEmpty);

      await c.apply(c.planUninstall('just_art_knight')!);
      expect(c.installed('just_art_knight'), isNull);
      expect(
        Directory(
          '${project.path}/packages/characters/just_art_knight',
        ).existsSync(),
        isFalse,
      );
    },
  );

  test('installing editor code means a restart', () async {
    expect(c.restartPending, isFalse);
    final result = await c.apply(c.planInstall('just_tool')!);
    expect(result.needsRestart, isTrue);
    expect(c.restartPending, isTrue);
    expect(
      File(
        '${project.path}/lib/editor/store_modules.g.dart',
      ).readAsStringSync(),
      contains('s0.HandyModule()'),
    );
  });

  test(
    'progress is reported while applying, and one install at a time',
    () async {
      final seen = <String>[];
      c.addListener(() {
        if (c.progress != null) seen.add(c.progress!.message);
      });
      final first = c.apply(c.planInstall('just_art_slime')!);
      expect(c.busy, isTrue);
      expect(
        () => c.apply(c.planInstall('just_art_knight')!),
        throwsStateError,
      );
      await first;
      expect(c.busy, isFalse);
      expect(seen, contains('Resolving packages (pub get)'));
    },
  );

  test("a source that can't be read is reported, not thrown", () async {
    final broken = StoreController(
      scope: storeScope(),
      root: project.path,
      sources: [SourceConfig('${tempDir('none').path}/missing')],
      pub: pub,
    );
    addTearDown(broken.dispose);
    await broken.load();
    expect(broken.troubledSources.single.loaded, isFalse);
    expect(broken.shown, isEmpty);
  });

  group('Problems dock', () {
    test('quiet for a project with nothing from the store', () {
      final checks = StoreChecks(c, every: Duration.zero);
      expect(
        checks.check(
          ValidationContext(scope: c.scope, projectRoot: project.path),
        ),
        isEmpty,
      );
    });

    test(
      'a missing folder, stale generated files, and an unused registry',
      () async {
        await c.apply(c.planInstall('just_tool')!);
        final checks = StoreChecks(c, every: Duration.zero);
        final context = ValidationContext(
          scope: c.scope,
          projectRoot: project.path,
        );
        expect(checks.check(context).map((p) => p.message), [
          "The editor's entry point does not register the store's editor tools.",
        ]);
        File('${project.path}/lib/main_editor.dart').writeAsStringSync(
          "import 'editor/store_modules.g.dart';\nvoid main() => storeModules();\n",
        );
        expect(checks.check(context), isEmpty);
        File(
          '${project.path}/lib/editor/store_modules.g.dart',
        ).writeAsStringSync('// edited');
        expect(checks.check(context).single.message, contains('out of date'));
        // An editor tool is a plugin: installed under plugins/, not packages/.
        expect(
          Directory('${project.path}/packages/editors/just_tool').existsSync(),
          isFalse,
        );
        Directory(
          '${project.path}/plugins/editors/just_tool',
        ).deleteSync(recursive: true);
        expect(
          checks.check(context).map((p) => p.message).join('\n'),
          contains('just_tool is installed, but plugins/editors/just_tool'),
        );
      },
    );

    test('answers are kept between checks', () async {
      final checks = StoreChecks(c);
      final context = ValidationContext(
        scope: c.scope,
        projectRoot: project.path,
      );
      expect(checks.check(context), isEmpty);
      await c.apply(c.planInstall('just_tool')!);
      expect(checks.check(context), isEmpty, reason: 'kept');
      checks.invalidate();
      expect(checks.check(context), isNotEmpty);
    });
  });

  test(
    'the module contributes its window, button, command, key and actions',
    () {
      final module = BuiltInAssetStoreModule(root: project.path, pub: pub);
      expect(module.workspaces.single.id, BuiltInAssetStoreModule.workspaceId);
      expect(module.toolbarButtons.single.id, 'asset_store.open');
      expect(module.gettingStartedTips.single.id, 'asset_store.tip');
      expect(module.commands.single.id, 'store.open');
      expect(module.keyBindings.single.commandId, 'store.open');
      final show = module.assetActions.firstWhere(
        (a) => a.id == 'asset_store.show',
      );
      expect(
        show.appliesTo('packages/just_art_knight', isDirectory: true),
        isTrue,
      );
      expect(
        show.appliesTo('packages/just_art_knight/sprites', isDirectory: true),
        isFalse,
      );
      expect(show.appliesTo('assets', isDirectory: true), isFalse);
      expect(
        module.assetActions
            .firstWhere((a) => a.id == 'asset_store.get')
            .appliesTo('assets', isDirectory: true),
        isTrue,
      );
      expect(module.dataFileSuffixes, [
        '/just_store.json',
        'just_store.lock.json',
      ]);
      expect(module.settingsSections.single.id, 'asset_store');
    },
  );

  test('the shop button stands under the transform tools, always', () {
    final module = BuiltInAssetStoreModule(root: project.path, pub: pub);
    final button = module.toolbarButtons.single;
    expect(button.slot, ToolbarSlot.toolColumn);
    expect(button.tooltip, contains('Ctrl+Shift+G'));
    expect(button.isActive!(c.scope), isFalse);
    // The start card points at it.
    expect(module.gettingStartedTips.single.text, contains('shop button'));
  });
}
