import 'package:just_game_engine/just_game_engine.dart';

/// Encodes and decodes components for one editor, through the engine's
/// definition registry.
///
/// The same registry the shipped game loads with, so the editor and the game
/// cannot disagree about what a saved level means. A component with no
/// definition is not saved — the save path warns instead of silently writing
/// something the game would then refuse to load.
class SceneCodec {
  const SceneCodec(this.definitions);

  /// Over the process-wide registry the game registers into at boot.
  static SceneCodec get global =>
      SceneCodec(ComponentDefinitionRegistry.instance);

  /// Where component definitions come from.
  final ComponentDefinitionRegistry definitions;

  /// Encodes [component], or null if it has no definition.
  Map<String, dynamic>? encode(Component component) =>
      definitions.encode(component);

  /// Decodes [json], or null if its type is unknown.
  Component? decode(Map<String, dynamic> json) => definitions.decode(json);

  /// Whether [component] would be saved.
  bool canEncode(Component component) => definitions.canEncode(component);

  /// Encodes [entities] the way a scene file stores them.
  ///
  /// Inactive entities are skipped, and so are components with no
  /// definition — runtime-only state such as a physics body handle.
  List<Map<String, dynamic>> encodeEntities(List<Entity> entities) {
    final active = entities.where((e) => e.isActive).toList();
    final names = {for (final e in active) e.id: e.name ?? 'entity_${e.id}'};
    return [
      for (final e in active)
        {
          'name': e.name,
          'parentName': switch (e.getComponent<ParentComponent>()?.parentId) {
            final id? => names[id],
            null => null,
          },
          'components': e.components
              .map(encode)
              .whereType<Map<String, dynamic>>()
              .toList(),
        },
    ];
  }

  /// The definition [component] is saved and inspected through, or null.
  ComponentDefinition? definitionFor(Component component) =>
      definitions.definitionFor(component);
}
