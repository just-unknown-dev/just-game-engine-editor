import 'package:just_game_engine/just_game_engine.dart' as jge;

/// A named draw-order layer the designer offers.
///
/// Layers are an editor concept in every 2D game — something has to be behind
/// something else — so the editor ships three sensible ones. A project that
/// wants different names or a different depth ordering registers its own.
class LayerPreset {
  const LayerPreset({
    required this.id,
    required this.order,
    this.label,
    this.description,
  });

  /// Matches [LayerComponent.layerId].
  final String id;

  /// Draw order. Lower draws first (further back).
  final int order;

  /// Display name; defaults to [id].
  final String? label;

  /// Tooltip.
  final String? description;

  /// Name shown in the layers panel.
  String get displayLabel => label ?? id;
}

/// The layers available in the designer.
class LayerPresetRegistry {
  LayerPresetRegistry();

  final Map<String, LayerPreset> _presets = {};

  /// All registered layers, back to front.
  List<LayerPreset> get all {
    final sorted = _presets.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return List.unmodifiable(sorted);
  }

  /// Looks up a layer by id.
  LayerPreset? byId(String id) => _presets[id];

  /// Draw order for [layerId].
  ///
  /// Unregistered layers sort with [LevelLayers.main], so a layer found on an
  /// entity but never declared still lands somewhere sensible rather than at
  /// one extreme.
  int orderOf(String layerId) =>
      _presets[layerId]?.order ?? jge.LevelLayers.main;

  /// Registers [preset], replacing any existing one with the same id.
  void register(LayerPreset preset) => _presets[preset.id] = preset;

  /// Registers several layers.
  void registerAll(Iterable<LayerPreset> presets) {
    for (final preset in presets) {
      register(preset);
    }
  }

  /// Removes every registration, ahead of rebuilding from extensions.
  void clear() => _presets.clear();

  /// The layers the editor itself provides.
  static const List<LayerPreset> builtIn = [
    LayerPreset(
      id: 'background',
      order: jge.LevelLayers.background,
      description: 'Scenery behind the level',
    ),
    LayerPreset(
      id: 'main',
      order: jge.LevelLayers.main,
      description: 'Level geometry, actors and pickups',
    ),
    LayerPreset(
      id: 'foreground',
      order: jge.LevelLayers.foreground,
      description: 'Drawn over everything, including the player',
    ),
  ];
}
