export 'package:just_code_gen/just_code_gen.dart' show ECSComponent, ECSComponentType;

/// Field-level editor behavior annotation used by code-generation.
class EditorField {
  const EditorField({
    this.name,
    this.visible = true,
    this.readOnly = false,
    this.includeInJson = true,
    this.label,
    this.order = 0,
    this.scrubStep,
    this.scrubFractionDigits,
    this.scrubMin,
    this.scrubMax,
    this.scrubInteger = false,
  });

  /// Overrides the descriptor field name used for JSON serialization.
  /// Defaults to the member name when null.
  final String? name;
  final bool visible;
  final bool readOnly;
  final bool includeInJson;
  final String? label;
  final int order;
  final double? scrubStep;
  final int? scrubFractionDigits;
  final double? scrubMin;
  final double? scrubMax;
  final bool scrubInteger;
}

/// Hides a property from the editor UI.
class EditorHidden {
  const EditorHidden();
}

/// Forces a property to be visible but non-editable.
class EditorReadOnly {
  const EditorReadOnly();
}

/// Strongly typed kind used by editor controls and JSON conversion.
enum EditorFieldKind {
  boolean,
  integer,
  decimal,
  text,
  enumeration,
  list,
  map,
  vector2,
  vector3,
  color,
  offset,
  unknown,
}
