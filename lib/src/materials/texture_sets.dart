import 'package:flutter/foundation.dart' show compute;
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths, ProjectFiles;
import 'package:just_game_engine/graphics_3d.dart';

import 'image_pixels.dart';
import 'normal_maps.dart';

/// What a map in a texture set is for, read from its file name.
enum TextureRole {
  colour('colour'),
  normal('normal'),
  roughness('roughness'),
  gloss('gloss'),
  metallic('metallic'),
  occlusion('occlusion'),

  /// Occlusion, roughness and metal in red, green and blue — glTF's own
  /// packing (also called ARM).
  orm('occlusion, roughness and metal'),
  emission('glow'),

  /// Height or displacement: not drawn by the engine; left out.
  height('height');

  const TextureRole(this.label);

  /// What it is, for a person.
  final String label;
}

/// One map of a [TextureSet]: its file and what it is for.
typedef TextureMap = ({String path, TextureRole role, bool directX});

/// Maps that belong together — `brick_albedo.png`, `brick_normal.png`,
/// `brick_roughness.png` — as a texture site or a painting tool exports
/// them, named [name].
final class TextureSet {
  TextureSet(this.name, this.folder, this.maps);

  /// What the maps' names share: `brick`.
  final String name;

  /// The folder they are in, project-relative.
  final String folder;

  /// Each map, by what it is for.
  final Map<TextureRole, TextureMap> maps;

  /// Whether its normal map is DirectX-style (green down), by its name.
  bool get directX => maps[TextureRole.normal]?.directX ?? false;

  @override
  String toString() =>
      '$name (${[for (final r in maps.keys) r.label].join(', ')})';
}

/// What importing a [TextureSet] made.
final class TextureSetImport {
  TextureSetImport(this.set, this.material, this.made, this.notes);

  final TextureSet set;

  /// The material file made, project-relative.
  final String material;

  /// The maps made for it — packed or turned over — project-relative.
  final List<String> made;

  /// What a person should know: a map left out, a size changed.
  final List<String> notes;
}

/// Texture sets: found by their file names, and made into materials.
abstract final class TextureSets {
  static const List<String> imageEndings = ['.png', '.jpg', '.jpeg', '.webp'];

  // Names a map's role goes by, lower case, longest first where they
  // share a start.
  static const Map<String, TextureRole> _one = {
    'albedo': TextureRole.colour,
    'basecolor': TextureRole.colour,
    'basecolour': TextureRole.colour,
    'diffuse': TextureRole.colour,
    'diff': TextureRole.colour,
    'color': TextureRole.colour,
    'colour': TextureRole.colour,
    'col': TextureRole.colour,
    'alb': TextureRole.colour,
    'normal': TextureRole.normal,
    'normalgl': TextureRole.normal,
    'normaldx': TextureRole.normal,
    'nor': TextureRole.normal,
    'nrm': TextureRole.normal,
    'norm': TextureRole.normal,
    'roughness': TextureRole.roughness,
    'rough': TextureRole.roughness,
    'rgh': TextureRole.roughness,
    'gloss': TextureRole.gloss,
    'glossiness': TextureRole.gloss,
    'metallic': TextureRole.metallic,
    'metalness': TextureRole.metallic,
    'metal': TextureRole.metallic,
    'met': TextureRole.metallic,
    'ao': TextureRole.occlusion,
    'ambientocclusion': TextureRole.occlusion,
    'occlusion': TextureRole.occlusion,
    'occ': TextureRole.occlusion,
    'orm': TextureRole.orm,
    'arm': TextureRole.orm,
    'emissive': TextureRole.emission,
    'emission': TextureRole.emission,
    'emit': TextureRole.emission,
    'glow': TextureRole.emission,
    'height': TextureRole.height,
    'disp': TextureRole.height,
    'displacement': TextureRole.height,
    'bump': TextureRole.height,
  };

  static const Map<String, TextureRole> _two = {
    'base color': TextureRole.colour,
    'base colour': TextureRole.colour,
    'ambient occlusion': TextureRole.occlusion,
    'normal gl': TextureRole.normal,
    'normal dx': TextureRole.normal,
    'nor gl': TextureRole.normal,
    'nor dx': TextureRole.normal,
  };

