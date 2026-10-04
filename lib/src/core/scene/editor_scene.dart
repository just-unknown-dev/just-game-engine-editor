/// The scene open in the editor, as its file's header holds it.
library;

import 'package:just_game_engine/just_game_engine.dart';

/// A scene's name and how it is authored — the `name` and `mode` a scene
/// file keeps beside its `entities`.
///
/// The scene itself is its entities in the world; this is only what the
/// editor needs to know about the file they came from and go back to.
class EditorScene {
  EditorScene({required this.name, this.mode = SceneMode.twoD});

  /// Reads the header of a scene file (see [toJson]).
  factory EditorScene.fromJson(Map<String, dynamic> json) => EditorScene(
    name: json['name'] as String,
    mode: SceneMode.fromId(json['mode']),
  );

  /// The scene's name — its file is `<name>.scene.json`.
  final String name;

  /// 2-D (the default) or 3-D. Only an editor reads it; every entity has a
  /// 3-D transform either way.
  SceneMode mode;

  /// The header fields a scene file starts with.
  Map<String, dynamic> toJson() => {'name': name, 'mode': mode.id};
}
