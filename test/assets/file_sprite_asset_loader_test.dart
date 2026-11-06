// The editor's sprite loader keeps each sheet it decodes and hands out
// clones; what two scenes in a row did not ask for is let go as the next
// opens, its image disposed, while the clones callers hold stay theirs.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/assets/file_sprite_asset_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('jge_sprite_loader'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a file for a moment; it is a temp one.
    }
  });

  Future<void> png(String name) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 4, 4),
      Paint()..color = const Color(0xFF336699),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(4, 4);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    File('${dir.path}/$name').writeAsBytesSync(bytes.buffer.asUint8List());
  }

  test('each caller gets a clone of the one image kept', () async {
    await png('a.png');
    final loader = FileSpriteAssetLoader(root: dir.path);
    expect(loader.callerDisposesImages, isTrue);
    final first = await loader.loadImage('a.png');
    final second = await loader.loadImage('a.png');
    final kept = await loader.keptImageOf('a.png')!;
    expect(first.isCloneOf(kept), isTrue);
    expect(second.isCloneOf(kept), isTrue);
    first.dispose();
    expect(kept.debugDisposed, isFalse, reason: "the caller's own let go");
    second.dispose();
    loader.clear();
  });

  test(
    'what two scenes in a row did not ask for goes as the next opens',
    () async {
      for (final name in ['a.png', 'b.png', 'c.png']) {
        await png(name);
      }
      final loader = FileSpriteAssetLoader(root: dir.path);
      addTearDown(loader.clear);

      loader.loads.restart(); // Scene one opens.
      final held = await loader.loadImage('a.png');
      final a = await loader.keptImageOf('a.png')!;
      loader.loads.restart(); // Scene two.
      (await loader.loadImage('b.png')).dispose();
      loader.loads.restart(); // Scene three: one and two are the last two.
      expect(loader.keptImages, containsAll(['a.png', 'b.png']));
      (await loader.loadImage('c.png')).dispose();
      loader.loads.restart(); // Scene four: scene one's sheet goes.
      expect(loader.keptImages, unorderedEquals(['b.png', 'c.png']));
      await Future<void>.delayed(Duration.zero);
      expect(a.debugDisposed, isTrue, reason: "the loader's own let go");
      expect(held.debugDisposed, isFalse, reason: 'the clone held is its own');
      expect(held.width, 4);
      held.dispose();

      // Asked for again, it is read again.
      final again = await loader.loadImage('a.png');
      expect(again.width, 4);
      again.dispose();
    },
  );

  test('evicted or cleared, the images kept are disposed', () async {
    await png('a.png');
    await png('b.png');
    final loader = FileSpriteAssetLoader(root: dir.path);
    (await loader.loadImage('a.png')).dispose();
    (await loader.loadImage('b.png')).dispose();
    final a = await loader.keptImageOf('a.png')!;
    final b = await loader.keptImageOf('b.png')!;
    loader.evict('a.png');
    await Future<void>.delayed(Duration.zero);
    expect(a.debugDisposed, isTrue);
    expect(b.debugDisposed, isFalse);
    loader.clear();
    await Future<void>.delayed(Duration.zero);
    expect(b.debugDisposed, isTrue);
    expect(loader.keptImages, isEmpty);
  });
}