  static final RegExp _split = RegExp(r'[_\-. ]+');
  // After a map's role: sizes, formats and tile numbers (`_2k`, `_png`,
  // `.1001`) say nothing.
  static final RegExp _noise = RegExp(r'^(\d+k|\d+|png|jpe?g|webp|tga)$');
  // Before it — the set's own name — only sizes and formats: a plain number
  // there is part of the name (`rocks_02` and `rocks_04` are two sets).
  static final RegExp _stemNoise = RegExp(r'^(\d+k|png|jpe?g|webp|tga)$');

  /// What the image file called [name] is for, and the name of the set it
  /// belongs to; null when its name says nothing of a map.
  static (String, TextureRole, bool)? roleOf(String name) {
    final lower = name.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final base = dot < 0 ? name : name.substring(0, dot);
    final words = base.split(_split).where((w) => w.isNotEmpty).toList();
    // Sizes and formats at the end say nothing: `_2k`, `_png`.
    while (words.isNotEmpty && _noise.hasMatch(words.last.toLowerCase())) {
      words.removeLast();
    }
    if (words.isEmpty) return null;
    TextureRole? role;
    var take = 0;
    var directX = false;
    if (words.length >= 2) {
      final pair =
          '${words[words.length - 2].toLowerCase()} '
          '${words.last.toLowerCase()}';
      if (_two[pair] case final r?) {
        role = r;
        take = 2;
        directX = pair.endsWith(' dx');
      }
    }
    if (role == null) {
      final last = words.last.toLowerCase();
      if (_one[last] case final r?) {
        role = r;
        take = 1;
        directX = last == 'normaldx';
      }
    }
    if (role == null) return null;
    final stem = words.sublist(0, words.length - take);
    while (stem.isNotEmpty && _stemNoise.hasMatch(stem.last.toLowerCase())) {
      stem.removeLast();
    }
    return (stem.join('_'), role, directX);
  }

