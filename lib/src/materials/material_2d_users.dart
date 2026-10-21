import 'dart:convert';

import 'package:just_editor_core/io.dart';

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

  // What each scene or prefab file draws with 2-D materials — every user
  // in it, by material — with the file's stamp when it was read (when it
  // changed and how big it is). Read again only once the stamp is another,
  // or the editor says it changed ([forget]): a whole folder of pictures
  // reads each file once, not once a picture.
  static final Map<String, (String, Map<String, List<Material2DUser>>)> _files =
      {};

  /// [path] (project-relative, under [root]) changed on disk: it is read
  /// again when next asked.
  static void forget(String root, String path) =>
      _files.remove('${_normal(root)}/$path');

  /// Everything drawn with the material at [path] in the scene and prefab
  /// files under [root]'s `assets` folder, sprites first, then shapes, in
  /// file order — those drawing the same (the same image, the same shape)
  /// as one, with how many they are ([Material2DUser.count]).
  static Future<List<Material2DUser>> findAll(String root, String path) async {
    final base = _normal(root);
    final folder = Directory('$base/assets');
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
    // Files gone since: nothing to keep of them.
    final listed = files.toSet();
    _files.removeWhere((p, _) => p.startsWith('$base/') && !listed.contains(p));
    final found = <String, Material2DUser>{};
    for (final p in files) {
      final users = await _usersIn(p, p.substring(base.length + 1));
      for (final user in users[path] ?? const <Material2DUser>[]) {
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

  // Every user in the file at [absolute] ([relative] to the project), by
  // the material it draws with; read once while the file stays as it is.
  static Future<Map<String, List<Material2DUser>>> _usersIn(
    String absolute,
    String relative,
  ) async {
    final file = File(absolute);
    String stamp;
    try {
      final stat = await file.stat();
      stamp = '${stat.modified.microsecondsSinceEpoch}:${stat.size}';
    } on FileSystemException {
      return const {};
    }
    final known = _files[absolute];
    if (known != null && known.$1 == stamp) return known.$2;
    final users = <String, List<Material2DUser>>{};
    try {
      final text = await file.readAsString();
      // Most files draw nothing with a 2-D material: not decoded.
      if (text.contains('Material2D')) {
        for (final entity in _entities(jsonDecode(text))) {
          for (final material in _materialsOf(entity)) {
            final user = _userOf(entity, material, relative);
            if (user != null) (users[material] ??= []).add(user);
          }
        }
      }
    } on Object {
      // Unreadable, or not JSON: no users in it.
    }
    _files[absolute] = (stamp, users);
    return users;
  }

  // The 2-D materials [entity] draws with.
  static Set<String> _materialsOf(Map<String, dynamic> entity) {
    final raw = entity['components'];
    final out = <String>{};
    for (final c in [if (raw is List) ...raw, if (raw is Map) ...raw.values]) {
      if (c is! Map<String, dynamic> || c['type'] != 'Material2D') continue;
      final fields = c['fields'];
      final material = fields is Map ? fields['material'] : null;
      if (material is String && material.isNotEmpty) out.add(material);
    }
    return out;
  }

  static String _normal(String root) {
    var r = root.replaceAll(r'\', '/');
    while (r.length > 1 && r.endsWith('/')) {
      r = r.substring(0, r.length - 1);
    }
    return r;
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
