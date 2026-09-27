import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

/// How a prefab is created in the viewport.
enum PrefabPlacement {
  /// Drag a rectangle; the prefab is sized to fit it. Level geometry.
  dragRect,

  /// Single click; the prefab keeps its own size. Spawn points, pickups.
  point,
}

/// A ready-made entity the Level Designer can stamp into a level.
///
/// [build] returns fresh component instances every call — returning shared
/// ones would make every copy of a prefab alias the same state, so moving one
/// platform would move them all.
class PrefabDefinition {
  const PrefabDefinition({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.build,
    this.placement = PrefabPlacement.dragRect,
    this.defaultSize = const Size(128, 32),
    this.description,
    this.namePrefix,
    this.aliases = const [],
    this.depth,
  });

  /// Stable identifier, used by the palette selection and in saved designer
  /// state. Changing it orphans anything that referenced it.
  final String id;

  /// Display name.
  final String name;

  /// Palette grouping, e.g. 'Geometry', 'Hazards', 'Actors'.
  final String category;

  /// Palette icon.
  final IconData icon;

  /// Accent colour, also used to tint the drag preview so the author can see
  /// what they are about to place before releasing.
  final Color color;

  /// How it is placed.
  final PrefabPlacement placement;

  /// Size used for [PrefabPlacement.point], and the drag preview's starting
  /// size.
  final Size defaultSize;

  /// One-line explanation for the palette tooltip.
  final String? description;

  /// Base for generated entity names; defaults to [id] when unset.
  final String? namePrefix;

  /// Other names its class goes by, besides its [id] and [name] — what a
  /// Tiled map commonly calls it: `spikes`, `spring`. Importing a Tiled
  /// map, an object whose class is one of them becomes this prefab. Any
  /// case.
  final List<String> aliases;

  /// Builds the components for one instance, sized to [size] and centred at
  /// [position].
  final List<jge.Component> Function(Offset position, Size size) build;

  /// The depth it is placed at, whatever depth is active — a background
  /// decoration's `background`; null for the one being placed at.
  final String? depth;
}

/// The palette of prefabs available in the Level Designer.
///
/// A registry a project extends so it can add to the
/// palette with its own entity types rather than being limited to the
/// built-ins — a template is a starting point, not a ceiling.
class PrefabRegistry {
  PrefabRegistry();

  final Map<String, PrefabDefinition> _prefabs = {};

  /// All registered prefabs, in registration order.
  List<PrefabDefinition> get all => List.unmodifiable(_prefabs.values);

  /// Registered prefabs grouped by [PrefabDefinition.category], preserving
  /// registration order within each group.
  Map<String, List<PrefabDefinition>> get byCategory {
    final grouped = <String, List<PrefabDefinition>>{};
    for (final prefab in _prefabs.values) {
      grouped.putIfAbsent(prefab.category, () => []).add(prefab);
    }
    return grouped;
  }

  /// Looks up a prefab by [PrefabDefinition.id].
  PrefabDefinition? byId(String id) => _prefabs[id];

  /// Registers [prefab], replacing any existing one with the same id.
  void register(PrefabDefinition prefab) => _prefabs[prefab.id] = prefab;

  /// Registers several prefabs.
  void registerAll(Iterable<PrefabDefinition> prefabs) {
    for (final prefab in prefabs) {
      register(prefab);
    }
  }

  /// Removes every registration. Called before re-registering on hot reload,
  /// so edited prefab definitions actually take effect.
  void clear() => _prefabs.clear();
}
