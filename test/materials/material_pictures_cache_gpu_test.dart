@Tags(['gpu'])
library;

// What material pictures keep, on a real GPU: the dock's pictures draw
// their maps small and the window's full size, let go when it closes; the
// pictures kept on disk are drawn again when anything they are drawn from
// changed — a map, between sessions — or when one was cut short; two
// materials whose names look alike keep a picture each; and a material
// changed on disk is read again.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  final skip = gpuUnavailableReason();
  late Directory dir;
  late String cache;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_cache');
    cache = '${dir.path}/cache';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  MaterialPictures session({String? folder}) {
    final pictures = MaterialPictures(
      root: dir.path,
      size: 64,
      cacheFolder: folder,
    );
    addTearDown(pictures.dispose);
    return pictures;
  }

  Future<void> writePng(String path, ui.Color colour, {int size = 8}) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..color = colour,
    );
    final image = await recorder.endRecording().toImage(size, size);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('${dir.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  void writeMaterial(String path, MaterialFile file) =>
      File('${dir.path}/$path')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(file.encode());

  Future<List<int>> centre(ui.Image? image) async =>
      (await readPixels(image!)).atFraction(0.5, 0.5);

  List<String> cached() => [
    for (final f in Directory(cache).listSync().whereType<File>())
      f.uri.pathSegments.last,
  ]..sort();

  test("the dock's maps small, the window's full size and let go", () async {
    await writePng('big.png', const ui.Color(0xFFFF0000), size: 1024);
    writeMaterial(
      'm.material.json',
      const MaterialFile(colorMap: 'big.png', unlit: true),
    );
    final pictures = session();
    expect(await pictures.of('m.material.json'), isNotNull);
    expect(pictures.keptMaps, [('big.png', true, 128)]);
    expect(pictures.keptMapBytes, lessThanOrEqualTo(128 * 128 * 4 * 4 ~/ 3));

    final full = await pictures.render(
      MaterialFile.parse(
        File('${dir.path}/m.material.json').readAsStringSync(),
      ),
    );
    full?.dispose();
    expect(pictures.keptMaps, contains(('big.png', true, null)));
    expect(pictures.keptMapBytes, greaterThan(1024 * 1024 * 4));

    pictures.releaseFullSizeMaps();
    expect(pictures.keptMaps, [('big.png', true, 128)]);
    pictures.dispose();
    expect(pictures.keptMaps, isEmpty);
  }, skip: skip);

  test('a picture on disk is drawn again when its map changed', () async {
    await writePng('tint.png', const ui.Color(0xFFFF0000));
    writeMaterial(
      'm.material.json',
      const MaterialFile(colorMap: 'tint.png', unlit: true),
    );
    final modified = File('${dir.path}/m.material.json').lastModifiedSync();
    final red = await centre(
      await session(folder: cache).of('m.material.json', modified: modified),
    );
    expect(red[0], greaterThan(red[2]));
    expect(cached(), hasLength(1));

    // Next session: the map was painted over; the material is as it was.
    await writePng('tint.png', const ui.Color(0xFF0000FF));
    final blue = await centre(
      await session(folder: cache).of('m.material.json', modified: modified),
    );
    expect(blue[2], greaterThan(blue[0]), reason: 'not the kept picture');
    expect(cached(), hasLength(1), reason: 'the stale one let go');
  }, skip: skip);

  test('a picture cut short is drawn again; old kinds are let go', () async {
    writeMaterial('m.material.json', const MaterialFile(color: 0xFF20A040));
    final modified = File('${dir.path}/m.material.json').lastModifiedSync();
    await session(folder: cache).of('m.material.json', modified: modified);
    final kept = File('$cache/${cached().single}');
    kept.writeAsBytesSync(kept.readAsBytesSync().sublist(0, 20));
    // A picture drawn for an older look, and one half written.
    File('$cache/old.material.json@123-64-v1.png').writeAsBytesSync([1, 2]);
    File('$cache/x.png.saving').writeAsBytesSync([1, 2]);

    final again = await session(
      folder: cache,
    ).of('m.material.json', modified: modified);
    expect(again, isNotNull);
    expect(cached(), [kept.uri.pathSegments.last]);
    expect(kept.lengthSync(), greaterThan(20), reason: 'written whole again');
  }, skip: skip);

  test('names that look alike keep a picture each', () async {
    writeMaterial('a/b.material.json', const MaterialFile(color: 0xFFFF0000));
    writeMaterial('a_b.material.json', const MaterialFile(color: 0xFF0000FF));
    final pictures = session(folder: cache);
    final t = DateTime(2026);
    await pictures.of('a/b.material.json', modified: t);
    await pictures.of('a_b.material.json', modified: t);
    expect(cached(), hasLength(2));
    final next = session(folder: cache);
    final red = await centre(await next.of('a/b.material.json', modified: t));
    final blue = await centre(await next.of('a_b.material.json', modified: t));
    expect(red[0], greaterThan(red[2]));
    expect(blue[2], greaterThan(blue[0]));
  }, skip: skip);

  test('a material changed on disk is read again', () async {
    final pictures = session();
    writeMaterial(
      'm.material.json',
      const MaterialFile(color: 0xFFFF0000, unlit: true),
    );
    final red = await centre(
      await pictures.of('m.material.json', modified: DateTime(2026, 1, 1)),
    );
    expect(red[0], greaterThan(red[2]));
    // Changed by another tool: the dock asks for it as it is now.
    writeMaterial(
      'm.material.json',
      const MaterialFile(color: 0xFF0000FF, unlit: true, roughness: 0.4),
    );
    final blue = await centre(
      await pictures.of('m.material.json', modified: DateTime(2026, 1, 2)),
    );
    expect(blue[2], greaterThan(blue[0]));
  }, skip: skip);
}
