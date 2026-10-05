import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import '../widgets/scrubbable_number_field.dart' show NumberScrubConfig;
import 'field_rows.dart';
import 'live_preview.dart';

/// Builds the inspector control for one field.
/// What [component]'s unset colour field [field] falls back to, or null
/// when this lookup has nothing to say about it.
typedef InheritedColor =
    ({Color color, String from})? Function(
      jge.Component component,
      String field,
    );

typedef FieldEditorBuilder = Widget Function(FieldEditorContext context);

/// Everything a field editor is given: the field, its hint, the live value,
/// and how to write it back.
class FieldEditorContext {
  const FieldEditorContext({
    required this.field,
    required this.hint,
    required this.value,
    required this.component,
    required this.onChanged,
    required this.editors,
    this.readOnly = false,
    this.entityNames,
    this.world,
    this.sceneState,
    this.scope,
    this.preview,
  });

  /// The definition field being edited: name, kind, limits, read/write.
  final jge.SchemaField field;

  /// How the definition wants it shown.
  final jge.FieldHint hint;

  /// The current value, as [jge.SchemaField.read] returned it.
  final Object? value;

  /// The component the field belongs to.
  final jge.Component component;

  /// Writes a new value; the caller records the edit and refreshes.
  final ValueChanged<Object?> onChanged;

  /// The registry this editor was resolved from, so a compound editor (a
  /// vector, a shape) can build its parts from the same registry.
  final FieldEditorRegistry editors;

  /// Whether the field cannot be written right now.
  final bool readOnly;

  /// The names of the scene's entities, for a field that refers to one.
  /// Null where there is no scene to ask.
  final List<String> Function()? entityNames;

  /// The world the inspector is editing, and its selection, when that is
  /// not the scene's — a screen in the interface editor. A field that
  /// points at other entities looks them up here, not in the level.
  final jge.World? world;
  final EditorSceneState? sceneState;

  /// The editor the inspector belongs to — its tag list, its spawners.
  /// Null where there is none to ask.
  final EditorScope? scope;

  /// Shows a value in the scene without recording it, for a control that
  /// previews as it goes — a colour picker — before [onChanged] records
  /// the one kept. Null where the field cannot be written.
  final LivePreview? preview;

  /// Label to show: the hint's, else the field name.
  String get label => hint.label ?? field.name;

  /// Drag-to-scrub feel for a numeric field: the hint's step and precision,
  /// the definition's limits. Null when nothing asked for scrubbing.
  NumberScrubConfig? get scrub {
    final s = hint.scrub;
    if (s == null && field.min == null && field.max == null) return null;
    return NumberScrubConfig(
      step: s?.step ?? 1.0,
      pixelsPerStep: s?.pixelsPerStep ?? 12.0,
      fractionDigits: s?.fractionDigits ?? 2,
      integer: s?.integer ?? field.kind.id == jge.FieldTypes.integer.id,
      min: field.min,
      max: field.max,
      suffix: s?.suffix,
    );
  }

  /// This context with a different value or writer, for a compound editor's
  /// parts.
  FieldEditorContext copyWith({
    jge.SchemaField? field,
    jge.FieldHint? hint,
    Object? value,
    ValueChanged<Object?>? onChanged,
  }) => FieldEditorContext(
    field: field ?? this.field,
    hint: hint ?? this.hint,
    value: value ?? this.value,
    component: component,
    onChanged: onChanged ?? this.onChanged,
    editors: editors,
    readOnly: readOnly,
    entityNames: entityNames,
    world: world,
    sceneState: sceneState,
    scope: scope,
    // A part writes a different value than the whole; previewing through
    // the whole's would write the wrong thing.
    preview: onChanged == null ? preview : null,
  );
}

/// Which control edits which [jge.FieldType], by type id.
///
/// The editor registers one per built-in type; a module registers editors
/// for its own types (`'platformer.waypoints'`, say), or replaces a built-in
/// with `override: true`. A field whose type has no editor is still shown,
/// read-only, saying so: a project cannot end up with a field that exists on
/// disk but is invisible in the inspector.
class FieldEditorRegistry {
  FieldEditorRegistry();

  /// The key the editor for any [jge.EnumFieldType] is found under when its
  /// own id has none.
  static const String enumKey = 'enum';

  final Map<String, FieldEditorBuilder> _byTypeId = {};

  /// What an unset colour falls back to, asked in turn until one answers —
  /// a theme's panel colour, say. Modules add theirs through
  /// `EditorModule.inheritedColors`.
  final List<InheritedColor> inheritedColors = [];

  /// What [component]'s unset colour field [field] is drawn with, and what
  /// to call that — or null when unset means none at all.
  ({Color color, String from})? inheritedColor(
    jge.Component component,
    String field,
  ) {
    for (final lookup in inheritedColors) {
      final found = lookup(component, field);
      if (found != null) return found;
    }
    return null;
  }

  /// Registers [builder] for the field type with [typeId].
  void register(
    String typeId,
    FieldEditorBuilder builder, {
    bool override = false,
  }) {
    if (!override && _byTypeId.containsKey(typeId)) {
      throw StateError(
        'A field editor for "$typeId" is already registered; pass '
        'override: true to replace it',
      );
    }
    _byTypeId[typeId] = builder;
  }

  /// Registers several editors.
  void registerAll(
    Map<String, FieldEditorBuilder> builders, {
    bool override = false,
  }) {
    for (final entry in builders.entries) {
      register(entry.key, entry.value, override: override);
    }
  }

  /// The editor registered for [typeId], or null.
  FieldEditorBuilder? byTypeId(String typeId) => _byTypeId[typeId];

  /// The editor for [field]: its type's, else the generic enum editor for
  /// any enum type, else null.
  FieldEditorBuilder? forField(jge.SchemaField field) =>
      _byTypeId[field.kind.id] ??
      (field.kind is jge.EnumFieldType ? _byTypeId[enumKey] : null);

  /// Every registered type id.
  Iterable<String> get typeIds => _byTypeId.keys;

  /// Whether [field] has an editor.
  bool canEdit(jge.SchemaField field) => forField(field) != null;

  /// Builds the control for [context], or the visible "no editor" row.
  Widget build(FieldEditorContext context) {
    final builder = forField(context.field);
    if (builder == null) {
      return ReadonlyRow(
        label: context.label,
        value: '${context.value} (no editor for "${context.field.kind.id}")',
      );
    }
    return builder(context);
  }

  /// Forgets every editor.
  void clear() {
    _byTypeId.clear();
    inheritedColors.clear();
  }
}
