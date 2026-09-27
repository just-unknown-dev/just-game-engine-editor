import 'dart:ui' as ui;

import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_tiled/just_tiled.dart' as tiled;

import 'tiled_import.dart';

/// [to] as a path from the folder [fromDir], both project-relative:
/// `../tilesets/grass.png`.
String relativePath(String fromDir, String to) {
  final from = fromDir.split('/').where((p) => p.isNotEmpty).toList();
  final target = to.split('/').where((p) => p.isNotEmpty).toList();
  var common = 0;
  while (common < from.length &&
      common < target.length - 1 &&
      from[common] == target[common]) {
    common++;
  }
  return [
    for (var i = common; i < from.length; i++) '..',
    ...target.skip(common),
  ].join('/');
}

/// Writes tile maps as Tiled files, to open in Tiled: the map as a `.tmx`
/// (or `.tmj`), each of its tilesets as a `.tsx` (`.tsj`) beside it, with
/// paths relative to the files, as Tiled keeps them. A built-in tileset's
/// picture, which is no file, is written beside them as a `.png`.
class TiledExporter {
  TiledExporter(this.files);

  final TiledFiles files;

  /// Writes [map] to [to]; its tilesets come from [tilesetAt]. Returns the
  /// files written, the map last.
  Future<List<String>> export(
    LevelMapData map, {
    required String to,
    required TilesetData? Function(int slot) tilesetAt,
  }) async {
    final json = to.toLowerCase().endsWith('.tmj');
    final dir = TileAssets.directoryOf(to);
    final tilesets = [
      for (var slot = 0; slot < map.tilesets.length; slot++)
        map.tilesets[slot] == null ? null : tilesetAt(slot),
    ];
    final names = <int, String>{};
    final images = <int, String>{};
    final taken = <String>{};
    final written = <String>[];
    String inDir(String file) => dir.isEmpty ? file : '$dir/$file';
    for (var slot = 0; slot < tilesets.length; slot++) {
      final ts = tilesets[slot];
      if (ts == null) continue;
      final path = map.tilesets[slot]!;
      final stem = tiledStem(
        BuiltInTilesets.isBuiltIn(path)
            ? path.substring(BuiltInTilesets.prefix.length)
            : path,
      );
      var name = stem;
      for (var n = 2; !taken.add(name); n++) {
        name = '${stem}_$n';
      }
      final file = '$name.${json ? 'tsj' : 'tsx'}';
      names[slot] = file;
      var image = relativePath(dir, ts.image);
      final drawn = BuiltInTilesets.image(ts.image);
      if (drawn != null) {
        final png = await drawn.toByteData(format: ui.ImageByteFormat.png);
        if (png != null) {
          image = '$name.png';
          await files.writeBytes(inDir(image), png.buffer.asUint8List());
          written.add(inDir(image));
        }
      }
      images[slot] = image;
      final out = TiledInterop.exportTileset(
        ts,
        imageSource: image,
        source: file,
      );
      await files.write(
        inDir(file),
        json ? tiled.TmjWriter.writeTileset(out) : tiled.TsxWriter.write(out),
      );
      written.add(inDir(file));
    }
    final out = TiledInterop.exportMap(
      map,
      tilesets,
      imageSource: (slot) =>
          images[slot] ?? relativePath(dir, tilesets[slot]!.image),
      tilesetSource: (slot) => names[slot],
    );
    await files.write(
      to,
      json ? tiled.TmjWriter.write(out) : tiled.TmxWriter.write(out),
    );
    return [...written, to];
  }
}
