// Pointing at a tag's or a layer's row rings its things in the level; the
// ring goes when the row does, though no pointer ever left it.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/tags/tags_dock.dart';

void main() {
  late Directory root;
  late EditorScope scope;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dock_highlight_');
    Directory('${root.path}/assets/scenes').createSync(recursive: true);
    scope = testScope(scenesRoot: '${root.path}/assets/scenes');
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets("a tag's ring goes with the dock it was pointed at in", (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    scope.tags.create('coin');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: TagsDock(scope: scope),
          ),
        ),
      ),
    );
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('coin').first));
    await tester.pump();
    expect(scope.highlightedTag.value, 'coin');

    // F2 shuts the panel under the pointer: no exit is ever heard.
    await tester.pumpWidget(const SizedBox());
    expect(scope.highlightedTag.value, isNull);
  });
}
