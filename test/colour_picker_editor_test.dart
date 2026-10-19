// The colour picker as the editor uses it: what a shape's paint becomes in
// the picker and back, a colour shown live and then recorded as one step,
// and palettes kept with the project.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_colours/just_colours.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'support/test_scope.dart';
import 'package:just_editor_core/host.dart';

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);

class _Merging extends EditorCommand {
  @override
  String get label => 'Change Fill';

  @override
  void redo() {}

  @override
  void undo() {}

  @override
  bool mergeWith(EditorCommand next) => next is _Merging;
}

void main() {
  group('paint ↔ picker', () {
    test('a sweep keeps its angles; tint and blend mode come back', () {
      const style = jge.ShapePaintStyle(
        color: Color(0xFF808080),
        blendMode: BlendMode.multiply,
        gradient: jge.ShapeGradient.sweep(
          colors: [_red, _blue],
          startAngle: math.pi / 2,
          endAngle: math.pi,
        ),
      );
      final sel = shapePaintStyleToSelection(style);
      expect(sel.tint, const Color(0xFF808080));
      expect(sel.color, _red);
      expect(sel.gradient.startAngle, closeTo(90, 1e-9));

      final back = selectionToShapePaintStyle(sel, blendMode: style.blendMode);
      expect(back.color, style.color);
      expect(back.blendMode, BlendMode.multiply);
      expect(back.gradient!.startAngle, closeTo(math.pi / 2, 1e-9));
      expect(back.gradient!.endAngle, closeTo(math.pi, 1e-9));
    });

    test('a gradient pointing up reads as 270°, not a clamped -90°', () {
      const style = jge.ShapePaintStyle(
        gradient: jge.ShapeGradient.linear(
          colors: [_red, _blue],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      );
      expect(shapePaintStyleToSelection(style).gradient.angle, closeTo(270, 1e-9));
    });

    test('a solid colour is drawn without a tint left over', () {
      final s = selectionToShapePaintStyle(
        const ColourSelection(color: _red, tint: _blue),
      );
      expect(s.color, _red);
      expect(s.gradient, isNull);
    });
  });

  group('LivePreview', () {
    test('shows unrecorded, holds autosave, a save puts it back', () {
      final scope = testScope();
      var value = 1;
      final preview = LivePreview(
        read: () => value,
        write: (v) => value = v! as int,
        scope: scope,
      );
      preview.show(2);
      expect(value, 2);
      expect(scope.isAuthoredStateHeld, isTrue);
      expect(scope.history.canUndo.value, isFalse);

      scope.restoreAuthoredState();
      expect(value, 1);
      expect(scope.isAuthoredStateHeld, isFalse);

      preview.show(3);
      preview.restore();
      expect(value, 1);
      expect(scope.authoredStateGuards, isEmpty);
    });

    test('what is kept after a preview is a step of its own', () {
      final scope = testScope();
      final preview = LivePreview(read: () => 0, write: (_) {}, scope: scope);
      scope.history.push(_Merging());
      preview.show(1);
      preview.restore();
      scope.history.push(_Merging());
      expect(scope.history.undoEntries, hasLength(2));
    });
  });

  test('palettes are kept in the project file and read back', () {
    final dir = Directory.systemTemp.createTempSync('palettes');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/project/palettes.json';

    final first = ProjectColours(path: path)..load();
    addTearDown(first.dispose);
    first.library.savePalette(
      const ColourPalette(id: '', name: 'Mine', colors: [_red]),
    );
    expect(File(path).existsSync(), isTrue);

    final again = ProjectColours(path: path)..load();
    addTearDown(again.dispose);
    expect(again.library.palettes.single.name, 'Mine');
    expect(again.error, isNull);
  });

  testWidgets('a colour row previews live and records only what is kept', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final previews = <jge.ShapePaintStyle>[];
    final changes = <jge.ShapePaintStyle>[];
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: ColorEditorRow(
              label: 'Fill',
              paintStyle: const jge.ShapePaintStyle(color: _red),
              onChanged: changes.add,
              onPreview: previews.add,
              onPreviewEnd: () => ended++,
            ),
          ),
        ),
      ),
    );

    final open = find.byIcon(Icons.colorize_rounded);
    await tester.tap(open);
    await tester.pumpAndSettle();
    final panel = find.byType(ColourPickerPanel);
    expect(panel, findsOneWidget);
    expect(Theme.of(tester.element(panel)).brightness, Brightness.dark);

    await tester.enterText(find.byType(TextField).first, '00ff00');
    await tester.pump();
    expect(previews.last.color.toARGB32(), 0xFF00FF00);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(ended, 1);
    expect(changes, isEmpty);

    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '0000ff');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(ended, 2);
    expect(changes.single.color, _blue);
  });
}
