import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/view/ray_entity_picker.dart';
import '../ui/level_designer/state/prefab_registry.dart';

/// Another way to offer prefabs that are already there: each prefab it
/// [appliesTo] is offered again with [extra] components added — a physics
/// module's "Solid" and "Trigger" of every shape another module offers,
/// without either knowing the other.
///
/// The variant of a prefab with id `cube` is `solid:cube`, named
/// "Solid Cube", in [category].
final class PrefabVariant {
  /// A variant called [name].
  const PrefabVariant({
    required this.id,
    required this.name,
    required this.category,
    required this.appliesTo,
    required this.extra,
    this.icon,
    this.description,
  });

  /// Stable identifier: the prefix of its prefabs' ids.
  final String id;

  /// What goes before a prefab's name: `Solid`.
  final String name;

  /// Where its prefabs are listed: `Solid shapes`.
  final String category;

  /// Whether a prefab whose components are [components] has this variant.
  final bool Function(List<jge.Component> components) appliesTo;

  /// The components it adds, fresh each call.
  final List<jge.Component> Function() extra;

  /// Its prefabs' icon; the prefab's own when null.
  final IconData? icon;

  /// One line for a tooltip; the prefab's own when null.
  final String? description;

  /// Whether [prefab] has this variant: built once, its components asked.
  bool offersFor(PrefabDefinition prefab) => appliesTo(
    prefab.buildAt?.call(SurfacePoint(jge.Vector3.zero(), jge.Vector3(0, -1, 0))) ??
        prefab.build(Offset.zero, prefab.defaultSize),
  );

  /// [prefab] made this way.
  PrefabDefinition of(PrefabDefinition prefab) {
    final buildAt = prefab.buildAt;
    return PrefabDefinition(
      id: '$id:${prefab.id}',
      name: '$name ${prefab.name}',
      category: category,
      icon: icon ?? prefab.icon,
      color: prefab.color,
      placement: prefab.placement,
      defaultSize: prefab.defaultSize,
      description: description ?? prefab.description,
      namePrefix: prefab.namePrefix ?? prefab.id,
      depth: prefab.depth,
      dimensions: prefab.dimensions,
      build: (position, size) => [...prefab.build(position, size), ...extra()],
      buildAt: buildAt == null ? null : (at) => [...buildAt(at), ...extra()],
    );
  }
}
