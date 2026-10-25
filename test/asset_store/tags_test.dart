// Tags: how finished an item is (its stage) and where it comes from (its
// source), the editor's own stage, and what the Store window does with
// them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/asset_store/store_checks.dart';
import 'package:just_game_engine_editor/src/asset_store/store_controller.dart';
import 'package:just_game_engine_editor/src/asset_store/ui/store_window.dart';
import 'package:just_game_engine_editor/src/editor_release.dart';

import 'support/store_fixtures.dart';

/// A catalog with an item at every stage.
SourceConfig stagedCatalog() => buildCatalog(tempDir('catalog'), const [
  Item(
    'just_sturdy_tool',
    name: 'Sturdy Tool',
    kind: ItemKind.editorExtension,
    category: 'editors',
    stage: ItemStage.stable,
  ),
  Item(
    'just_handy_tool',
    name: 'Handy Tool',
    kind: ItemKind.editorExtension,
    category: 'editors',
  ),
  Item(
    'just_new_tool',
    name: 'New Tool',
    kind: ItemKind.editorExtension,
    category: 'editors',
    stage: ItemStage.experimental,
  ),
  Item(
    'just_old_tool',
    name: 'Old Tool',
    kind: ItemKind.editorExtension,
    category: 'editors',
    stage: ItemStage.deprecated,
    replacedBy: 'just_handy_tool',
  ),
]);

void main() {
  late StoreController c;
  late Directory project;

  setUp(() async {
    project = projectDir();
    c = StoreController(
      scope: storeScope(),
      root: project.path,
      sources: [stagedCatalog()],
      cacheDir: tempDir('cache').path,
      pub: FakePub(),
    );
    addTearDown(c.dispose);
    await c.load();
  });

  List<String> shown() => [for (final e in c.shown) e.item.id];

  test('experimental items wait for "Show experimental"; deprecated ones '
      'for a search', () {
    expect(shown(), ['just_handy_tool', 'just_sturdy_tool']);
    expect(c.categoryCounts, {'editors': 2});
    c.showExperimental = true;
    expect(shown(), ['just_handy_tool', 'just_new_tool', 'just_sturdy_tool']);
    expect(c.categoryCounts, {'editors': 3});
    c.search('old');
    expect(shown(), ['just_old_tool']);
    c
      ..search('')
      ..showExperimental = false;
    expect(shown(), isNot(contains('just_new_tool')));
  });

  test('where each comes from, and a linked checkout is Local', () {
    final entry = c.entry('just_handy_tool')!;
    expect(c.sourceOf(entry), ItemSource.official);
    c.project.writeLock(
      StoreLock(
        items: {
          'just_handy_tool': const LockedItem(
            version: '1.0.0',
            kind: ItemKind.editorExtension,
            origin: ItemOrigin.linked,
            path: '../plugins/just_handy_tool',
          ),
        },
      ),
    );
    c.refreshProject();
    expect(c.sourceOf(entry), ItemSource.local);
  });

  test('a deprecated item installed is a warning, naming what replaces it', () async {
    c.search('old');
    await c.apply(c.planInstall('just_old_tool')!);
    File('${project.path}/lib/main_editor.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'editor/store_modules.g.dart';\nvoid main() => storeModules();\n",
      );
    final checks = StoreChecks(c, every: Duration.zero);
    final problems = checks.check(
      ValidationContext(scope: c.scope, projectRoot: project.path),
    );
    expect(problems.single.message, 'Old Tool is deprecated: it is no longer developed.');
    expect(problems.single.hint, contains('Install Handy Tool instead'));
  });

  test('installing an experimental or deprecated item says so first', () {
    String warnings(String id) => c
        .planInstall(id)!
        .issues
        .where((i) => i.level == IssueLevel.warning)
        .map((i) => i.message)
        .join('\n');
    expect(warnings('just_new_tool'), contains('is experimental'));
    expect(warnings('just_old_tool'), contains('Use Handy Tool instead.'));
    expect(warnings('just_sturdy_tool'), isNot(contains('experimental')));
  });

  testWidgets('cards carry the tags; stable shows none', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: StoreWindow(controller: c))),
    );
    await tester.pump();
    expect(find.text('BETA'), findsOneWidget);
    expect(find.text('OFFICIAL'), findsNWidgets(2));
    expect(find.text('STABLE'), findsNothing);
    expect(find.text('EXPERIMENTAL'), findsNothing);
    await tester.tap(find.text('Show experimental'));
    await tester.pump();
    expect(find.text('EXPERIMENTAL'), findsOneWidget);
  });

  test("the editor's own stage, and its version as its pubspec says", () {
    expect(EditorRelease.stage, ItemStage.beta);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)![1],
      EditorRelease.version,
    );
    final manifest = ItemManifest.parse(
      File('just_store.json').readAsStringSync(),
    );
    expect(manifest.stage, EditorRelease.stage);
    expect('${manifest.version}', EditorRelease.version);
  });

  test("every first-party plugin in the template names its stage", () {
    final plugins = Directory('../../plugins');
    if (!plugins.existsSync()) return; // the editor checked out on its own
    final stages = {
      for (final d in plugins.listSync().whereType<Directory>())
        if (File('${d.path}/just_store.json').existsSync())
          d.uri.pathSegments.where((s) => s.isNotEmpty).last: ItemManifest.parse(
            File('${d.path}/just_store.json').readAsStringSync(),
          ).stage,
    };
    expect(stages, {
      'just_input_editor': ItemStage.beta,
      'just_material_editor': ItemStage.beta,
      'just_platformer_kit': ItemStage.beta,
      'just_sprite_editor': ItemStage.beta,
      'just_third_person_kit': ItemStage.beta,
      'just_ui_editor': ItemStage.experimental,
      'just_world_builder_kit': ItemStage.beta,
    });
  });
}
