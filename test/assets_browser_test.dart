// The asset browser on screen, and an asset dropped into the level.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/assets/assets_browser.dart';

import 'support/real_io.dart';
import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/serialization/scene_manager.dart';

/// The index, counting its scans under way: a scan reads the folder, so a
/// test is done with the disk once none is — the folder is deleted after.
///
/// It does not watch the folder. A rescan the watcher asks for comes on the
/// fake clock at a moment of its own, and one that overlaps an action's own
/// rescan makes that one return before the index has caught up (scans fold
/// into one more pass): what the browser shows after an action would then
/// depend on timing. Watching is tested in just_editor_core's
/// asset_index_test; here every rescan is one an action makes.
class _Index extends AssetIndex {
  _Index({super.projectRoot});

  int scanning = 0;

  @override
  Future<void> scan() async {
    scanning++;
    try {
      await super.scan();
    } finally {
      scanning--;
    }
  }

  @override
  void startWatching() {}
}

class _Memory implements DockMemory {
  final Map<String, Object?> values = {};

  @override
  T? read<T>(String key) => values[key] is T ? values[key] as T : null;

  @override
  void write(String key, Object? value) => values[key] = value;
}

// More things to do with a folder than its row in the tree has room for.
class _FolderModule extends EditorModule {
  final ran = <String>[];

  @override
  String get id => 'folders';
  @override
  String get name => 'Folders';

  @override
  List<AssetAction> get assetActions => [
    for (var i = 0; i < 7; i++)
      AssetAction(
        id: 'folders.new$i',
        label: 'New thing $i',
        icon: Icons.add_box_outlined,
        appliesTo: (path, {required isDirectory}) => isDirectory,
        run: (scope, path) => ran.add('$i $path'),
      ),
  ];
}

