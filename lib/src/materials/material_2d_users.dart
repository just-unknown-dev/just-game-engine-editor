import 'dart:convert';
import 'dart:io';

/// Something in the project drawn with a 2-D material: an entity of a scene
/// or prefab file with a `Material2D` naming it — what the material is shown
/// on when its preview picks the game's own ([Material2DUsers.find]).
final class Material2DUser {
  const Material2DUser({
    required this.file,
    required this.entity,
    this.spritePath,
    this.shape,
    this.pixelArt = false,
    this.count = 1,
  });

  /// The scene or prefab file it is in, from the project folder.
  final String file;

  /// The entity's name ('' for none).
  final String entity;

  /// The image a sprite draws, from the project folder; null for a shape.
  final String? spritePath;

  /// A shape's saved components (`{type, fields}` each), but its place and
  /// its material: what the preview draws it from. Null for a sprite.
  final List<Map<String, dynamic>>? shape;

  /// Whether a sprite is pixel art: drawn crisp when magnified.
  final bool pixelArt;

  /// How many entities draw the same — the same image, or the same shape —
  /// of which this is the first.
  final int count;

  Material2DUser _times(int count) => Material2DUser(
    file: file,
    entity: entity,
    spritePath: spritePath,
    shape: shape,
    pixelArt: pixelArt,
    count: count,
  );

  // What it draws: users drawing the same are one.
  String get _drawing => spritePath ?? jsonEncode(shape);

  /// Where it is, for the preview to say: its name, and the file's.
  String get label {
    final name = file.split('/').last.split('.').first;
    return entity.isEmpty ? name : '$entity ($name)';
  }
}

/// Finds what in the project draws with a 2-D material.
abstract final class Material2DUsers {
  // What a user's own drawing is not.
  static const Set<String> _notDrawn = {
    'TransformComponent',
    'Material2D',
    'LayerComponent',
    'ShadowCaster2D',
  };

  /// The first sprite, or else the first shape, drawn with the material at
  /// [path] in the scene and prefab files under [root]'s `assets` folder;
  /// null when nothing is. A sprite from an atlas is passed over: its
  /// frame is the atlas's to say.
  static Future<Material2DUser?> find(String root, String path) async =>
      (await findAll(root, path)).firstOrNull;

  /// Everything drawn with the material at [path] in the scene and prefab
  /// files under [root]'s `assets` folder, sprites first, then shapes, in
  /// file order — those drawing the same (the same image, the same shape)
  /// as one, with how many they are ([Material2DUser.count]).
  static Future<List<Material2DUser>> findAll(String root, String path) async {
    final folder = Directory('$root/assets');
    if (!await folder.exists()) return const [];
    final files = <String>[];
    await for (final f in folder.list(recursive: true, followLinks: false)) {
      if (f is! File) continue;
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.json') || p.endsWith('material2d.json')) continue;
      if (p.endsWith('.material.json')) continue;
      files.add(p);
    }
    files.sort();
    final found = <String, Material2DUser>{};
    for (final p in files) {
      final String text;
      try {
        text = await File(p).readAsString();
      } on Object {
        continue;
      }
      if (!text.contains(path)) continue;
      final Object? json;
      try {
        json = jsonDecode(text);
      } on Object {
        continue;
      }
      final relative = p.substring(root.replaceAll(r'\', '/').length + 1);
      for (final entity in _entities(json)) {
        final user = _userOf(entity, path, relative);
        if (user == null) continue;
        final known = found[user._drawing];
        found[user._drawing] = known == null
            ? user
            : known._times(known.count + 1);
      }
    }
    return [
      ...found.values.where((u) => u.spritePath != null),
      ...found.values.where((u) => u.spritePath == null),
    ];
  }

  // Every map with components, at any depth (children included).
  static Iterable<Map<String, dynamic>> _entities(Object? json) sync* {
    if (json is Map<String, dynamic>) {
      if (json['components'] != null) yield json;
      for (final v in json.values) {
        yield* _entities(v);
      }
    } else if (json is List) {
      for (final v in json) {
        yield* _entities(v);
      }
    }
  }

  static Material2DUser? _userOf(
    Map<String, dynamic> entity,
    String path,
    String file,
  ) {
    final raw = entity['components'];
    final components = <Map<String, dynamic>>[
      if (raw is List)
        for (final c in raw)
          if (c is Map<String, dynamic>) c,
      if (raw is Map)
        for (final c in raw.values)
          if (c is Map<String, dynamic>) c,
    ];
    Map<String, dynamic>? fieldsOf(Map<String, dynamic> c) {
      final f = c['fields'];
      return f is Map<String, dynamic> ? f : null;
    }

    final usesIt = components.any(
      (c) => c['type'] == 'Material2D' && fieldsOf(c)?['material'] == path,
    );
    if (!usesIt) return null;
    final name = entity['name'] is String ? entity['name'] as String : '';
    for (final c in components) {
      if (c['type'] != 'SpriteComponent') continue;
      final f = fieldsOf(c) ?? const {};
      final image = f['spritePath'];
      final atlas = f['atlasPath'];
      if (image is String &&
          image.isNotEmpty &&
          (atlas is! String || atlas.isEmpty)) {
        return Material2DUser(
          file: file,
          entity: name,
          spritePath: image,
          pixelArt: f['pixelArt'] == true,
        );
      }
      return null;
    }
    final drawn = [
      for (final c in components)
        if (!_notDrawn.contains(c['type'])) c,
    ];
    if (drawn.isEmpty) return null;
    return Material2DUser(file: file, entity: name, shape: drawn);
  }
}
