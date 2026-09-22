// The theme editor: tokens on the left, what they look like on the right,
// and a save that restyles what is already on screen.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/theme/theme_dock.dart';

void main() {
  setUpAll(registerCoreCodecs);

  late Directory project;
  final saved = <String>[];

  String themePath() => '${project.path}/assets/ui/default.uitheme.json';

  void writeTheme(UiTheme theme) {
    File(themePath())
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(theme.toJson()),
      );
  }

  setUp(() {
    saved.clear();
    project = Directory.systemTemp.createTempSync('theme_dock_test');
    addTearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });
  });

  Future<void> pumpDock(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeDock(
            root: project.path,
            onSaved: (path) async => saved.add(path),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no theme in the project, it offers to make one', (
    tester,
  ) async {
    await pumpDock(tester);

    expect(find.text('No theme yet'), findsOneWidget);
    expect(find.text('Make one'), findsOneWidget);
  });

  testWidgets('making one writes a file and opens it', (tester) async {
    await pumpDock(tester);

    await tester.tap(find.text('Make one'));
    await tester.pump();

    expect(File(themePath()).existsSync(), isTrue);
    expect(find.text('primary'), findsOneWidget);
  });

  group('over a project with a theme', () {
    setUp(() {
      writeTheme(
        UiTheme.fallback.copyWith(
          name: 'default',
          palette: const UiPalette(primary: Color(0xFF112233)),
          radius: 10,
        ),
      );
    });

    testWidgets('it opens the theme, tokens beside a live gallery', (
      tester,
    ) async {
      await pumpDock(tester);

      // Every colour role is editable…
      for (final role in UiPalette.roles) {
        expect(find.text(role), findsOneWidget, reason: role);
      }
      // …and the gallery is built from the widgets a canvas is built from.
      expect(find.text('The quick brown fox'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('nothing to save until something changes', (tester) async {
      await pumpDock(tester);

      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('a changed corner is written and the canvases are told', (
      tester,
    ) async {
      await pumpDock(tester);

      // Type a new corner radius into its field.
      final corner = find.descendant(
        of: find.ancestor(
          of: find.text('Corner'),
          matching: find.byType(ScrubFieldRow),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(corner, '18');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('Save'), findsOneWidget, reason: 'it changed');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final onDisk = UiTheme.parse(File(themePath()).readAsStringSync());
      expect(onDisk.radius, 18);
      expect(onDisk.name, 'default');
      // The canvases using it are restyled without reopening the scene.
      expect(saved, ['assets/ui/default.uitheme.json']);
      expect(find.textContaining('Saved assets/ui'), findsOneWidget);
    });

    testWidgets('the gallery is drawn in the theme\'s own colours', (
      tester,
    ) async {
      await pumpDock(tester);

      final button = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Play'),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(button.onPressed, isNotNull);
      // The surface behind the gallery is the theme's surface.
      final material = tester.widgetList<Material>(find.byType(Material));
      expect(
        material.any((m) => m.color == UiTheme.fallback.palette.surface),
        isTrue,
      );
    });
  });
}
