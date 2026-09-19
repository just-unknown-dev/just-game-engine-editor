import 'package:just_game_engine/just_game_engine.dart';

import '../../scope/editor_scope.dart';

/// A single entry in the component picker catalogue.
class ComponentEntry {
  const ComponentEntry({
    required this.name,
    required this.group,
    required this.description,
    required this.factory,
    this.componentTypeName,
    this.allowMultiple = false,
  });

  final String name;
  final String group;
  final String description;
  final String? componentTypeName;

  /// Whether an entity may carry more than one.
  final bool allowMultiple;

  /// Produces a new component instance with sensible editor defaults.
  final Component Function() factory;
}

/// Every component the picker can add: each runtime definition the scope
/// knows.
List<ComponentEntry> getComponentRegistryEntries(EditorScope scope) => [
  for (final d in scope.definitions.definitions)
    ComponentEntry(
      name: d.hints.name ?? d.type,
      group: d.hints.group ?? 'Core',
      description: d.hints.description ?? '',
      factory: d.create,
      componentTypeName: d.type,
      allowMultiple: d.hints.allowMultiple,
    ),
];
