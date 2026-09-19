import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import 'field_editor.dart';

/// A button in a component's inspector header.
class InspectorAction {
  const InspectorAction({
    required this.id,
    required this.label,
    required this.run,
    this.icon,
  });

  final String id;
  final String label;
  final IconData? icon;

  /// Runs the action for [component]; the inspector refreshes afterwards.
  final Future<void> Function(BuildContext context, jge.Component component)
  run;
}

/// Editor-only additions to how one component type is inspected, keyed by
/// its definition's `type`.
///
/// The runtime definition says what a component *is*; this says what the
/// editor can do with it beyond editing fields: actions in its header, a
/// custom widget under its fields, or a replacement editor for one field.
/// It lives in the editor, so the runtime package never carries it.
class ComponentEditorExtras {
  const ComponentEditorExtras({
    required this.type,
    this.actions = const [],
    this.section,
    this.fieldEditors = const {},
    this.summary,
  });

  /// The definition type this decorates.
  final String type;

  /// Header buttons, in order.
  final List<InspectorAction> actions;

  /// Drawn under the fields.
  final Widget Function(BuildContext context, jge.Component component)? section;

  /// Replacement editors by field name, ahead of the type's own.
  final Map<String, FieldEditorBuilder> fieldEditors;

  /// One line about a component's current state, for the chrome that has
  /// room for no more: the timeline dock names the animation clip this way.
  final String Function(jge.Component component)? summary;

  /// These extras merged with [other]'s: actions appended, field editors
  /// overlaid, the later section winning.
  ComponentEditorExtras merge(ComponentEditorExtras other) =>
      ComponentEditorExtras(
        type: type,
        actions: [...actions, ...other.actions],
        section: other.section ?? section,
        fieldEditors: {...fieldEditors, ...other.fieldEditors},
        summary: other.summary ?? summary,
      );
}

/// The extras registered with one editor, merged per type.
class ComponentExtrasRegistry {
  ComponentExtrasRegistry();

  final Map<String, ComponentEditorExtras> _byType = {};

  /// Adds [extras] to whatever is already registered for its type.
  void register(ComponentEditorExtras extras) {
    final existing = _byType[extras.type];
    _byType[extras.type] = existing == null ? extras : existing.merge(extras);
  }

  /// Registers several.
  void registerAll(Iterable<ComponentEditorExtras> all) =>
      all.forEach(register);

  /// The merged extras for [type], or null.
  ComponentEditorExtras? forType(String type) => _byType[type];

  /// Forgets everything.
  void clear() => _byType.clear();
}
