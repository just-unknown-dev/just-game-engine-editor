// Scene renames, copies and deletes that never lose a scene: a rename may
// change only the letter case of the scene's own name and nothing else may
// clash, a copy never lands on its source, a delete goes to the trash and
// comes back, the backups and the other scenes' mentions follow a rename,
// and a scene file of the wrong shape is listed as unreadable.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/memory_settings_store.dart';
import 'support/real_io.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_manager.dart';
import 'package:just_game_engine_editor/src/ui/panels/scene_picker_panel.dart';

/// A store that records the renames it is asked for instead of making
/// them: what [SceneManager] lets through, whatever the disk does.
class _RecordingStore extends SceneStore {
  _RecordingStore({required super.codec, required super.root});

  final List<(String, String)> renames = [];

  @override
  Future<void> renameSceneFiles(String oldName, String newName) async =>
      renames.add((oldName, newName));
}

void main() {
  late Directory root;
  late SceneStore store;
  late SceneManager manager;

  SceneCodec codec() => SceneCodec(ComponentDefinitionRegistry.core());

  setUp(() async {
    root = Directory.systemTemp.createTempSync('scene_safety_');
    store = SceneStore(root: root.path, codec: codec());
    for (final name in ['level_01', 'level_02', 'level_03']) {
      await store.writeInitialFiles(name);
    }
    manager = SceneManager(store: store);
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File sceneFile(String name) => File('${root.path}/$name.scene.json');

  List<String> manifest() =>
      ((jsonDecode(
                    readWhenFree(
                      () => File('${root.path}/scenes.json').readAsStringSync(),
                    ),
                  )
                  as Map)['scenes']
              as List)
          .cast<String>();

  group('rename', () {
    test('a case-only rename of the scene itself goes through; any other '
        'clash is refused before the store is asked', () async {
      final recording = _RecordingStore(codec: codec(), root: root.path);
      final m = SceneManager(store: recording);

      // What the Rename box checks as it is typed.
      expect(m.validateName('Level_01', ignoring: 'level_01'), isNull);
      expect(m.validateName('LEVEL_02', ignoring: 'level_01'), isNotNull);

      await m.renameScene('level_01', 'Level_01');
      expect(recording.renames, [('level_01', 'Level_01')]);

      for (final taken in ['level_02', 'LEVEL_02', 'Level_03']) {
        await expectLater(
          m.renameScene('level_01', taken),
          throwsA(isA<SceneManagerException>()),
          reason: taken,
        );
      }
      // The same name is nothing to do — never a copy onto itself.
      await m.renameScene('level_01', 'level_01');
      // A scene that is not there is refused, not "renamed".
      await expectLater(
        m.renameScene('ghost', 'phantom'),
        throwsA(isA<SceneManagerException>()),
      );
      expect(recording.renames, [('level_01', 'Level_01')]);
    });

    test('the backups follow the scene to its new name', () async {
      await store.writeBackup('level_02', '{}', keep: 3);
      await manager.renameScene('level_02', 'forest');
      expect(Directory('${store.backupsRoot}/forest').existsSync(), isTrue);
      expect(Directory('${store.backupsRoot}/level_02').existsSync(), isFalse);
      expect(store.backupsOf('forest'), hasLength(1));
    });

    test('the other scenes that name it are found, and pointed at the new '
        'name in place', () async {
      final raw = store.readRawSync('level_01')!;
      (raw['entities'] as List).add({
        'name': 'Exit',
        'components': [
          {'type': 'GoalComponent', 'nextScene': 'level_02'},
        ],
      });
      sceneFile('level_01').writeAsStringSync(store.encodeRawText(raw));

      await manager.renameScene('level_02', 'forest');
      final mentions = await manager.mentionsOf('level_02', except: 'forest');
      expect(mentions, {'level_01': 1});

      expect(
        await manager.rewriteMentions('level_02', 'forest', mentions.keys),
        1,
      );
      final after = store.readRawSync('level_01')!;
      expect(after['name'], 'level_01', reason: 'its own name is its own');
      final exit = (after['entities'] as List).last as Map;
      expect((exit['components'] as List).single['nextScene'], 'forest');
      expect(await manager.mentionsOf('level_02'), isEmpty);
    });
  });

  group('duplicate', () {
    test(
      'a copy may not take its source\'s name, in any letter case',
      () async {
        final before = sceneFile('level_01').readAsStringSync();
        for (final name in ['level_01', 'Level_01', 'LEVEL_01']) {
          await expectLater(
            manager.duplicateScene('level_01', name),
            throwsA(isA<SceneManagerException>()),
            reason: name,
          );
        }
        expect(sceneFile('level_01').readAsStringSync(), before);
        expect(manifest(), ['level_01', 'level_02', 'level_03']);
        await expectLater(
          manager.duplicateScene('ghost', 'ghost_copy'),
          throwsA(isA<SceneManagerException>()),
        );

        await manager.duplicateScene('level_01', 'level_01_copy');
        expect(manifest(), [
          'level_01',
          'level_01_copy',
          'level_02',
          'level_03',
        ]);
      },
    );
  });

  group('delete', () {
    test('goes to the trash, and comes back to its place', () async {
      final text = sceneFile('level_02').readAsStringSync();
      final deleted = await manager.deleteScene('level_02');

      expect(sceneFile('level_02').existsSync(), isFalse);
      expect(manifest(), ['level_01', 'level_03']);
      expect(File(deleted.keptAt).readAsStringSync(), text);
      expect(deleted.keptAt, startsWith(manager.trashRoot));
      expect(store.listSceneNames(), isNot(contains('level_02')));

      await deleted.restore();
      expect(sceneFile('level_02').readAsStringSync(), text);
      expect(manifest(), ['level_01', 'level_02', 'level_03']);
      expect(File(deleted.keptAt).existsSync(), isFalse);
    });

    test('a restore never replaces a scene made since', () async {
      final deleted = await manager.deleteScene('level_02');
      await store.writeInitialFiles('Level_02');
      await expectLater(
        deleted.restore(),
        throwsA(isA<SceneManagerException>()),
      );
      expect(File(deleted.keptAt).existsSync(), isTrue, reason: 'kept');
    });

    test('a scene that is not there is refused', () async {
      await expectLater(
        manager.deleteScene('ghost'),
        throwsA(isA<SceneManagerException>()),
      );
    });

    test('the project\'s own store trashes into .editor_trash', () {
      final own = SceneManager(store: SceneStore(codec: codec()));
      expect(
        own.trashRoot,
        '${Directory.current.path}/${AssetIndex.trashFolder}',
      );
    });
  });

  group('summaries', () {
    test('a scene of the wrong shape is unreadable, not a crash; a file '
        'unchanged is not read again', () {
      sceneFile('odd').writeAsStringSync('{"name": "odd", "entities": {}}');
      final odd = manager.summaryOf('odd');
      expect(odd, isNotNull);
      expect(odd!.isReadable, isFalse);

      final first = manager.summaryOf('level_01');
      expect(first!.isReadable, isTrue);
      expect(identical(manager.summaryOf('level_01'), first), isTrue);
      expect(manager.summaryOf('missing'), isNull);
    });
  });

  group('the Scenes list', () {
    late EditorPrefs prefs;
    setUp(() => prefs = EditorPrefs(store: MemorySettingsStore()));

    Future<void> pumpPanel(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(420, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScenePickerPanel(
              sceneManager: manager,
              prefs: prefs,
              onSceneSelected: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a scene file of the wrong shape is a row that says so', (
      tester,
    ) async {
      sceneFile('odd').writeAsStringSync('{"name": "odd", "entities": {}}');
      await pumpPanel(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('odd'), findsOneWidget);
      expect(find.text("Can't read this file"), findsOneWidget);
    });

    testWidgets('a deleted scene can be brought back with Undo', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('PLAY ORDER'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(find.textContaining(AssetIndex.trashFolder), findsOneWidget);
      await tester.tap(find.widgetWithText(EditorButton, 'Delete'));
      // Undo is offered once the delete — the play order too — is done.
      await pumpUntil(
        tester,
        () => find.textContaining('Deleted "level_02"').evaluate().isNotEmpty,
        what: 'the delete',
      );
      await tester.pumpAndSettle();

      expect(sceneFile('level_02').existsSync(), isFalse);
      expect(find.textContaining('Deleted "level_02"'), findsOneWidget);
      expect(find.text('level_02'), findsNothing, reason: 'its row is gone');
      await tester.tap(find.text('Undo'));
      // The list reads the scenes again once the scene is back in place.
      await pumpUntil(
        tester,
        () => find.text('level_02').evaluate().isNotEmpty,
        what: 'the scene to come back',
      );
      await tester.pumpAndSettle();

      expect(sceneFile('level_02').existsSync(), isTrue);
      expect(manifest(), ['level_01', 'level_02', 'level_03']);
      expect(find.text('level_02'), findsOneWidget);
      expect(find.textContaining('Deleted "level_02"'), findsNothing);
    });

    testWidgets('Duplicate refuses the source\'s own name as it is typed', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('PLAY ORDER'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate "level_01"'), findsOneWidget);

      // The dialog's box: the list's search field is the first.
      await tester.enterText(find.byType(TextField).last, 'Level_01');
      await tester.pump();
      expect(find.textContaining('already exists'), findsOneWidget);
    });

    testWidgets('on a Mac: Cmd+D duplicates and Backspace deletes a scene', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('PLAY ORDER'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      // Ctrl is no shortcut key on a Mac.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate "level_01"'), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('Duplicate "level_01"'), findsOneWidget);
      await tester.tap(find.widgetWithText(EditorButton, 'Cancel'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();
      expect(find.textContaining(AssetIndex.trashFolder), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}
