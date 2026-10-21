// Making materials from what artists bring: texture sets found by their
// names and packed as the engine reads them, a model's own materials
// written out, and normal maps made from a picture.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String root;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_import');
    root = dir.path.replaceAll(r'\', '/');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A [w] × [h] picture of one colour.
  Pixels solid(int w, int h, int r, int g, int b, [int a = 255]) {
    final p = Pixels(w, h);
    for (var i = 0; i < w * h; i++) {
      p.rgba
        ..[i * 4] = r
        ..[i * 4 + 1] = g
        ..[i * 4 + 2] = b
        ..[i * 4 + 3] = a;
    }
    return p;
  }

  Future<void> png(String path, Pixels p) => p.writePng('$root/$path');

  test('pixels survive a PNG, half-clear ones keeping their colour', () async {
    await png('a.png', solid(3, 2, 200, 40, 10, 128));
    final back = await Pixels.read('$root/a.png');
    expect((back.width, back.height), (3, 2));
    for (var c = 0; c < 4; c++) {
      expect(back.at(1, 1, c), closeTo([200, 40, 10, 128][c], 2));
    }
    final big = await Pixels.read('$root/a.png', width: 6, height: 4);
    expect((big.width, big.height), (6, 4));
    expect(await Pixels.sizeOf('$root/a.png'), (3, 2));
  });

  group('texture sets', () {
    test('a map known by its name, as sites and tools write them', () {
      expect(TextureSets.roleOf('brick_albedo.png'), (
        'brick',
        TextureRole.colour,
        false,
      ));
      expect(TextureSets.roleOf('Bricks059_1K-PNG_Color.png'), (
        'Bricks059',
        TextureRole.colour,
        false,
      ));
      expect(TextureSets.roleOf('Bricks059_1K-PNG_NormalDX.png'), (
        'Bricks059',
        TextureRole.normal,
        true,
      ));
      expect(TextureSets.roleOf('brick_wall_nor_gl_2k.png'), (
        'brick_wall',
        TextureRole.normal,
        false,
      ));
      expect(TextureSets.roleOf('brick_wall_nor_dx_2k.png')!.$3, isTrue);
      expect(TextureSets.roleOf('brick_wall_arm_2k.jpg')!.$2, TextureRole.orm);
      expect(TextureSets.roleOf('rock_Base_Color.png'), (
        'rock',
        TextureRole.colour,
        false,
      ));
      expect(
        TextureSets.roleOf('rock-AmbientOcclusion.png')!.$2,
        TextureRole.occlusion,
      );
      expect(TextureSets.roleOf('rock_gloss.png')!.$2, TextureRole.gloss);
      expect(TextureSets.roleOf('rock_disp_4k.png')!.$2, TextureRole.height);
      expect(TextureSets.roleOf('hero.png'), isNull);
      expect(TextureSets.roleOf('1k.png'), isNull);
    });

    test('maps that share a name are one set; a lone map is none', () {
      final sets = TextureSets.find([
        'assets/t/brick_albedo.png',
        'assets/t/brick_normal.png',
        'assets/t/brick_roughness.png',
        'assets/t/hero.png',
        'assets/t/stone_ao.png',
        'assets/t/wood_diffuse.jpg',
        'assets/u/brick_albedo.png',
      ]);
      expect(
        [for (final s in sets) '${s.folder}/${s.name}'],
        ['assets/t/brick', 'assets/u/brick', 'assets/t/wood'],
      );
      expect(sets.first.maps.keys.toSet(), {
        TextureRole.colour,
        TextureRole.normal,
        TextureRole.roughness,
      });
    });

    test('made into a material: occlusion, roughness and metal packed; a '
        'DirectX normal turned over', () async {
      Directory('$root/assets/t').createSync(recursive: true);
      await png('assets/t/brick_albedo.png', solid(4, 4, 180, 90, 60));
      await png('assets/t/brick_roughness.png', solid(4, 4, 100, 100, 100));
      await png('assets/t/brick_metallic.png', solid(2, 2, 255, 255, 255));
      await png('assets/t/brick_ao.png', solid(4, 4, 200, 200, 200));
      await png('assets/t/brick_normaldx.png', solid(4, 4, 128, 40, 255));
      await png('assets/t/brick_height.png', solid(4, 4, 0, 0, 0));
      final set = TextureSets.inFolder(root, 'assets/t').single;
      expect(set.directX, isTrue);
      final result = await TextureSets.make(root, set);

      expect(result.material, 'assets/t/brick.material.json');
      final m = MaterialFile.parse(read(root, result.material));
      expect(m.colorMap, 'assets/t/brick_albedo.png');
      expect(m.metalRoughMap, 'assets/t/brick_orm.png');
      expect(m.occlusionMap, 'assets/t/brick_orm.png');
      expect(m.normalMap, 'assets/t/brick_normal_gl.png');
      expect((m.metallic, m.roughness), (1.0, 1.0), reason: 'the maps say');
      expect(m.validate(), isEmpty);

      final orm = await Pixels.read('$root/assets/t/brick_orm.png');
      expect((orm.width, orm.height), (4, 4), reason: 'the largest');
      expect(
        [orm.at(1, 1, 0), orm.at(1, 1, 1), orm.at(1, 1, 2)],
        [200, 100, 255],
      );
      final normal = await Pixels.read('$root/assets/t/brick_normal_gl.png');
      expect(normal.at(0, 0, 1), 255 - 40, reason: 'green turned over');
      expect(result.notes.join(' '), contains('height map'));
      expect(result.notes.join(' '), contains('scaled to 4 × 4'));

      // Again: nothing written over.
      final again = await TextureSets.make(root, set);
      expect(again.material, 'assets/t/brick_2.material.json');
      expect(again.made, contains('assets/t/brick_orm_2.png'));
    });

    test(
      'gloss is turned into roughness; an ORM map is used as it is',
      () async {
        Directory('$root/t').createSync(recursive: true);
        await png('t/a_gloss.png', solid(2, 2, 255, 255, 255));
        await png('t/a_color.png', solid(2, 2, 10, 10, 10));
        await png('t/b_color.png', solid(2, 2, 10, 10, 10));
        await png('t/b_orm.png', solid(2, 2, 1, 2, 3));
        final sets = TextureSets.inFolder(root, 't');
        final a = await TextureSets.make(root, sets.first);
        final packed = await Pixels.read('$root/t/a_orm.png');
        expect(packed.at(0, 0, 1), 0, reason: 'fully glossy: smooth');
        expect(packed.at(0, 0, 2), 0, reason: 'no metal map: not metal');
        final ma = MaterialFile.parse(read(root, a.material));
        expect((ma.metallic, ma.roughness), (0.0, 1.0));
        expect(ma.occlusionMap, isEmpty);
        final b = await TextureSets.make(root, sets.last);
        final mb = MaterialFile.parse(read(root, b.material));
        expect(
          (mb.metalRoughMap, mb.occlusionMap),
          ('t/b_orm.png', 't/b_orm.png'),
        );
        expect(b.made, isEmpty);
      },
    );
  });

  group('normal maps', () {
    test('flat stays flat; a slope leans away from what is higher', () {
      final flat = NormalMaps.of(solid(5, 5, 128, 128, 128));
      expect(
        [flat.at(2, 2, 0), flat.at(2, 2, 1), flat.at(2, 2, 2)],
        [128, 128, 255],
      );
      // Brighter to the right: higher to the right, so it faces left.
      final ramp = Pixels(5, 5);
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final i = (y * 5 + x) * 4;
          ramp.rgba
            ..[i] = ramp.rgba[i + 1] = ramp.rgba[i + 2] = x * 50
            ..[i + 3] = 255;
        }
      }
      final right = NormalMaps.of(ramp);
      expect(right.at(2, 2, 0), lessThan(128));
      expect(right.at(2, 2, 1), 128);
      // Brighter going down: higher below, so it faces up (green up).
      final down = Pixels(5, 5);
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final i = (y * 5 + x) * 4;
          down.rgba
            ..[i] = down.rgba[i + 1] = down.rgba[i + 2] = y * 50
            ..[i + 3] = 255;
        }
      }
      expect(NormalMaps.of(down).at(2, 2, 1), greaterThan(128));
      expect(
        NormalMaps.of(
          ramp,
          options: const NormalMapOptions(invert: true),
        ).at(2, 2, 0),
        greaterThan(128),
        reason: 'dark is high',
      );
    });

    test('a sprite: clear stays clear, its edges round off', () {
      final sprite = Pixels(9, 9);
      for (var y = 2; y < 7; y++) {
        for (var x = 2; x < 7; x++) {
          final i = (y * 9 + x) * 4;
          sprite.rgba
            ..[i] = sprite.rgba[i + 1] = sprite.rgba[i + 2] = 255
            ..[i + 3] = 255;
        }
      }
      final map = NormalMaps.of(
        sprite,
        options: const NormalMapOptions.sprite(bevel: 2),
      );
      expect(map.at(0, 0, 3), 0, reason: 'clear');
      expect(map.at(4, 4, 3), 255);
      expect(
        map.at(2, 4, 0),
        lessThan(128),
        reason: 'its left edge faces left',
      );
      expect(map.at(6, 4, 0), greaterThan(128), reason: 'its right, right');
      expect(map.at(4, 2, 1), greaterThan(128), reason: 'its top, up');
    });

    test('a tiling texture: its edges meet', () {
      final stripe = solid(4, 4, 0, 0, 0);
      for (var y = 0; y < 4; y++) {
        final i = (y * 4 + 0) * 4;
        stripe.rgba[i] = stripe.rgba[i + 1] = stripe.rgba[i + 2] = 255;
      }
      final map = NormalMaps.of(
        stripe,
        options: const NormalMapOptions.tiling(),
      );
      // The column left of the bright one is the last: it faces left.
      expect(map.at(3, 1, 0), lessThan(128));
    });

    test('made beside the picture, never over another', () async {
      await png('hero.png', solid(4, 4, 255, 255, 255));
      final a = await NormalMaps.generate(root, 'hero.png');
      final b = await NormalMaps.generate(root, 'hero.png');
      expect((a, b), ('hero_normal.png', 'hero_normal_2.png'));
      expect((await Pixels.read('$root/$a')).width, 4);
      final flipped = NormalMaps.flipGreen(solid(1, 1, 10, 20, 30));
      expect(flipped.at(0, 0, 1), 235);
    });
  });

  test("a model's materials written out, its images beside them", () async {
    final image = await solid(2, 2, 255, 0, 0).png();
    final w = GlbWriter();
    final texture = w.addTexture(w.addImage(image));
    final brass = w.addMaterial({
      'name': 'Brass Trim',
      'pbrMetallicRoughness': {
        'baseColorFactor': [1, 0.5, 0.2, 1],
        'metallicFactor': 1,
        'roughnessFactor': 0.3,
        'baseColorTexture': {'index': texture},
      },
      'alphaMode': 'MASK',
      'alphaCutoff': 0.4,
      'emissiveFactor': [0, 0, 0],
    });
    w.setScene([
      w.addNode({
        'mesh': w.addMesh([
          {
            'attributes': {
              'POSITION': w.addFloats(
                [0, 0, 0, 1, 0, 0, 0, 1, 0],
                'VEC3',
                withBounds: true,
              ),
            },
            'material': brass,
          },
        ]),
      }),
    ]);
    Directory('$root/assets/models').createSync(recursive: true);
    File('$root/assets/models/lamp.glb').writeAsBytesSync(w.toGlb());

    final made = await ModelMaterials.extract(root, 'assets/models/lamp.glb');
    expect(made, ['assets/models/lamp_Brass_Trim.material.json']);
    final m = MaterialFile.parse(read(root, made.single));
    expect(m.colorMap, 'assets/models/lamp_textures/image_0.png');
    expect(
      File('$root/${m.colorMap}').readAsBytesSync(),
      Uint8List.fromList(image),
    );
    expect((m.metallic, m.roughness), (1.0, 0.3));
    expect(m.alpha, MaterialAlpha.cutout);
    expect(m.alphaCutoff, closeTo(0.4, 1e-9));
    // Linear 0.5 is sRGB 188.
    expect((m.color >> 8) & 0xFF, closeTo(188, 1));
    expect(m.emission, 0xFF000000);
  });

  test('the module offers each where it fits, and says what it made', () async {
    final module = BuiltInMaterialsModule(root: root);
    final scope = EditorScope(world: World()..initialize(), modules: [module]);
    addTearDown(scope.dispose);
    final byId = {for (final a in module.assetActions) a.id: a};
    expect(
      byId[BuiltInMaterialsModule.textureSetsId]!.appliesTo(
        'assets',
        isDirectory: true,
      ),
      isTrue,
    );
    expect(
      byId[BuiltInMaterialsModule.extractId]!.appliesTo(
        'a/b.glb',
        isDirectory: false,
      ),
      isTrue,
    );
    expect(
      byId[BuiltInMaterialsModule.extractId]!.appliesTo(
        'a/b.png',
        isDirectory: false,
      ),
      isFalse,
    );
    expect(
      byId[BuiltInMaterialsModule.spriteNormalId]!.appliesTo(
        'a/b.png',
        isDirectory: false,
      ),
      isTrue,
    );
    // An empty folder: nothing made, said so.
    Directory('$root/empty').createSync();
    expect(await module.importTextureSets(scope, 'empty'), isEmpty);
  });
}

String read(String root, String path) => File('$root/$path').readAsStringSync();
