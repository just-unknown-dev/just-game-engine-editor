@Tags(['gpu'])
library;

// A model's picture for the Assets dock, rendered on a real GPU.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/graphics/graphics.dart';
import 'package:just_graphics_engine/testing.dart';

void main() {
  final skip = gpuUnavailableReason();

  test('a model is pictured, and the picture is kept', () async {
    final dir = Directory.systemTemp.createTempSync('jge_thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/hero.glb').writeAsBytesSync(mannequinGlb());
    final thumbnails = ModelThumbnails(root: dir.path, size: 64);
    addTearDown(thumbnails.dispose);

    final image = await thumbnails.of('hero.glb');
    expect(image, isNotNull);
    expect((image!.width, image.height), (64, 64));
    // Something is drawn in the middle: the figure, not the clear colour.
    final pixels = await readPixels(image);
    final centre = pixels.atFraction(0.5, 0.5);
    final corner = pixels.atFraction(0.02, 0.02);
    expect(centre, isNot(corner));
    expect(thumbnails.peek('hero.glb'), same(image));

    // A file that is no model has no picture.
    File('${dir.path}/broken.glb').writeAsStringSync('nope');
    expect(await thumbnails.of('broken.glb'), isNull);
  }, skip: skip);

  test('a model changed on disk is pictured again, and the old picture let '
      'go', () async {
    final dir = Directory.systemTemp.createTempSync('jge_thumb');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/hero.glb')..writeAsBytesSync(mannequinGlb());
    final thumbnails = ModelThumbnails(root: dir.path, size: 64);
    addTearDown(thumbnails.dispose);

    final first = await thumbnails.of('hero.glb', modified: DateTime(2026));
    expect(first, isNotNull);
    file.setLastModifiedSync(DateTime(2026, 2));
    final second = await thumbnails.of(
      'hero.glb',
      modified: file.lastModifiedSync(),
    );
    expect(second, isNotNull);
    expect(first!.debugDisposed, isTrue, reason: 'the old picture let go');
    expect(second!.debugDisposed, isFalse);
    expect(thumbnails.keptPictures, 1);
  }, skip: skip);
}
