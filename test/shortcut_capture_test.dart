// Changing a command's keys: a command that runs even while typing is not
// given a key that types, and moving from one row to the next keeps the
// editor listening.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';

import 'support/test_scope.dart';

void main() {
  Future<EditorScope> keyboardPage(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scope = testScope();
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
    await tester.tap(find.text('Keyboard').first);
    await tester.pumpAndSettle();
    return scope;
  }

  Future<void> edit(WidgetTester tester, String commandId) async {
    final row = find.byKey(ValueKey('shortcut:$commandId'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: row, matching: find.byIcon(Icons.edit_outlined)),
    );
    await tester.pump();
  }

  testWidgets('Save is not given a plain letter', (tester) async {
    final scope = await keyboardPage(tester);
    await edit(tester, 'editor.save');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(find.textContaining('would stop it being typed'), findsOneWidget);
    expect(scope.prefs.settings.value.shortcuts, isEmpty);

    // With Ctrl it is taken.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.shortcuts['editor.save'], ['Ctrl+K']);
  });

  testWidgets('nor Shift and a letter, which types a capital', (tester) async {
    final scope = await keyboardPage(tester);
    await edit(tester, 'editor.save');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining('would stop it being typed'), findsOneWidget);
    expect(scope.prefs.settings.value.shortcuts, isEmpty);
  });

  testWidgets('on a Mac, Cmd is recorded — and saved as Ctrl, as on every OS', (
    tester,
  ) async {
    final scope = await keyboardPage(tester);
    await edit(tester, 'editor.save');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.shortcuts['editor.save'], ['Ctrl+K']);
    expect(scope.commands.shortcutOf('editor.save'), 'Cmd+K');
    expect(find.text('Cmd+K'), findsWidgets, reason: 'the row shows Cmd');

    // Cmd+S again is the key it came with: no longer a change.
    await edit(tester, 'editor.save');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.shortcuts, isEmpty);
    expect(scope.commands.shortcutOf('editor.save'), 'Cmd+S');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
    'on a Mac, Ctrl and Option are refused where they would be dropped or '
    'type',
    (tester) async {
      final scope = await keyboardPage(tester);
      await edit(tester, 'editor.save');
      // Ctrl: no binding is made with it on a Mac.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('Shortcuts are made with Cmd'), findsOne);
      // Option and a letter types a character there (Option+S is ß).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(find.textContaining('would stop it being typed'), findsOne);
      expect(scope.prefs.settings.value.shortcuts, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets('from one row straight to another, the editor still listens', (
    tester,
  ) async {
    final scope = await keyboardPage(tester);
    await edit(tester, 'designer.hide');
    expect(scope.chrome.capturingKeys, isTrue);
    await edit(tester, 'designer.lock');
    await tester.pump();
    expect(scope.chrome.capturingKeys, isTrue, reason: 'the second listens');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(scope.chrome.capturingKeys, isFalse);
  });
}
