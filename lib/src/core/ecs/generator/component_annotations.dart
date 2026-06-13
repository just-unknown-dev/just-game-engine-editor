export 'package:just_code_gen/just_code_gen.dart' show ECSComponent;

/// Field-level editor behavior annotation used by code-generation.
class EditorField {
  const EditorField({
    this.visible = true,
    this.readOnly = false,
    this.includeInJson = true,
    this.label,
    this.order = 0,
  });

  final bool visible;
  final bool readOnly;
  final bool includeInJson;
  final String? label;
  final int order;
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
