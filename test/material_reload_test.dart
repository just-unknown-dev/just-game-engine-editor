// A material file changed on disk: the editor has the engine read it
// again — whichever tool wrote it — so what is drawn with it changes.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a 2-D material is read again, one file or many at once', () async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await engine.initialize();
    final reads = <String>[];
    // The library the engine draws with, reading through a counter.
    engine.context.slot(
      Material2DLibrary,
      () => Material2DLibrary((path) async {
        reads.add(path);
        return '{"kind": "sprite"}';
      }),
    );
    final plugin = JustGameEditorPlugin(engine: engine);
    await plugin.onInitialize();
    addTearDown(plugin.dispose);

    const path = 'assets/materials/hit.material2d.json';
    final library = Material2DLibrary.of(engine.context);
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
}