  /// The texture sets among [paths] (project-relative image files): maps
  /// grouped by the name they share, each set in the folder its maps are
  /// in. A set needs more than one map, or a colour map. Where two files
  /// are the same map of a set, the first by name is taken, whatever order
  /// [paths] are in.
  static List<TextureSet> find(Iterable<String> paths) {
    final sets = <(String, String), Map<TextureRole, TextureMap>>{};
    for (final path in [...paths]..sort()) {
      final lower = path.toLowerCase();
      if (!imageEndings.any(lower.endsWith)) continue;
      final slash = path.lastIndexOf('/');
      final folder = slash < 0 ? '' : path.substring(0, slash);
      final name = path.substring(slash + 1);
      final found = roleOf(name);
      if (found == null) continue;
      final (stem, role, directX) = found;
      final key = (folder, stem.isEmpty ? _lastOf(folder) : stem);
      (sets[key] ??= {}).putIfAbsent(
        role,
        () => (path: path, role: role, directX: directX),
      );
    }
    return [
      for (final MapEntry(key: (folder, name), value: maps) in sets.entries)
        if (maps.length > 1 || maps.containsKey(TextureRole.colour))
          TextureSet(name, folder, maps),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  static String _lastOf(String folder) {
    final slash = folder.lastIndexOf('/');
    final last = folder.substring(slash + 1);
    return last.isEmpty ? 'material' : last;
  }

  /// The texture sets in [folder] (project-relative) under [root], its
  /// own files only.
  static List<TextureSet> inFolder(String root, String folder) {
    final dir = Directory(PackageAssetPaths.of(root).absolute(folder));
    if (!dir.existsSync()) return const [];
    final base = folder.endsWith('/') ? folder : '$folder/';
    return find([
      for (final f in dir.listSync().whereType<File>())
        '$base${f.uri.pathSegments.last}',
    ]);
  }

  /// Makes a material of [set] under [root]:
  /// - roughness (or gloss, turned over), metal and occlusion packed into
  ///   one `<name>_orm.png` — occlusion red, roughness green, metal blue,
  ///   as the engine reads them — the sizes made to match;
  /// - a DirectX normal map turned into an OpenGL one, `<name>_normal_gl.png`
  ///   (when [flipDirectX]);
  /// - the material, `<name>.material.json` (`_2` and on when that is
  ///   taken), naming its maps.
  ///
  /// Never writes over a file there already.
  static Future<TextureSetImport> make(
    String root,
    TextureSet set, {
    bool flipDirectX = true,
  }) async {
    final made = <String>[];
    final notes = <String>[];
    String at(String name) => set.folder.isEmpty ? name : '${set.folder}/$name';
    String free(String stem, String ending) {
      var n = 1;
      String path() => at('$stem${n == 1 ? '' : '_$n'}$ending');
      while (File('$root/${path()}').existsSync()) {
        n++;
      }
      return path();
    }

    final maps = set.maps;
    if (maps.containsKey(TextureRole.height)) {
      notes.add(
        'The height map ${_name(maps[TextureRole.height]!.path)} was left '
        'out: the engine draws normal maps, not heights.',
      );
    }

    // The normal map, turned over when it is DirectX's.
    var normal = maps[TextureRole.normal]?.path ?? '';
    if (normal.isNotEmpty && set.directX && flipDirectX) {
      // Off the UI's isolate: a 4K map is millions of pixels.
      final flipped = await compute(
        NormalMaps.flipGreen,
        await Pixels.read('$root/$normal'),
      );
      final out = free('${set.name}_normal_gl', '.png');
      await flipped.writePng('$root/$out');
      made.add(out);
      notes.add('${_name(normal)} is DirectX-style: turned over into $out.');
      normal = out;
    }

    // Occlusion, roughness and metal.
    var metalRough = '', occlusion = '';
    var metallic = 0.0, roughness = 0.5;
    final orm = maps[TextureRole.orm]?.path;
    final rough = maps[TextureRole.roughness] ?? maps[TextureRole.gloss];
    final metal = maps[TextureRole.metallic];
    final ao = maps[TextureRole.occlusion];
    if (orm != null) {
      metalRough = occlusion = orm;
      metallic = 1;
      roughness = 1;
    } else if (rough != null || metal != null) {
      final parts = [?rough, ?metal, ?ao];
      var w = 0, h = 0;
      for (final p in parts) {
        final (pw, ph) = await Pixels.sizeOf('$root/${p.path}');
        if (pw * ph > w * h) (w, h) = (pw, ph);
      }
      Future<Pixels?> read(TextureMap? m) async {
        if (m == null) return null;
        final px = await Pixels.read('$root/${m.path}', width: w, height: h);
        final (pw, ph) = await Pixels.sizeOf('$root/${m.path}');
        if (pw != w || ph != h) {
          notes.add('${_name(m.path)} was scaled to $w × $h to pack it.');
        }
        return px;
      }

      final r = await read(rough), m = await read(metal), o = await read(ao);
      final gloss = rough?.role == TextureRole.gloss;
      final packed = await compute(_pack, (w, h, o, r, m, gloss));
      final out = free('${set.name}_orm', '.png');
      await packed.writePng('$root/$out');
      made.add(out);
      metalRough = out;
      if (ao != null) occlusion = out;
      metallic = metal == null ? 0 : 1;
      roughness = rough == null ? 0.5 : 1;
      if (gloss) notes.add('${_name(rough!.path)} is gloss: turned over.');
    } else if (ao != null) {
      occlusion = ao.path;
    }

    final emission = maps[TextureRole.emission]?.path ?? '';
    final file = MaterialFile(
      colorMap: maps[TextureRole.colour]?.path ?? '',
      normalMap: normal,
      metalRoughMap: metalRough,
      occlusionMap: occlusion,
      emissionMap: emission,
      emission: emission.isEmpty ? 0xFF000000 : 0xFFFFFFFF,
      metallic: metallic,
      roughness: roughness,
    );
    final path = free(set.name, MaterialFile.ending);
    await ProjectFiles.writeString('$root/$path', file.encode());
    return TextureSetImport(set, path, made, notes);
  }

  // Occlusion, roughness (or gloss, turned over) and metal packed into red,
  // green and blue, [w] × [h]: on another isolate.
  static Pixels _pack((int, int, Pixels?, Pixels?, Pixels?, bool) job) {
    final (w, h, o, r, m, gloss) = job;
    final packed = Pixels(w, h);
    for (var i = 0; i < w * h; i++) {
      final p = i * 4;
      packed.rgba[p] = o?.rgba[p] ?? 255;
      packed.rgba[p + 1] = r == null
          ? 255
          : gloss
          ? 255 - r.rgba[p]
          : r.rgba[p];
      packed.rgba[p + 2] = m?.rgba[p] ?? 0;
      packed.rgba[p + 3] = 255;
    }
    return packed;
  }

  static String _name(String path) => path.substring(path.lastIndexOf('/') + 1);
}
