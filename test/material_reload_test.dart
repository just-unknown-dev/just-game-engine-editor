// A material file changed on disk: the editor has the engine read it
// again — whichever tool wrote it — so what is drawn with it changes.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 2-D material is read again, one file or many at once', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);
    await plugin.attach(plugin.engine);
    addTearDown(plugin.dispose);
    final reads = <String>[];
    // The library the engine draws with, reading through a counter in place
    // of the editor's reader of the project's files.
    engine.context.material2DText = (path) async {
      reads.add(path);
      return '{"kind": "sprite"}';
    };

    const path = 'assets/materials/hit.material2d.json';
    final library = engine.context.material2DLibrary;
    library.fileOf(path);
    await pumpEventQueue();
    expect(reads, [path]);
    expect(library.fileOf(path), isNotNull);

    plugin.reloadAsset(path);
    await pumpEventQueue();
    expect(reads, [path, path]);

    plugin.reloadAssets([path, 'assets/sprites/hero.png']);
    await pumpEventQueue();
    expect(reads, [path, path, path], reason: 'the picture is no material');
  });

  for (final many in [false, true]) {
    test('a picture a 2-D material uses is read again from the new file, '
        'not the one the editor had read (${many ? 'many' : 'one'})', () async {
      final engine = Engine();
      addTearDown(engine.dispose);
      await engine.initialize();
      // Not a project file: the editor reads it through the engine's own
      // loader, which makes a new picture each time.
      final pictures = _Pictures();
      addTearDown(pictures.dispose);
      engine.context.sprites = pictures;
      final plugin = JustGameEditorPlugin(engine: engine);
      await plugin.attach(plugin.engine);
      addTearDown(plugin.dispose);

      const map = 'assets/materials/bumps_normal.png';
      final library = engine.context.material2DLibrary;
      library.imageOf(map);
      await _until(() => library.imageOf(map) != null);
      final first = library.imageOf(map);
      expect(first, isNotNull);
      expect(pictures.made, hasLength(1));

      if (many) {
        plugin.reloadAssets([map]);
      } else {
        plugin.reloadAsset(map);
      }
      await _until(
        () =>
            pictures.made.length > 1 &&
            identical(library.imageOf(map), pictures.made.last),
      );
      expect(
        pictures.made,
        hasLength(2),
        reason: "read again: the sprites' copy was forgotten first",
      );
      expect(library.imageOf(map), same(pictures.made.last));
      expect(library.imageOf(map)!.debugDisposed, isFalse);
    });
  }
}

/// Waits, a little at a time, until [done]: a file looked for and a picture
/// made take more than a turn of the event queue. Gives up after a second.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A new picture for each read, kept to be disposed by the test.
final class _Pictures extends SpriteAssetLoader {
  final List<ui.Image> made = [];

  @override
  Future<ui.Image> loadImage(String path) async {
    final image = await createTestImage(width: 1, height: 1, cache: false);
    made.add(image);
    return image;
  }

  @override
  Future<SpriteAtlas> loadAtlas(String path) =>
      throw UnsupportedError('no atlases here');

  void dispose() {
    for (final image in made) {
      image.dispose();
    }
  }
}
