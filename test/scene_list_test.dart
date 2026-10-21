// The Scenes list: every scene, in the game's play order, to open, find,
// sort, reorder and look after — with the keys as well as the mouse.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/prefs/recent_scenes.dart';
import 'package:just_game_engine_editor/src/ui/panels/scene_row.dart';

import 'support/memory_settings_store.dart';
import 'support/real_io.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_manager.dart';
import 'package:just_game_engine_editor/src/ui/dialogs/create_scene_overlay.dart';
import 'package:just_game_engine_editor/src/ui/panels/scene_picker_panel.dart';

/// Counts the play-order writes it is asked for, and those still under way:
/// the list is done with an action that rewrites `scenes.json` once none
/// is (it shows the new order straight away, and reads it back after).
class _TrackedManager extends SceneManager {
  _TrackedManager({required super.store, super.protectedSceneNames});

  int writes = 0;
  int writing = 0;

  @override
  Future<void> setPlayOrder(List<String> names) async {
    writes++;
    writing++;
    try {
      await super.setPlayOrder(names);
    } finally {
      writing--;
    }
  }
}

void main() {
  late Directory root;
  late SceneStore store;
  late _TrackedManager manager;
  late EditorPrefs prefs;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('scene_list_');
    store = SceneStore(
      root: root.path,
      codec: SceneCodec(ComponentDefinitionRegistry.core()),
    );
    for (final name in ['level_01', 'level_02', 'level_03']) {
      await store.writeInitialFiles(name);
    }
    manager = _TrackedManager(store: store, protectedSceneNames: {'level_03'});
    prefs = EditorPrefs(store: MemorySettingsStore());
  });
  tearDown(() => deleteWhenFree(root));

  // A file just written can be held for a moment by something else on
  // Windows (a virus scanner): read again shortly rather than fail.
  List<String> manifest() =>
      ((jsonDecode(
                    readWhenFree(
                      () => File('${root.path}/scenes.json').readAsStringSync(),
                    ),
                  )
                  as Map)['scenes']
              as List)
          .cast<String>();

  group('the store', () {
    test('the play order is the manifest, and writing it rewrites '
        'scenes.json', () async {
      expect(store.playOrder(), ['level_01', 'level_02', 'level_03']);
      await store.writePlayOrder(['level_03', 'level_01']);
      expect(manifest(), ['level_03', 'level_01']);
      // Left out, but still there: after the play order.
      expect(store.listSceneNames(), ['level_03', 'level_01', 'level_02']);
    });

    test(
      'a summary tells the mode, the entities and when it was saved',
      () async {
        final summary = store.summaryOf('level_01');
        final file = File('${root.path}/level_01.scene.json');
        final entities =
            ((jsonDecode(file.readAsStringSync()) as Map)['entities'] as List)
                .length;
        expect(summary!.mode, SceneMode.twoD);
        expect(summary.entityCount, entities);
        expect(summary.savedAt, file.lastModifiedSync());
        expect(summary.isReadable, isTrue);

        expect(store.summaryOf('missing'), isNull);
        File('${root.path}/broken.scene.json').writeAsStringSync('{ not json');
        final broken = store.summaryOf('broken');
        expect(broken!.isReadable, isFalse);
        expect(broken.entityCount, isNull);
      },
    );

    test('the play order takes scenes that are there, once each', () async {
      expect(
        () => manager.setPlayOrder(['level_01', 'nope']),
        throwsA(isA<SceneManagerException>()),
      );
      expect(
        () => manager.setPlayOrder(['level_01', 'level_01']),
        throwsA(isA<SceneManagerException>()),
      );
      await manager.setPlayOrder(['level_02', 'level_01', 'level_03']);
      expect(manager.playOrder(), ['level_02', 'level_01', 'level_03']);
    });
  });

  test('a new scene is offered the name after the last one', () {
    String next(List<String> names) => CreateSceneOverlay.suggestName(names);
    expect(next([]), 'level_01');
    expect(next(['level_01', 'level_03']), 'level_04');
    expect(next(['level_02', 'level_01']), 'level_03', reason: 'taken: on');
    expect(next(['a_9']), 'a_10');
    expect(next(['cave']), 'cave_2');
    // After the last in the play order — where the new one goes — not
    // after a scene the game does not list.
    expect(
      CreateSceneOverlay.suggestName([
        'level_01',
        'level_02',
        'zz_draft',
      ], after: 'level_02'),
      'level_03',
    );
  });

  group('recent scenes', () {
    test('the newest first, a few of them', () async {
      for (var i = 0; i < 10; i++) {
        await RecentScenes.touch(prefs, 's$i');
      }
      await RecentScenes.touch(prefs, 's5');
      final recent = RecentScenes.of(prefs);
      expect(recent.first, 's5');
      expect(recent, hasLength(RecentScenes.keep));
      expect(RecentScenes.of(prefs, existing: ['s5', 's9']), ['s5', 's9']);
    });

    test('a rename follows, and so does the last scene', () async {
      await RecentScenes.touch(prefs, 'a');
      await RecentScenes.touch(prefs, 'b');
      await prefs.set(RecentScenes.lastScene, 'a');
      await RecentScenes.rename(prefs, 'a', 'z');
      expect(RecentScenes.of(prefs), ['b', 'z']);
      expect(prefs.get(RecentScenes.lastScene), 'z');

      await RecentScenes.forget(prefs, 'z');
      expect(RecentScenes.of(prefs), ['b']);
      expect(prefs.get(RecentScenes.lastScene), '');
    });
  });

  testWidgets('a focused panel keeps the keys it claims, and only while '
      'focused', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorKeyClaim(
          claims: (e) => e.logicalKey == LogicalKeyboardKey.f2,
          child: Focus(focusNode: node, child: const SizedBox()),
        ),
      ),
    );
    KeyDownEvent down(LogicalKeyboardKey key, PhysicalKeyboardKey at) =>
        KeyDownEvent(
          physicalKey: at,
          logicalKey: key,
          timeStamp: Duration.zero,
        );
    final f2 = down(LogicalKeyboardKey.f2, PhysicalKeyboardKey.f2);
    final f3 = down(LogicalKeyboardKey.f3, PhysicalKeyboardKey.f3);

    expect(EditorKeyClaim.focusedClaims(f2), isFalse, reason: 'not focused');
    node.requestFocus();
    await tester.pump();
    expect(EditorKeyClaim.focusedClaims(f2), isTrue);
    expect(EditorKeyClaim.focusedClaims(f3), isFalse);
  });

  group('the panel', () {
    Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

    /// Does [action], then waits until the play order it writes is
    /// written — real file writes, a step of them per pump — and the list
    /// has read it back.
    Future<void> writing(
      WidgetTester tester,
      Future<void> Function() action,
    ) async {
      final before = manager.writes;
      await action();
      await pumpUntil(
        tester,
        () => manager.writes > before && manager.writing == 0,
        what: 'the play order to be written',
      );
      await tester.pumpAndSettle();
    }

    Future<List<String>> pumpPanel(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(420, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScenePickerPanel(
              sceneManager: manager,
              prefs: prefs,
              onSceneSelected: (name) async => opened.add(name),
            ),
          ),
        ),
      );
      await settle(tester);
      return opened;
    }

    double top(WidgetTester tester, String name) =>
        tester.getTopLeft(find.text(name)).dy;

    Future<void> focusList(WidgetTester tester) async {
      await tester.tap(find.text('PLAY ORDER'));
      await tester.pump();
    }

    Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    testWidgets('rows in play order: numbered, the first marked START, '
        'each with what is in it', (tester) async {
      await pumpPanel(tester);
      expect(top(tester, 'level_01'), lessThan(top(tester, 'level_02')));
      expect(top(tester, 'level_02'), lessThan(top(tester, 'level_03')));
      for (final n in ['1', '2', '3']) {
        expect(
          find.descendant(of: find.byType(SceneRow), matching: find.text(n)),
          findsOneWidget,
        );
      }
      expect(find.text('START'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('START'), matching: find.byType(SceneRow)),
        findsOneWidget,
      );
      final start = tester.widget<SceneRow>(
        find.ancestor(of: find.text('START'), matching: find.byType(SceneRow)),
      );
      expect(start.name, 'level_01');
      expect(find.text('2D'), findsNWidgets(3));
      expect(find.textContaining('entities · saved'), findsNWidgets(3));
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    });

    testWidgets('the search narrows the list, and Enter opens the first '
        'match', (tester) async {
      final opened = await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), '02');
      await tester.pump();
      expect(find.text('level_01'), findsNothing);
      expect(find.text('level_02'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(opened, ['level_02']);
    });

    testWidgets('nothing matching says so, and the search clears', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.text('No scene matches "zzz"'), findsOneWidget);
      await tester.tap(find.text('Clear the search'));
      await tester.pump();
      expect(find.byType(SceneRow), findsNWidgets(3));
    });

    testWidgets('recently opened: a group at the top, and a sort that is '
        'remembered', (tester) async {
      await RecentScenes.touch(prefs, 'level_02');
      await pumpPanel(tester);
      expect(find.text('RECENT'), findsOneWidget);
      expect(find.byIcon(Icons.history_rounded), findsOneWidget);

      await tester.tap(find.byTooltip('Sort: Play order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recently opened'));
      await tester.pumpAndSettle();
      expect(prefs.get(ScenePickerPanel.sortPref), SceneSort.recent.name);
      expect(find.text('RECENT'), findsNothing, reason: 'the list is that');
      expect(find.text('RECENTLY OPENED'), findsOneWidget);
      expect(top(tester, 'level_02'), lessThan(top(tester, 'level_01')));
    });

    testWidgets('keys: arrows move, Enter opens, F2 renames, Delete asks — '
        'and not for a scene the game uses', (tester) async {
      final opened = await pumpPanel(tester);
      await focusList(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.enter);
      expect(opened, ['level_02']);

      await key(tester, LogicalKeyboardKey.f2);
      expect(find.text('Rename "level_02"'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await key(tester, LogicalKeyboardKey.delete);
      expect(find.text('Delete scene?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await key(tester, LogicalKeyboardKey.end);
      await key(tester, LogicalKeyboardKey.f2);
      expect(find.textContaining('Rename'), findsNothing, reason: 'guarded');
      await key(tester, LogicalKeyboardKey.delete);
      expect(find.text('Delete scene?'), findsNothing);
    });

    testWidgets('Alt+↓ moves a scene later in the play order, and '
        'scenes.json follows', (tester) async {
      await pumpPanel(tester);
      await focusList(tester);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await writing(tester, () async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      });
      expect(manifest(), ['level_02', 'level_01', 'level_03']);
    });

    testWidgets('the menu starts the game elsewhere, leaves a scene out and '
        'puts it back', (tester) async {
      await pumpPanel(tester);
      Future<void> menu(String name, String item) async {
        await tester.tap(find.text(name), buttons: kSecondaryButton);
        await tester.pumpAndSettle();
        await writing(tester, () => tester.tap(find.text(item)));
      }

      await menu('level_02', 'Start the game here');
      expect(manifest(), ['level_02', 'level_01', 'level_03']);
      expect(
        tester
            .widget<SceneRow>(
              find.ancestor(
                of: find.text('START'),
                matching: find.byType(SceneRow),
              ),
            )
            .name,
        'level_02',
      );

      await menu('level_01', 'Leave out of the game');
      expect(manifest(), ['level_02', 'level_03']);
      expect(find.text('–'), findsOneWidget);

      await menu('level_01', 'Add to the play order');
      expect(manifest(), ['level_02', 'level_03', 'level_01']);
    });

    testWidgets('New scene asks in a dialog, and opens what it made', (
      tester,
    ) async {
      final opened = await pumpPanel(tester);
      await tester.tap(find.byTooltip('New scene'));
      await tester.pumpAndSettle();
      expect(find.text('New scene'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'level_04',
      );
      await tester.tap(find.text('Create scene'));
      // Real file writes (each written beside its file, flushed and moved
      // over it), and then the new scene is opened.
      await pumpUntil(
        tester,
        () => opened.isNotEmpty,
        what: 'the new scene to be made and opened',
      );
      await tester.pumpAndSettle();
      expect(opened, ['level_04']);
      expect(manifest().last, 'level_04');
    });
  });
}
