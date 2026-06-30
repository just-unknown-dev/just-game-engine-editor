import 'package:just_game_engine/just_game_engine.dart';

import '../generator/component_registry.dart';
import '../components/editor_components_registrant.dart';

/// A single entry in the component picker catalogue.
class ComponentEntry {
  const ComponentEntry({
    required this.name,
    required this.group,
    required this.description,
    required this.factory,
    this.componentTypeName,
  });

  final String name;
  final String group;
  final String description;
  final String? componentTypeName;

  /// Produces a new component instance with sensible editor defaults.
  final Component Function() factory;
}

/// Groups used to categorise the component list in the picker.
const List<String> kComponentGroups = [
  'Core',
  'Rendering',
  'Physics',
  'Gameplay',
  'Input',
  'Camera',
  'Audio',
  'Animation',
  'Hierarchy',
  'Effects',
  'UI',
];

bool _registered = false;

/// Returns all available component entries for the picker, derived from
/// the pre-built descriptor registry.
List<ComponentEntry> getComponentRegistryEntries() {
  if (!_registered) {
    registerAllEditorComponents();
    _registered = true;
  }

  return CustomComponentRegistry.instance.descriptors
      .map(
        (d) => ComponentEntry(
          name: d.name,
          group: d.group ?? 'Core',
          description: d.description ?? '',
          factory: d.factory,
          componentTypeName: d.type,
        ),
      )
      .toList();
}
