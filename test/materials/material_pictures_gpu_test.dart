@Tags(['gpu'])
library;

// Materials pictured on a real GPU: on a ball for the Assets dock, on each
// preview shape and in each light, and drawn again when a map they use
// changes.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_graphics_engine/testing.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  final skip = gpuUnavailableReason();
  late Directory dir;
  late MaterialPictures pictures;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_picture');
    pictures = MaterialPictures(root: dir.path, size: 64);
  });

  tearDown(() {
    pictures.dispose();
    dir.deleteSync(recursive: true);
  });

  int brightness(List<int> rgba) => rgba[0] + rgba[1] + rgba[2];

  Future<void> writePng(String path, ui.Color colour) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 8, 8), ui.Paint()..color = colour);
    final image = await recorder.endRecording().toImage(8, 8);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$path').writeAsBytesSync(png!.buffer.asUint8List());
  }

  test('a material is pictured on a ball, and the picture is kept', () async {
    File(
      '${dir.path}/red.material.json',
    ).writeAsStringSync(const MaterialFile(color: 0xFFE53935).encode());

    final image = await pictures.of('red.material.json');
    expect(image, isNotNull);
    expect((image!.width, image.height), (64, 64));
    // The ball in the middle is red; the corner is not the ball.
    final pixels = await readPixels(image);
    final centre = pixels.atFraction(0.5, 0.5);
    final corner = pixels.atFraction(0.02, 0.02);
    expect(centre, isNot(corner));
    expect(centre[0], greaterThan(centre[2]), reason: 'red, not blue');
    expect(pictures.peek('red.material.json'), same(image));

    // A file that is no material has no picture.
    File('${dir.path}/broken.material.json').writeAsStringSync('nope');
    expect(await pictures.of('broken.material.json'), isNull);
  }, skip: skip);

  test('every shape, in every preset light', () async {
    const grey = MaterialFile(color: 0xFFB0B0B0, roughness: 0.5);
    final corners = <PreviewShape, List<int>>{};
    for (final shape in PreviewShape.values) {
      for (final lighting in PreviewLighting.values) {
        final image = await pictures.render(
          grey,
          shape: shape,
          lighting: lighting,
        );
        expect(image, isNotNull, reason: '${shape.name} ${lighting.name}');
        final pixels = await readPixels(image!);
        if (lighting == PreviewLighting.studio) {
          corners[shape] = pixels.atFraction(0.25, 0.25);
        }
      }
    }
    // The shapes fill the view differently.
    expect(corners.values.toSet().length, greaterThan(1));
  }, skip: skip);

  test('the light changes how it looks; the scene\'s own is used', () async {
    const white = MaterialFile(color: 0xFFFFFFFF, roughness: 0.6);
    Future<int> centreIn(PreviewLighting l, {RenderScene? scene}) async {
      final image = await pictures.render(white, lighting: l, scene: scene);
      return brightness((await readPixels(image!)).atFraction(0.5, 0.5));
    }

    final studio = await centreIn(PreviewLighting.studio);
    final night = await centreIn(PreviewLighting.night);
    expect(night, lessThan(studio));
    // A dark scene: no sun, no sky light.
    final dark = RenderScene();
    dark.sun.enabled = false;
    dark.environment
      ..sky = false
      ..ambientSky = (0, 0, 0)
      ..ambientGround = (0, 0, 0);
    expect(await centreIn(PreviewLighting.scene, scene: dark), lessThan(night));
  }, skip: skip);

  test('a changed map draws the pictures that use it again', () async {
    await writePng('tint.png', const ui.Color(0xFFFF0000));
    File('${dir.path}/tinted.material.json').writeAsStringSync(
      const MaterialFile(colorMap: 'tint.png', unlit: true).encode(),
    );
    final first = await pictures.of('tinted.material.json');
    final red = (await readPixels(first!)).atFraction(0.5, 0.5);
    expect(red[0], greaterThan(red[2]));

    await writePng('tint.png', const ui.Color(0xFF0000FF));
    final before = pictures.revision.value;
    pictures.forget('tint.png');
    expect(pictures.revision.value, greaterThan(before));
    final again = await pictures.of('tinted.material.json');
    expect(again, isNot(same(first)));
    final blue = (await readPixels(again!)).atFraction(0.5, 0.5);
    expect(blue[2], greaterThan(blue[0]));
  }, skip: skip);

  test('a variant is pictured over its parent', () async {
    File('${dir.path}/base.material.json').writeAsStringSync(
      const MaterialFile(color: 0xFF2040FF, unlit: true).encode(),
    );
    File('${dir.path}/variant.material.json').writeAsStringSync(
      const MaterialFile(parent: 'base.material.json').encode(),
    );
    final image = await pictures.of('variant.material.json');
    final centre = (await readPixels(image!)).atFraction(0.5, 0.5);
    expect(centre[2], greaterThan(centre[0]), reason: "the parent's blue");
    // The parent changed: its variant's picture goes stale too.
    final before = pictures.revision.value;
    pictures.forget('base.material.json');
    expect(pictures.revision.value, greaterThan(before));
  }, skip: skip);
}
