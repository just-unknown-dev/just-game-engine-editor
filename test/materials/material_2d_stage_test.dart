// The 2-D stage: a material drawn on its sample sprite, a row of tiles or
// a scene through the engine's own shaders, unsaved edits shown in place
// of the file, and a light moved over a lit one.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Material2DStage stage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_stage');
    stage = Material2DStage(root: dir.path);
  });

  tearDown(() {
    stage.dispose();
    dir.deleteSync(recursive: true);
  });

  void write(String path, Map<String, Object?> json) =>
      File('${dir.path}/$path').writeAsStringSync(jsonEncode(json));

  Future<ByteData> frame(int w, int h) async {
    final image = await stage.picture(w, h);
    final data = (await image.toByteData())!;
    image.dispose();
    return data;
  }

  (int, int, int, int) at(ByteData d, int w, int x, int y) {
    final i = (y * w + x) * 4;
    return (
      d.getUint8(i),
      d.getUint8(i + 1),
      d.getUint8(i + 2),
      d.getUint8(i + 3),
    );
  }

  test('the sample sprite drawn through the material', () async {
    write('flash.material2d.json', {
      'flash': {'colour': 0xFFFF0000, 'amount': 1},
    });
    stage.show('flash.material2d.json', kind: Material2DKind.sprite);
    final d = await frame(80, 80);
    expect(stage.ready, isTrue);
    final (r, g, b, _) = at(d, 80, 34, 34);
    expect(r, greaterThan(200), reason: 'flashed red');
    expect(g, lessThan(60));
    expect(b, lessThan(60));
    // The corner is the background.
    expect(at(d, 80, 2, 2), (0x2A, 0x2E, 0x35, 0xFF));
  });

  test('an unsaved edit shown in place of the file', () async {
    write('flash.material2d.json', {
      'flash': {'colour': 0xFFFF0000, 'amount': 1},
    });
    stage.show('flash.material2d.json', kind: Material2DKind.sprite);
    await frame(80, 80);
    stage.library.preview(
      'flash.material2d.json',
      const Material2DFile(
        effects: {'flash': true},
        values: {'flash.colour': 0xFF0000FF, 'flash.amount': 1.0},
      ),
    );
    final (r, _, b, _) = at(await frame(80, 80), 80, 34, 34);
    expect(b, greaterThan(200), reason: 'flashed blue now');
    expect(r, lessThan(60));
  });

  test('tiles, and a screen material over a scene', () async {
    write('flash.material2d.json', {
      'flash': {'colour': 0xFFFF0000, 'amount': 1},
    });
    stage.show(
      'flash.material2d.json',
      kind: Material2DKind.sprite,
      subject: Material2DSubject.tiles,
    );
    final tiles = await frame(120, 60);
    final (r, g, _, _) = at(tiles, 120, 60, 30);
    expect((r > 200, g < 60), (true, true), reason: 'the middle tile');

    write('grey.material2d.json', {
      'kind': 'screen',
      'greyscale': {'amount': 1},
    });
    stage.show('grey.material2d.json', kind: Material2DKind.screen);
    final scene = await frame(120, 80);
    for (final (x, y) in [(10, 10), (60, 40), (100, 70)]) {
      final (r, g, b, _) = at(scene, 120, x, y);
      expect(
        (r - g).abs() <= 2 && (g - b).abs() <= 2,
        isTrue,
        reason: 'grey at $x, $y: $r $g $b',
      );
    }
  });

  test('lit: brighter near the light than far from it', () async {
    write('plain.material2d.json', {
      'tint': {'colour': 0xFFFFFFFF},
    });
    stage
      ..show('plain.material2d.json', kind: Material2DKind.sprite, lit: true)
      ..light = const ui.Offset(0.5, 0.5);
    final near = at(await frame(100, 100), 100, 35, 35);
    stage.light = const ui.Offset(1, 1);
    final far = at(await frame(100, 100), 100, 35, 35);
    expect(near.$1 + near.$2 + near.$3, greaterThan(far.$1 + far.$2 + far.$3));
  });
}
