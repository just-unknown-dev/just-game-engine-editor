// Auto: a 2-D material shown on what fits it — the game's own sprite or
// shape drawn with it (found in the project's scenes), else stone tiles the
// size of its normal map, tiles for what moves, or the sample sprite.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

const _material = 'assets/materials/rock.material2d.json';

Map<String, Object?> _component(String type, Map<String, Object?> fields) => {
  'type': type,
  'fields': fields,
};

Map<String, Object?> _entity(String name, List<Map<String, Object?>> c) => {
  'name': name,
  'components': [
    _component('TransformComponent', {}),
    ...c,
    _component('Material2D', {'material': _material, 'overrides': {}}),
  ],
};

Map<String, Object?> _sprite(String image, {String atlas = ''}) => _component(
  'SpriteComponent',
  {'spritePath': image, 'atlasPath': atlas, 'region': ''},
);

final _circle = _component('CircleComponent', {
  'radius': 6.0,
  'fillStyle': {'color': 0xFFFFC107, 'blendMode': 'modulate'},
  'strokeStyle': {'color': 0xFF000000, 'blendMode': 'modulate'},
  'filled': true,
  'strokeWidth': 1.0,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('jge_auto'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String path, Object json) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(json));

  Future<void> png(String path, int w, int h, Color colour) async {
    final r = ui.PictureRecorder();
    Canvas(r).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = colour,
    );
    final picture = r.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes.buffer.asUint8List());
  }

  group('Material2DUsers', () {
    test(
      'a sprite drawn with it, before a shape; atlases passed over',
      () async {
        write('assets/scenes/a.scene.json', {
          'entities': [
            _entity('Glow', [_circle]),
            _entity('Atlas', [_sprite('assets/sheet.png', atlas: 'a.json')]),
          ],
        });
        write('assets/scenes/b.scene.json', {
          'entities': [
            {
              'name': 'Group',
              'components': <Object>[],
              'children': [
                _entity('Rock', [_sprite('assets/rock.png')]),
              ],
            },
          ],
        });
        final user = (await Material2DUsers.find(dir.path, _material))!;
        expect(user.spritePath, 'assets/rock.png');
        expect(user.label, 'Rock (b)');

        File('${dir.path}/assets/scenes/b.scene.json').deleteSync();
        final shape = (await Material2DUsers.find(dir.path, _material))!;
        expect(shape.spritePath, isNull);
        expect(
          [for (final c in shape.shape!) c['type']],
          ['CircleComponent'],
          reason: 'its place and its material left out',
        );
        expect(shape.file, 'assets/scenes/a.scene.json');

        expect(
          await Material2DUsers.find(dir.path, 'other.material2d.json'),
          isNull,
        );
      },
    );
  });

  test('what fits it, by its effects; lit when bumps or a glow', () {
    Material2DFile file(Map<String, Object?> json) =>
        Material2DFile.parse(jsonEncode(json));
    final bumps = file({
      'normalMap': {'map': 'n.png'},
    });
    final water = file({
      'scroll': {
        'speed': [10, 0],
      },
    });
    final flash = file({
      'flash': {'amount': 1},
    });
    final glow = file({
      'emissive': {'amount': 1},
    });
    expect(
      [
        for (final f in [bumps, water, flash, glow]) Material2DAuto.of(f),
      ],
      [
        Material2DAuto.stone,
        Material2DAuto.tiles,
        Material2DAuto.sample,
        Material2DAuto.sample,
      ],
    );
    expect(
      [
        for (final f in [bumps, water, flash, glow]) Material2DAuto.lit(f),
      ],
      [true, false, false, true],
    );
  });

  group('the stage', () {
    late Material2DStage stage;
    setUp(() => stage = Material2DStage(root: dir.path));
    tearDown(() => stage.dispose());

    Future<(int, int, int)> middle(int w, int h) async {
      final image = await stage.picture(w, h);
      final d = (await image.toByteData())!;
      image.dispose();
      final i = ((h ~/ 2) * w + w ~/ 2) * 4;
      return (d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
    }

    test("on the game's own sprite", () async {
      write(_material, {
        'tint': {'colour': 0xFFFFFFFF},
      });
      await png('assets/rock.png', 16, 16, const Color(0xFFFF0000));
      final user = Material2DUser(
        file: 'assets/scenes/b.scene.json',
        entity: 'Rock',
        spritePath: 'assets/rock.png',
      );
      stage.show(
        _material,
        kind: Material2DKind.sprite,
        subject: Material2DSubject.auto,
        image: await stage.loadImage('assets/rock.png'),
        user: user,
      );
      final (r, g, _) = await middle(80, 80);
      expect((r > 200, g < 60), (true, true), reason: 'the red rock');
      expect(stage.autoShows, Material2DAuto.user);
    });

    test(
      'nothing of the game: stone tiles the size of its normal map',
      () async {
        await png('assets/n.png', 8, 8, const Color(0xFF8080FF));
        write(_material, {
          'normalMap': {'map': 'assets/n.png'},
        });
        stage.show(
          _material,
          kind: Material2DKind.sprite,
          subject: Material2DSubject.auto,
        );
        await stage.picture(60, 60);
        expect(stage.autoShows, Material2DAuto.stone);
        final tiles = [
          for (final e in stage.world.query(const [RenderableComponent]))
            e.getComponent<RenderableComponent>()!.renderable,
        ].whereType<Sprite>().toList();
        expect(tiles, hasLength(9), reason: 'three by three');
        expect(
          {for (final t in tiles) (t.image!.width, t.image!.height)},
          {(8, 8)},
          reason: "each the map's size, so its bumps fit a tile",
        );
      },
    );

    test('on a shape drawn with it', () async {
      write(_material, {
        'tint': {'colour': 0xFFFFFFFF},
      });
      stage.show(
        _material,
        kind: Material2DKind.sprite,
        subject: Material2DSubject.auto,
        user: Material2DUser(
          file: 'assets/scenes/a.scene.json',
          entity: 'Glow',
          shape: [_circle.cast<String, dynamic>()],
        ),
      );
      final (r, g, b) = await middle(80, 80);
      expect((r > 200, g > 150, b < 80), (true, true, true), reason: 'amber');
      final drawn = [
        for (final e in stage.world.query(const [Material2D]))
          e.getComponent<RenderableComponent>(),
      ];
      expect(drawn, [isA<CircleComponent>()], reason: 'the circle, decoded');
    });
  });
}