void main() {
  late Directory dir;
  late _Index index;

  void write(String path, [String content = 'x']) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('assets_browser');
    write('assets/sprites/hero.json', '{}');
    write('assets/sprites/coin.json', '{}');
    write('assets/audio/jump.wav');
    write(
      'assets/scenes/level.scene.json',
      '{"a": "assets/sprites/hero.json"}',
    );
    index = _Index(projectRoot: dir.path);
  });
  tearDown(() async {
    index.dispose();
    // Something else on the machine (a virus scanner) may still hold a
    // file just written for a moment on Windows.
    await deleteWhenFree(dir);
  });

  Future<(_Memory, EditorScope)> pump(
    WidgetTester tester, {
    List<EditorModule> modules = const [],
    Widget Function(Widget dock)? wrap,
    SceneManager Function(EditorScope scope)? scenes,
  }) async {
    tester.view
      ..physicalSize = const Size(1400, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(index.scan);
    final scope = testScope(
      modules: modules,
      scenesRoot: '${dir.path}/assets/scenes',
    );
    final memory = _Memory();
    final dock = AssetsBrowserDock(
      scope: scope,
      index: index,
      sceneManager: scenes?.call(scope),
      dock: DockContext(
        scope: scope,
        height: 400,
        onResize: (_) {},
        onClose: () {},
        memory: memory,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: wrap == null ? dock : wrap(dock),
          ),
        ),
      ),
    );
    await tester.pump();
    // The dock reads the folder again as it opens: done before the test
    // acts, so an action's own rescan is not folded into that one.
    await pumpUntil(
      tester,
      () => index.scanning == 0,
      what: 'the opening scan',
    );
    return (memory, scope);
  }

  /// Waits until no scan is under way, so that a test that changed files
  /// lets go of the folder before it is deleted.
  Future<void> quiet(WidgetTester tester) => pumpUntil(
    tester,
    () => index.scanning == 0,
    what: 'the asset index to finish scanning',
  );

  bool shows(Finder finder) => finder.evaluate().isNotEmpty;

  /// Whether [name] is selected: in the grid and in the preview beside it —
  /// where a rename or a restore leaves the file once it is done.
  bool selected(String name) => find.text(name).evaluate().length == 2;

  String readFile(String path) =>
      readWhenFree(() => File('${dir.path}/$path').readAsStringSync());

  testWidgets('folders lead somewhere, and the way back is on the toolbar', (
    tester,
  ) async {
    final (memory, _) = await pump(tester);
    expect(find.text('sprites'), findsWidgets);
    expect(
      find.text('hero.json'),
      findsNothing,
      reason: 'one folder at a time',
    );

    await tester.tap(find.text('sprites').first);
    await tester.pump();
    expect(find.text('hero.json'), findsOneWidget);
    expect(find.text('coin.json'), findsOneWidget);
    expect(memory.values['dir'], 'assets/sprites', reason: 'remembered');

    // A search looks under the open folder; the breadcrumb goes back up.
    await tester.enterText(find.byType(TextField), 'coin');
    await tester.pump();
    expect(find.text('hero.json'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('assets').first);
    await tester.pump();
    expect(find.text('hero.json'), findsNothing);
  });

  testWidgets('a folder with more actions than its row holds lists them '
      'under one button', (tester) async {
    final module = _FolderModule();
    await pump(tester, modules: [module]);
    expect(tester.takeException(), isNull, reason: 'nothing overflows');
    expect(find.byTooltip('New thing 0'), findsNothing);

    await tester.tap(find.byTooltip('What this folder can do'));
    await tester.pumpAndSettle();
    expect(find.text('New thing 6'), findsOneWidget);
    await tester.tap(find.text('New thing 2'));
    await tester.pumpAndSettle();
    expect(module.ran, ['2 assets']);
  });

  testWidgets('a file that is in use says so before it is deleted, and the '
      'delete can be taken back', (tester) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'));
    await tester.pump();
    expect(
      find.textContaining('Data · 2 B'),
      findsOneWidget,
      reason: 'preview',
    );

    final hero = File('${dir.path}/assets/sprites/hero.json');
    await tester.tap(find.byTooltip('Delete (to the trash)'));
    await pumpUntil(
      tester,
      () => shows(find.text('Delete anyway')),
      what: 'the question about what uses it',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('level.scene.json'), findsOneWidget);
    await tester.tap(find.text('Delete anyway'));
    // Restore is offered once the delete is done.
    await pumpUntil(
      tester,
      () => shows(find.text('Restore')),
      what: 'the delete',
    );
    await tester.pumpAndSettle();
    expect(hero.existsSync(), isFalse);
    expect(find.text('hero.json'), findsNothing);

    await tester.tap(find.text('Restore'));
    // Done when the file is back and the offer gone with it.
    await pumpUntil(
      tester,
      () => hero.existsSync() && !shows(find.text('Restore')),
      what: 'the restore',
    );
    expect(hero.existsSync(), isTrue);
    expect(find.text('hero.json'), findsWidgets);
    await quiet(tester);
    // Let the "restore" bar's timer run out before the test ends.
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('renaming a used file offers to update what uses it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'knight.json',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
    await pumpUntil(
      tester,
      () => shows(find.text('Rename and update')),
      what: 'the question about what uses it',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename and update'));
    // The renamed file is selected once the rename and the update are done.
    await pumpUntil(
      tester,
      () => selected('knight.json'),
      what: 'the rename and the update',
    );
    expect(File('${dir.path}/assets/sprites/knight.json').existsSync(), isTrue);
    expect(
      readFile('assets/scenes/level.scene.json'),
      contains('"assets/sprites/knight.json"'),
    );
    await quiet(tester);
  });

  Future<void> menu(WidgetTester tester, Finder on, String action) async {
    await tester.tap(on, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pumpAndSettle();
  }

  Future<void> renameTo(WidgetTester tester, String name) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      name,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Rename'));
  }

  testWidgets('renaming a used folder offers to update every path under it', (
    tester,
  ) async {
    final (_, scope) = await pump(tester);
    // The grid's "sprites", not the tree's.
    await menu(tester, find.text('sprites').last, 'Rename…');
    await renameTo(tester, 'chars');
    await pumpUntil(
      tester,
      () => shows(find.text('Rename and update')),
      what: 'the question about what uses it',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('level.scene.json'), findsOneWidget);
    await tester.tap(find.text('Rename and update'));
    // The last thing the update does is say so in the Console.
    await pumpUntil(
      tester,
      () => scope.log.entries.value.any(
        (e) => e.source == 'assets' && e.message.contains('chars'),
      ),
      what: 'the rename and the update',
    );
    expect(Directory('${dir.path}/assets/chars').existsSync(), isTrue);
    expect(
      readFile('assets/scenes/level.scene.json'),
      '{"a": "assets/chars/hero.json"}',
    );
    await quiet(tester);
  });

  testWidgets('deleting a used folder warns first', (tester) async {
    await pump(tester);
    await menu(tester, find.text('sprites').last, 'Delete');
    await pumpUntil(
      tester,
      () => shows(find.textContaining('still used')),
      what: 'the question about what uses it',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('still used'), findsOneWidget);
    expect(find.textContaining('level.scene.json'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(Directory('${dir.path}/assets/sprites').existsSync(), isTrue);
    await quiet(tester);
  });

  testWidgets('a scene file is renamed as a scene: its name checked and the '
      'play order kept', (tester) async {
    final (_, scope) = await pump(tester);
    await tester.runAsync(() => scope.scenes.writePlayOrder(['level']));
    await tester.tap(find.text('scenes').first);
    await tester.pump();
    await menu(tester, find.text('level.scene.json'), 'Rename…');
    expect(find.text('Rename "level"'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(EditorAlert),
        matching: find.byType(TextField),
      ),
      'level_07',
    );
    await tester.pump();
    await tester.tap(find.text('Rename').last);
    // The renamed scene is selected once the rename is done.
    await pumpUntil(
      tester,
      () => selected('level_07.scene.json'),
      what: 'the rename',
    );
    expect(
      File('${dir.path}/assets/scenes/level_07.scene.json').existsSync(),
      isTrue,
    );
    expect(
      File('${dir.path}/assets/scenes/level.scene.json').existsSync(),
      isFalse,
    );
    expect(scope.scenes.playOrder(), ['level_07']);
    await quiet(tester);
  });

  testWidgets("the open scene, and a scene the game's code opens, are not "
      'renamed or deleted here', (tester) async {
    final (_, scope) = await pump(
      tester,
      scenes: (scope) =>
          SceneManager(store: scope.scenes, protectedSceneNames: {'level'}),
    );
    await tester.tap(find.text('scenes').first);
    await tester.pump();
    await menu(tester, find.text('level.scene.json'), 'Delete');
    expect(find.textContaining("used by the game's own code"), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    final (_, open) = await pump(tester);
    open.sceneState.openScene(EditorScene(name: 'level'));
    await tester.tap(find.text('scenes').first);
    await tester.pump();
    await menu(tester, find.text('level.scene.json'), 'Rename…');
    expect(find.textContaining('the scene open in the editor'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      File('${dir.path}/assets/scenes/level.scene.json').existsSync(),
      isTrue,
    );
    expect(scope, isNot(same(open)));
  });

  testWidgets('a deleted scene leaves the play order, and a restore puts '
      'it back where it was', (tester) async {
    write('assets/scenes/intro.scene.json', '{"name": "intro"}');
    final (_, scope) = await pump(tester);
    await tester.runAsync(
      () => scope.scenes.writePlayOrder(['intro', 'level']),
    );
    await tester.tap(find.text('scenes').first);
    await tester.pump();
    await menu(tester, find.text('intro.scene.json'), 'Delete');
    // Restore is offered once the delete — the play order too — is done.
    await pumpUntil(
      tester,
      () => shows(find.text('Restore')),
      what: 'the delete',
    );
    await tester.pumpAndSettle();
    expect(
      File('${dir.path}/assets/scenes/intro.scene.json').existsSync(),
      isFalse,
    );
    expect(scope.scenes.playOrder(), ['level']);
    final manifest = readFile('assets/scenes/scenes.json');
    expect(manifest, isNot(contains('intro')), reason: 'the game reads it');

    await tester.tap(find.text('Restore'));
    // The restored scene is selected once the restore is done.
    await pumpUntil(
      tester,
      () => selected('intro.scene.json'),
      what: 'the restore',
    );
    expect(scope.scenes.playOrder(), ['intro', 'level']);
    await quiet(tester);
    await tester.pump(const Duration(seconds: 13));
  });

  testWidgets('nothing is renamed or deleted during a play-test', (
    tester,
  ) async {
    final (_, scope) = await pump(tester);
    scope.isPlayTesting.value = true;
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await menu(tester, find.text('hero.json'), 'Rename…');
    expect(find.textContaining('Stop the play-test first'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget, reason: 'no rename prompt');
  });

  testWidgets('with a file clicked, Delete is the browser\'s, not the '
      "level's", (tester) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'));
    await tester.pump();
    const delete = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.delete,
      logicalKey: LogicalKeyboardKey.delete,
      timeStamp: Duration.zero,
    );
    expect(
      EditorKeyClaim.focusedClaims(delete),
      isTrue,
      reason: 'the editor lets it through',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await pumpUntil(
      tester,
      () => shows(find.text('Delete anyway')),
      what: 'the question about what uses it',
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete anyway'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await quiet(tester);
  });

  testWidgets('on a Mac Backspace deletes a file too', (tester) async {
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    await tester.tap(find.text('hero.json'));
    await tester.pump();
    const backspace = KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.backspace,
      logicalKey: LogicalKeyboardKey.backspace,
      timeStamp: Duration.zero,
    );
    expect(EditorKeyClaim.focusedClaims(backspace), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await pumpUntil(
      tester,
      () => shows(find.text('Delete anyway')),
      what: 'the in-use warning',
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete anyway'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a dropped file lands under the pointer', (tester) async {
    Offset? dropped;
    await pump(
      tester,
      wrap: (dock) => Column(
        children: [
          SizedBox(height: 300, child: dock),
          Expanded(
            child: DragTarget<String>(
              onAcceptWithDetails: (d) => dropped = d.offset,
              builder: (context, _, _) => const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    final from = tester.getCenter(find.text('hero.json'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    const to = Offset(400, 420);
    for (var i = 1; i <= 5; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 5)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    expect(dropped, to);
  });

  testWidgets('a thumbnail is read again once its file changes', (
    tester,
  ) async {
    write('assets/sprites/tree.png', 'not really a png');
    await pump(tester);
    await tester.tap(find.text('sprites').first);
    await tester.pump();
    ImageProvider shown() => tester.widget<Image>(find.byType(Image)).image;
    final before = shown();
    File(
      '${dir.path}/assets/sprites/tree.png',
    ).setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
    await tester.runAsync(index.scan);
    await pumpUntil(
      tester,
      () => shown() != before,
      what: 'the thumbnail to follow the file',
    );
    expect(shown(), isNot(before));
    // Both readings of the file finish (here, failing to decode it) before
    // the folder is deleted.
    for (final image in [before, shown()]) {
      await pumpUntilImageSettled(
        tester,
        image,
        what: 'the thumbnail to be read',
      );
    }
    await quiet(tester);
  });

  // Boots an engine and the editor in a plain test: see bootTimeout.
  group('dropped on the viewport', () {
    late JustGameEditorPlugin plugin;
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine);
      await plugin.attach(plugin.engine);
    });
    tearDown(() {
      plugin.dispose();
    });

    test('an image is a sprite there; an atlas or a project animates', () {
      expect(
        plugin.dropAsset('assets/a.png', Offset.zero),
        isNull,
        reason: 'no scene',
      );
      plugin.sceneState.openScene(EditorScene(name: 'level'));
      final camera = plugin.engine.cameraSystem.mainCamera
        ..viewportSize = const Size(800, 600);
      final where = camera.screenToWorld(const Offset(200, 150));

      final still = plugin.dropAsset(
        'assets/sprites/tree.png',
        const Offset(200, 150),
      )!;
      expect(still.name, 'tree');
      final sprite = still.getComponent<SpriteComponent>()!;
      expect(
        (sprite.spritePath, sprite.pixelArt),
        ('assets/sprites/tree.png', true),
      );
      final at = still.getComponent<TransformComponent>()!.position;
      expect((at.x, at.y), (where.dx, where.dy));
      expect(plugin.sceneState.selectedEntity.value, same(still));

      final fromProject = plugin.dropAsset(
        'assets/sprites/hero.jsprite',
        Offset.zero,
      )!;
      expect(
        fromProject.getComponent<SpriteAnimationComponent>()!.atlasPath,
        'assets/sprites/hero.json',
        reason: 'the atlas saved beside the project',
      );
      expect(
        plugin.dropAsset('assets/scenes/l.scene.json', Offset.zero),
        isNull,
      );
      // A sound: a looping source of it, flat in a 2-D scene.
      final sound = plugin.dropAsset('assets/audio/wind.wav', Offset.zero)!;
      expect(sound.name, 'wind');
      final source = sound.getComponent<AudioSourceComponent>()!;
      expect(
        (source.clipPath, source.loop, source.is3d),
        ('assets/audio/wind.wav', true, false),
      );
    }, timeout: bootTimeout);
  });
}
