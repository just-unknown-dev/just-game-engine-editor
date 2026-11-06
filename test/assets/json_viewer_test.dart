// A JSON file no window of its own opens is shown as it is — pretty-printed,
// read-only, searched — while files with a window open in theirs, and a
// scene of the scenes folder opens as the scene.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/plugin/built_in_editor_module.dart';
import 'package:just_game_engine_editor/src/materials/built_in_materials_module.dart';
import 'package:just_game_engine_editor/src/assets/json_workspace.dart';
import 'package:just_game_engine_editor/src/assets/assets_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_json_view');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the system's own clean-up.
      }
    });
  });

  Future<JsonWorkspaceState> open(WidgetTester tester, String path) async {
    final scope = EditorScope(world: World()..initialize());
    addTearDown(scope.dispose);
    final key = GlobalKey<JsonWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonWorkspace(
            key: key,
            path: path,
            index: AssetIndex(projectRoot: dir.path),
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: path,
            ),
            loadOnStart: false,
          ),
        ),
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    return state;
  }

  testWidgets('pretty-printed, read-only, searched', (tester) async {
    File('${dir.path}/hud.ui.json').writeAsStringSync(
      '{"name":"HUD","children":[{"name":"Coins"},{"name":"Time"}]}',
    );
    final state = await open(tester, 'hud.ui.json');
    expect(state.problem, isNull);
    expect(state.lines.first, '{');
    expect(state.lines, contains('  "name": "HUD",'));
    expect(find.text('Read-only'), findsOneWidget);
    expect(find.text('Open in system app'), findsOneWidget);
    expect(find.text('Save'), findsNothing, reason: 'nothing here writes it');

    state.search('name');
    await tester.pump();
    expect(state.matches, hasLength(3));
    expect(find.text('1 of 3'), findsOneWidget);
    state.step();
    expect(state.current, 1);
    state
      ..step()
      ..step();
    expect(state.current, 0, reason: 'round again past the last');
    state.step(back: true);
    expect(state.current, 2);
  });

  testWidgets('a line wider than the window scrolls sideways, whole', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(700, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final blob = List.filled(400, 'abcdefghij').join();
    File(
      '${dir.path}/blob.json',
    ).writeAsStringSync('{"image":"${blob}END","name":"short"}');
    final state = await open(tester, 'blob.json');
    // The lines' list sits in it: not the header's or the search box's.
    final across = find.ancestor(
      of: find.byType(ListView),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
      ),
    );
    expect(across, findsOneWidget, reason: 'the lines scroll sideways');
    final position = tester.state<ScrollableState>(across).position;
    expect(position.maxScrollExtent, greaterThan(4000 * 5));
    // The long line is laid out whole, not clipped at the window's edge.
    final line = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('END'),
    );
    expect(tester.getSize(line).width, greaterThan(4000 * 5));

    // A match past the edge is scrolled to.
    state.search('END');
    await tester.pump();
    expect(position.pixels, greaterThan(0));
  });

  testWidgets('a file that is not JSON: as written, with why', (tester) async {
    File('${dir.path}/broken.json').writeAsStringSync('{"a": 1,');
    final state = await open(tester, 'broken.json');
    expect(state.problem, startsWith('Not valid JSON'));
    expect(state.lines, ['{"a": 1,']);
  });

  test('each file in its own window; the rest in the viewer', () {
    final scope = EditorScope(
      world: World()..initialize(),
      builtIns: const [BuiltInEditorModule.new, BuiltInMaterialsModule.make],
    );
    addTearDown(scope.dispose);
    String? opened(String path) {
      scope.openInWorkspace(path);
      return scope.activeWorkspace.value?.definition.id;
    }

    expect(opened('assets/ui/hud.ui.json'), 'json', reason: 'no UI editor');
    expect(opened('assets/fx/rock.material2d.json'), 'materials.material2D');
    expect(opened('assets/fx/stone.material.json'), 'materials.material');
    expect(opened('assets/maps/grass.tileset.json'), 'tileset');
  });

  test('a scene of the scenes folder is opened by its name', () {
    const root = 'D:/game/assets/scenes';
    expect(
      AssetsDock.sceneNameAt(
        r'D:\game\assets\scenes\level_01.scene.json',
        root,
      ),
      'level_01',
    );
    expect(
      AssetsDock.sceneNameAt('D:/game/assets/old/level_01.scene.json', root),
      isNull,
      reason: 'not in the scenes folder: no name to open it by',
    );
    expect(
      AssetsDock.sceneNameAt('D:/game/assets/scenes/scenes.json', root),
      isNull,
    );
  });
}
