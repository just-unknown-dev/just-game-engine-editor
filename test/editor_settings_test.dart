// The editor's settings beyond its look: each does what its row says —
// saving and backups, keys, snapping, the viewport's drawing, the play-test,
// the Console and messages — and all of them travel as one file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/overlay/chrome/editor_chrome.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_controls.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/shortcut_row.dart';

import 'support/test_scope.dart';

void main() {
  const defaults = OverlayUiSettings.defaults();
  tearDown(() {
    EditorMetrics.apply(defaults);
    ViewportLook.apply(defaults);
  });

  /// Every new setting moved off its default.
  final moved = defaults.copyWith(
    autosaveMinutes: 5,
    autosaveMode: AutosaveMode.save,
    backupsToKeep: 3,
    reopenLastScene: false,
    reopenDesigner: false,
    shortcuts: {
      'designer.hide': ['Ctrl+Shift+H'],
      'editor.settings': ['Ctrl+,'],
      'designer.lock': [],
    },
    targetFps: 144,
    rotationStep: 45,
    scaleStep: 0.25,
    nudgeDistance: 8,
    smartSnap: false,
    moveStep: 8,
    gridColour: const Color(0xFF5AC8FA),
    gridOpacity: 2,
    backdrop: const Color(0xFF0E1726),
    gizmoScale: 1.5,
    selectionColour: const Color(0xFFFFD60A),
    gizmos: const GizmoSettings(
      editor: GizmoModeSettings(shown: false),
      designer: GizmoModeSettings(
        shown: true,
        hidden: {GizmoKind.colliders, GizmoKind.icons},
      ),
      play: GizmoModeSettings(shown: true, hidden: {GizmoKind.aids}),
    ),
    pauseOnError: true,
    hideChromeWhilePlaying: true,
    undoLimit: 50,
    confirmDelete: true,
    closePrompt: ClosePrompt.always,
    consoleMaxEntries: 500,
    consoleHiddenLevels: ['info'],
    consoleTimestamps: false,
    messageLevel: MessageLevel.errors,
  );

  group('stored and carried', () {
    test('every setting comes back as it was stored', () {
      final back = OverlaySettingsStore.decode(
        OverlaySettingsStore.encode(moved),
      );
      expect(back, moved);
      expect(back.shortcuts['designer.lock'], isEmpty, reason: 'no key');
    });

    test('a value from outside the range is brought into it', () {
      final back = OverlaySettingsStore.decode({
        ...OverlaySettingsStore.encode(defaults),
        'editor.edit.undoLimit': '5',
        'editor.edit.rotationStep': '720',
        'editor.keys.shortcuts': 'not json',
      });
      expect(back.undoLimit, OverlayUiSettings.undoLimitRange.min);
      expect(back.rotationStep, OverlayUiSettings.rotationStepRange.max);
      expect(back.shortcuts, isEmpty);
    });

    test('an export imports as it was; junk does not import', () {
      final text = OverlaySettingsStore.export(moved);
      expect(OverlaySettingsStore.import(text, defaults), moved);
      expect(OverlaySettingsStore.import('{"a": 1}', defaults), isNull);
      expect(OverlaySettingsStore.import('nonsense', defaults), isNull);
    });

    test('what an import leaves out keeps its current value', () {
      final text = jsonEncode({
        'format': OverlaySettingsStore.exportFormat,
        'version': 1,
        'settings': {'editor.edit.undoLimit': '80'},
      });
      final imported = OverlaySettingsStore.import(text, moved)!;
      expect(imported.undoLimit, 80);
      expect(imported.targetFps, moved.targetFps);
    });
  });

  group('keys', () {
    test('every built-in chord reads back as the same keys', () {
      for (final b in BuiltInBindings.of(const DesignerConfig())) {
        final back = KeyBinding.parse(b.shortcut, b.commandId);
        expect(back, isNotNull, reason: b.shortcut);
        expect(back!.key, b.key, reason: b.shortcut);
        expect(
          (back.control, back.shift, back.alt),
          (b.control, b.shift, b.alt),
          reason: b.shortcut,
        );
      }
      expect(KeyBinding.parse('Ctrl+,', 'x')!.key, LogicalKeyboardKey.comma);
      expect(KeyBinding.parse('Ctrl+Nothing', 'x'), isNull);
    });

    test('changed keys lay over the built ones, and come off again', () {
      final registry = CommandRegistry()
        ..bindAll(BuiltInBindings.of(const DesignerConfig()))
        ..markBuilt();
      registry.applyShortcuts({
        'designer.hide': ['Ctrl+Shift+H'],
      });
      expect(registry.bindingsFor('designer.hide').map((b) => b.shortcut), [
        'Ctrl+Shift+H',
      ]);
      registry.applyShortcuts(const {});
      expect(registry.bindingsFor('designer.hide').map((b) => b.shortcut), [
        'H',
      ]);
    });

    test('the scope keeps changed keys through a rebuild', () {
      final scope = testScope();
      scope.prefs.settings.value = defaults.copyWith(
        shortcuts: {
          'designer.hide': ['Ctrl+Shift+H'],
        },
      );
      scope.reload();
      expect(
        scope.commands.bindingsFor('designer.hide').single.shortcut,
        'Ctrl+Shift+H',
      );
    });

    testWidgets('a command takes a new chord from the Keyboard page', (
      tester,
    ) async {
      final scope = testScope();
      await _pumpDialog(tester, scope);
      await tester.tap(find.text('Keyboard').first);
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('shortcut:designer.hide'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      );
      await tester.pump();
      expect(scope.chrome.capturingKeys, isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(scope.prefs.settings.value.shortcuts['designer.hide'], ['Ctrl+J']);
      expect(
        scope.commands.bindingsFor('designer.hide').single.shortcut,
        'Ctrl+J',
      );
      expect(scope.chrome.capturingKeys, isFalse);
    });

    testWidgets('a chord another command has is asked about, not taken', (
      tester,
    ) async {
      final scope = testScope();
      await _pumpDialog(tester, scope);
      await tester.tap(find.text('Keyboard').first);
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('shortcut:designer.hide'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      );
      await tester.pump();
      // L locks.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(scope.prefs.settings.value.shortcuts, isEmpty);
      expect(find.text('Use it anyway'), findsOneWidget);

      await tester.tap(find.text('Use it anyway'));
      await tester.pumpAndSettle();
      final shortcuts = scope.prefs.settings.value.shortcuts;
      expect(shortcuts['designer.hide'], ['L']);
      expect(shortcuts['designer.lock'], isEmpty, reason: 'gave it up');
    });

    testWidgets('Esc while listening cancels, and leaves the dialog open', (
      tester,
    ) async {
      final scope = testScope();
      await _pumpDialog(tester, scope);
      await tester.tap(find.text('Keyboard').first);
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('shortcut:designer.hide'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(scope.chrome.capturingKeys, isFalse);
      expect(scope.prefs.settings.value.shortcuts, isEmpty);
      expect(find.byType(ShortcutRow), findsWidgets);
    });
  });

  group('the settings dialog', () {
    testWidgets('the new pages are there, with their settings', (tester) async {
      final scope = testScope();
      await _pumpDialog(tester, scope);
      for (final (page, rows) in [
        ('Editing', ['Undo steps', 'Confirm deletes']),
        ('Snapping', ['Snapping', 'Move step', 'Rotation step', 'Smart snap']),
        ('Saving', ['Autosave', 'Backups kept', 'Reopen the last scene']),
        ('Play-testing', ['Pause on error', 'Step aside while playing']),
        ('Console & messages', ['Lines kept', 'Show times', 'Messages']),
        ('Viewport', ['Grid colour', 'Backdrop', 'Handle size']),
        ('Performance', ['Target frame rate']),
      ]) {
        await tester.tap(find.text(page).first);
        await tester.pumpAndSettle();
        for (final row in rows) {
          expect(find.text(row), findsWidgets, reason: '$page: $row');
        }
      }
    });

    testWidgets('a toggle that starts on resets to on', (tester) async {
      final scope = testScope();
      await _pumpDialog(tester, scope);
      await tester.tap(find.text('Saving').first);
      await tester.pumpAndSettle();
      final row = find.ancestor(
        of: find.text('Reopen the last scene'),
        matching: find.byType(SettingRow),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(EditorToggle)),
      );
      await tester.pumpAndSettle();
      expect(scope.prefs.settings.value.reopenLastScene, isFalse);
      expect(find.text('Reset page'), findsOneWidget);
      await tester.tap(find.text('Reset page'));
      await tester.pumpAndSettle();
      expect(scope.prefs.settings.value.reopenLastScene, isTrue);
    });
  });

  group('the services follow them', () {
    test('undo steps: fewer drops the oldest at once', () {
      final history = EditorHistory();
      for (var i = 0; i < 10; i++) {
        history.push(
          CallbackCommand(label: 'step $i', onRedo: () {}, onUndo: () {}),
        );
      }
      history.capacity = 4;
      expect(history.undoEntries, hasLength(4));
      expect(history.undoEntries.first.label, 'step 6');
    });

    test('the scope takes undo steps, log lines and snap steps', () {
      final scope = testScope();
      scope.prefs.settings.value = moved;
      expect(scope.history.capacity, 50);
      expect(scope.log.maxEntries, 500);
      expect(scope.sceneState.scaleStep, 0.25);
      expect(scope.sceneState.rotationStep, closeTo(0.785398, 1e-5));
    });

    test('fewer log lines keeps the newest; errors are heard', () {
      final log = EditorLogService();
      addTearDown(log.dispose);
      final heard = <String>[];
      final stop = log.onError((e) => heard.add(e.message));
      for (var i = 0; i < 20; i++) {
        log.log('line $i', mirrorToDebugger: false);
      }
      log.log('broke', level: DebuggerLogLevel.error, mirrorToDebugger: false);
      log.maxEntries = 5;
      stop();
      log.log('again', level: DebuggerLogLevel.error, mirrorToDebugger: false);
      expect(heard, ['broke']);
      expect(log.maxEntries, 5);
    });

    testWidgets('quieter messages: errors only lets an error through', (
      tester,
    ) async {
      EditorMetrics.apply(defaults.copyWith(messageLevel: MessageLevel.errors));
      final c = EditorSnackBarController();
      addTearDown(c.dispose);
      c.showSnackBar(const EditorSnackBarEntry(message: 'saved'));
      c.showSnackBar(
        const EditorSnackBarEntry(
          message: 'careful',
          type: EditorSnackBarType.warning,
        ),
      );
      c.showSnackBar(
        const EditorSnackBarEntry(
          message: 'broke',
          type: EditorSnackBarType.error,
        ),
      );
      final progress = StreamController<EditorSnackBarStep>();
      c.showSnackBar(
        EditorSnackBarEntry(
          message: 'building',
          progressStream: progress.stream,
        ),
      );
      expect(c.visible.map((s) => s.entry.message), ['broke', 'building']);
      await progress.close();
      await tester.pump(const Duration(seconds: 10));
    });

    test('snapped scale and turn move in the settings\' steps', () {
      final scope = testScope();
      scope.prefs.settings.value = defaults.copyWith(
        scaleStep: 0.5,
        rotationStep: 90,
      );
      final state = scope.sceneState;
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Box');
      state.setScale(e, const Offset(1.3, 0.1));
      final t = e.getComponent<TransformComponent>()!;
      expect(t.scale.x, 1.5);
      expect(t.scale.y, 0.5, reason: 'never snapped to nothing');
      expect(state.snapRotation(1.2), closeTo(1.5708, 1e-4));
      state.gridSnappingEnabled.value = false;
      expect(state.snapRotation(1.2), 1.2);
    });

    test('moving snaps in the move step, whatever the grid', () {
      final scope = testScope();
      scope.prefs.settings.value = defaults.copyWith(moveStep: 8);
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Box');
      scope.sceneState.setPosition(e, const Offset(13, 3));
      final at = e.getComponent<TransformComponent>()!.position;
      expect((at.x, at.y), (16.0, 0.0));

      // The designer's tools too, on a square grid.
      final context = ToolContext(
        world: scope.world,
        controller: LevelDesignerController(
          sceneState: scope.sceneState,
          history: scope.history,
        ),
        worldPosition: Offset.zero,
        gridSize: 32,
        snapStep: 8,
      );
      expect(context.snapPoint(const Offset(13, 3)), const Offset(16, 0));
      expect(
        ToolContext(
          world: scope.world,
          controller: LevelDesignerController(
            sceneState: scope.sceneState,
            history: scope.history,
          ),
          worldPosition: Offset.zero,
          gridSize: 32,
        ).snapPoint(const Offset(13, 3)),
        Offset.zero,
        reason: 'no step: the grid',
      );
    });

    test('the viewport look: grid colour and strength, the selection', () {
      expect(ViewportLook.gridLine(0.14).a, closeTo(0.14, 0.01));
      ViewportLook.apply(
        defaults.copyWith(
          gridColour: const Color(0xFF5AC8FA),
          gridOpacity: 2,
          selectionColour: const Color(0xFFFFD60A),
          gizmoScale: 1.5,
        ),
      );
      final line = ViewportLook.gridLine(0.14);
      expect(line.a, closeTo(0.28, 0.01));
      expect(line.b, greaterThan(line.r), reason: 'the sky colour');
      expect(ViewportLook.selection, const Color(0xFFFFD60A));
      expect(ViewportLook.designerSelection, const Color(0xFFFFD60A));
      expect(ViewportLook.gizmoScale, 1.5);
    });

    test('the frame budget is the target rate\'s', () {
      expect(defaults.frameBudgetMs, closeTo(16.67, 0.01));
      expect(
        defaults.copyWith(targetFps: 144).frameBudgetMs,
        closeTo(6.94, 0.01),
      );
    });
  });

  group('asking first', () {
    test('a delete waits for yes, when the settings want it asked', () async {
      final scope = testScope();
      final e = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Box');
      scope.sceneState.selectEntity(e);
      var answer = false;
      final asked = <String>[];
      scope.entities.confirmDelete = (what) async {
        asked.add(what);
        return answer;
      };

      // Not asked for: deleted at once.
      scope.prefs.settings.value = defaults;
      final f = scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Other');
      scope.sceneState.selectEntity(f);
      scope.entities.deleteSelection(scope.history);
      expect(f.isAlive, isFalse);
      expect(asked, isEmpty);

      scope.prefs.settings.value = defaults.copyWith(confirmDelete: true);
      scope.sceneState.selectEntity(e);
      scope.entities.deleteSelection(scope.history);
      await Future<void>.delayed(Duration.zero);
      expect(asked, ['Box']);
      expect(e.isAlive, isTrue, reason: 'no');

      answer = true;
      scope.entities.deleteSelection(scope.history);
      await Future<void>.delayed(Duration.zero);
      expect(e.isAlive, isFalse, reason: 'yes');
    });
  });

  group('backups', () {
    late Directory project;
    late EditorScope scope;
    late SceneIO io;

    setUp(() {
      project = Directory.systemTemp.createTempSync('backups_test');
      final scenes = Directory('${project.path}/assets/scenes')
        ..createSync(recursive: true);
      File('${scenes.path}/level.scene.json').writeAsStringSync(
        jsonEncode({
          'version': SceneFormat.current,
          ...EditorScene(name: 'level').toJson(),
          'entities': [
            {
              'name': 'Platform',
              'parentName': null,
              'components': [
                {
                  'type': 'TransformComponent',
                  'fields': {
                    'position': {'x': 0.0, 'y': 0.0},
                  },
                },
              ],
            },
          ],
        }),
      );
      scope = testScope(scenesRoot: scenes.path);
      io = SceneIO(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
      );
      addTearDown(() {
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
    });

    test(
      'a backup is written only when something changed, and pruned',
      () async {
        await io.open('level');
        expect(await io.backup(keep: 2), isTrue);
        expect(await io.backup(keep: 2), isFalse, reason: 'the same again');

        final platform = scope.world.findEntityByName('Platform')!;
        for (var x = 1; x <= 3; x++) {
          platform.getComponent<TransformComponent>()!.setPositionXY(
            x * 10.0,
            0,
          );
          // Names are by the millisecond.
          await Future<void>.delayed(const Duration(milliseconds: 5));
          expect(await io.backup(keep: 2), isTrue);
        }
        expect(scope.scenes.backupsOf('level'), hasLength(2));
      },
    );

    test('changes never saved are offered back; saved, they are not', () async {
      await io.open('level');
      scope.world
          .findEntityByName('Platform')!
          .getComponent<TransformComponent>()!
          .setPositionXY(64, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await io.backup(keep: 5);
      final unsaved = scope.scenes.unsavedBackupOf('level');
      expect(unsaved, isNotNull);

      // Recovered: open with the changes, and unsaved.
      final raw = await scope.scenes.readBackup(unsaved!);
      expect(await io.openFrom('level', raw!), isTrue);
      final at = scope.world
          .findEntityByName('Platform')!
          .getComponent<TransformComponent>()!
          .position;
      expect(at.x, 64);
      expect(scope.sceneState.isDirty.value, isTrue);

      // Saved: nothing left to offer.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await io.save();
      expect(scope.scenes.unsavedBackupOf('level'), isNull);
    });

    test('a backup set aside is kept, and not offered again', () async {
      await io.open('level');
      scope.world
          .findEntityByName('Platform')!
          .getComponent<TransformComponent>()!
          .setPositionXY(32, 0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await io.backup(keep: 5);
      final unsaved = scope.scenes.unsavedBackupOf('level')!;
      await scope.scenes.setAside(unsaved);
      expect(scope.scenes.unsavedBackupOf('level'), isNull);
      expect(
        Directory(
          '${scope.scenes.backupsRoot}/level',
        ).listSync().whereType<File>(),
        hasLength(1),
      );
    });
  });

  group('in the editor', () {
    late JustGameEditorPlugin plugin;

    Future<void> start(WidgetTester tester) async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await tester.runAsync(engine.initialize);
      plugin = JustGameEditorPlugin(engine: engine);
      await tester.runAsync(plugin.onInitialize);
      plugin.setVisible(true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JustGameEditorOverlay(
              plugin: plugin,
              gameChild: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> stop(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
    }

    testWidgets('stepping aside: the game has the window while it runs', (
      tester,
    ) async {
      await start(tester);
      plugin.scope.prefs.settings.value = defaults.copyWith(
        hideChromeWhilePlaying: true,
      );
      await tester.pump();
      expect(find.byType(FullEditorChrome), findsOneWidget);

      plugin.play();
      await tester.pump();
      expect(find.byType(PlayTestChrome), findsOneWidget);
      expect(find.byType(FullEditorChrome), findsNothing);

      plugin.pause();
      await tester.pump();
      expect(find.byType(FullEditorChrome), findsOneWidget, reason: 'back');
      plugin.stop();
      await tester.pump();
      await stop(tester);
    });

    testWidgets('an error logged in a play-test pauses it', (tester) async {
      await start(tester);
      plugin.scope.prefs.settings.value = defaults.copyWith(pauseOnError: true);
      plugin.play();
      await tester.pump();
      plugin.scope.log.log(
        'boom',
        level: DebuggerLogLevel.error,
        mirrorToDebugger: false,
      );
      await tester.pump();
      expect(plugin.playController.state.value, EditorPlayState.paused);
      plugin.stop();
      await tester.pump();
      await stop(tester);
    });

    testWidgets('the backdrop while authoring; the game\'s own in play', (
      tester,
    ) async {
      await start(tester);
      final rendering = plugin.engine.rendering;
      final own = rendering.backgroundColor;
      plugin.scope.prefs.settings.value = defaults.copyWith(
        backdrop: const Color(0xFF0E1726),
      );
      await tester.pump();
      expect(rendering.backgroundColor, const Color(0xFF0E1726));
      plugin.play();
      await tester.pump();
      expect(rendering.backgroundColor, own);
      plugin.stop();
      await tester.pump();
      await stop(tester);
      expect(rendering.backgroundColor, own, reason: 'given back');
    });
  });
}

Future<void> _pumpDialog(WidgetTester tester, EditorScope scope) async {
  tester.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EditorScopeProvider(
          scope: scope,
          child: EditorSettingsDialog(scope: scope, onClose: () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
