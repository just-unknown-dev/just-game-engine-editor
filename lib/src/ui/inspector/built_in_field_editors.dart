import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../widgets/scrubbable_number_field.dart' show NumberScrubConfig;
import 'ui_field_editors.dart';
import 'field_editor.dart';
import 'field_rows.dart';
import 'physics_shape_editor.dart';
import 'collection_editor.dart';

/// The editors for the engine's built-in field types, keyed by type id.
///
/// Registered into every scope's [FieldEditorRegistry] before the modules',
/// so a module can replace one with `override: true`.
abstract final class BuiltInFieldEditors {
  static Map<String, FieldEditorBuilder> get all => {
    jge.FieldTypes.boolean.id: _boolean,
    jge.FieldTypes.integer.id: _number,
    jge.FieldTypes.decimal.id: _number,
    jge.FieldTypes.text.id: _text,
    jge.FieldTypes.assetRef.id: _assetRef,
    jge.FieldTypes.entityRef.id: _entityRef,
    FieldEditorRegistry.enumKey: _enumeration,
    jge.FieldTypes.enumeration.id: _enumeration,
    jge.FieldTypes.list.id: _json,
    jge.FieldTypes.map.id: _json,
    jge.FieldTypes.vector2.id: _vector2,
    jge.FieldTypes.vector3.id: _vector3,
    jge.FieldTypes.offset.id: _offset,
    jge.FieldTypes.offsetList.id: _offsetList,
    jge.FieldTypes.color.id: _color,
    jge.FieldTypes.shapePaintStyle.id: _shapePaintStyle,
    jge.FieldTypes.physicsShape.id: (c) => PhysicsShapeEditor(ctx: c),
    jge.FieldTypes.uiTextStyle.id: _uiTextStyle,
    jge.FieldTypes.uiActions.id: _uiActions,
    jge.FieldTypes.edgeInsets.id: _edgeInsets,
    jge.FieldTypes.uiAnchor.id: _uiAnchor,
    jge.FieldTypes.uiText.id: _uiText,
    jge.FieldTypes.uiStyleRole.id: _uiStyleRole,
    jge.FieldTypes.uiColorRole.id: _uiColorRole,
    jge.FieldTypes.unknown.id: _readonly,
  };

  /// Which of the theme's colours this element is drawn in.
  ///
  /// The palette's roles, plus whatever the scene already says — a game may
  /// name a colour of its own, and opening the inspector must never quietly
  /// rewrite it.
  static Widget _uiColorRole(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    return DropdownEditorRow(
      label: c.label,
      value: current.isEmpty ? jge.UiPalette.roles.first : current,
      options: [
        ...jge.UiPalette.roles,
        if (current.isNotEmpty && !jge.UiPalette.roles.contains(current))
          current,
      ],
      allowCustom: true,
      onChanged: c.onChanged,
    );
  }

  /// Which of the theme's text styles this element reads as.
  ///
  /// A name the theme does not carry stays listed — a game may name a role
  /// of its own, and opening the inspector must never quietly rewrite it.
  static Widget _uiStyleRole(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    return DropdownEditorRow(
      label: c.label,
      value: current.isEmpty ? jge.UiTheme.textRoles.first : current,
      options: [
        ...jge.UiTheme.textRoles,
        if (current.isNotEmpty && !jge.UiTheme.textRoles.contains(current))
          current,
      ],
      allowCustom: true,
      onChanged: c.onChanged,
    );
  }

  static Widget _uiAnchor(FieldEditorContext c) => UiAnchorEditorRow(
    label: c.label,
    anchor: c.value is jge.UiAnchor
        ? c.value! as jge.UiAnchor
        : jge.UiAnchor.topLeft,
    onChanged: c.onChanged,
  );

  static Widget _uiText(FieldEditorContext c) => c.readOnly
      ? _readonly(c)
      : UiTextEditorRow(
          label: c.label,
          value: c.value?.toString() ?? '',
          bindings: jge.UiBindings.names,
          onChanged: c.onChanged,
        );

  static Widget _uiTextStyle(FieldEditorContext c) {
    // What this style layers over: the theme's style for the element's
    // role, so the row can show what is set here and what is not.
    final role = _roleOf(c.component);
    return UiTextStyleEditorRow(
      label: c.label,
      style: c.value is jge.UiTextStyle
          ? c.value! as jge.UiTextStyle
          : const jge.UiTextStyle(),
      fontFamilies: jge.UiFonts.families,
      inherited: role == null ? null : jge.UiThemes.preview.textStyle(role),
      inheritedFrom: role ?? '',
      onChanged: c.onChanged,
    );
  }

  /// The theme role the component this style belongs to reads as.
  static String? _roleOf(jge.Component component) => switch (component) {
    final jge.TextComponent text => text.styleRole,
    final jge.ButtonComponent button => button.styleRole,
    _ => null,
  };

  static Widget _uiActions(FieldEditorContext c) => UiActionsEditorRow(
    label: c.label,
    actions: c.value is jge.UiActionList
        ? c.value! as jge.UiActionList
        : jge.UiActionList.empty,
    customNames: jge.UiActions.customNames,
    onChanged: c.onChanged,
  );

  static Widget _edgeInsets(FieldEditorContext c) => EdgeInsetsEditorRow(
    label: c.label,
    insets: c.value is EdgeInsets ? c.value! as EdgeInsets : EdgeInsets.zero,
    onChanged: c.onChanged,
  );

  static Widget _readonly(FieldEditorContext c) =>
      ReadonlyRow(label: c.label, value: '${c.value}');

  static Widget _boolean(FieldEditorContext c) => c.readOnly
      ? _readonly(c)
      : BoolEditorRow(
          label: c.label,
          value: c.value == true,
          onChanged: c.onChanged,
        );

  /// Integers and decimals: a scrub field when the hint or limits ask for
  /// one, a text field otherwise. Angles display in degrees when the hint
  /// says so, while the component keeps radians.
  static Widget _number(FieldEditorContext c) {
    final degrees = c.hint.unit == jge.AngleUnit.degrees;
    final isInt = c.field.kind.id == jge.FieldTypes.integer.id;
    final raw = (c.value as num?)?.toDouble() ?? 0.0;
    final shown = degrees ? raw * 180 / math.pi : raw;
    Object toValue(double v) {
      final stored = degrees ? v * math.pi / 180 : v;
      return isInt ? stored.round() : stored;
    }

    if (c.readOnly) return _readonly(c);
    final scrub = c.scrub;
    if (scrub != null) {
      return ScrubFieldRow(
        label: c.label,
        value: shown,
        scrubConfig: scrub,
        onChanged: (v) => c.onChanged(toValue(v)),
      );
    }
    return TextEditorRow(
      label: c.label,
      initialValue: isInt ? shown.round().toString() : shown.toString(),
      onSubmitted: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null) c.onChanged(toValue(parsed));
      },
    );
  }

  static Widget _text(FieldEditorContext c) => c.readOnly
      ? _readonly(c)
      : TextEditorRow(
          label: c.label,
          initialValue: c.value?.toString() ?? '',
          onSubmitted: (text) => c.onChanged(text.trim()),
        );

  static const String _noEntity = '(none)';

  /// A reference to another entity, by name: a searchable dropdown of what
  /// the scene holds. A name the scene no longer has stays listed, so opening the
  /// inspector never silently rewrites it.
  static Widget _entityRef(FieldEditorContext c) {
    final current = c.value as String? ?? '';
    if (c.readOnly) return ReadonlyRow(label: c.label, value: current);
    final names = <String>{
      ...?c.entityNames?.call(),
      if (current.isNotEmpty) current,
    }.toList()..sort();
    return DropdownEditorRow(
      label: c.label,
      value: current.isEmpty ? _noEntity : current,
      options: [_noEntity, ...names],
      // A level has many entities, and the one wanted may not exist yet: a
      // player the game spawns is named here before it is ever in the scene.
      searchable: true,
      allowCustom: true,
      onChanged: (name) => c.onChanged(name == _noEntity ? '' : name),
    );
  }

  static Widget _assetRef(FieldEditorContext c) => c.readOnly
      ? _readonly(c)
      : AssetRefEditorRow(
          label: c.label,
          value: c.value as String? ?? '',
          extensions: c.hint.fileExtensions ?? const ['png'],
          onChanged: c.onChanged,
        );

  /// A dropdown over an [jge.EnumFieldType]'s values. A plain `enumeration`
  /// field has no value list, so it shows its current value read-only.
  static Widget _enumeration(FieldEditorContext c) {
    final kind = c.field.kind;
    if (kind is! jge.EnumFieldType || c.readOnly) {
      return ReadonlyRow(label: c.label, value: _enumName(c.value));
    }
    final names = kind.names;
    final selected = _enumName(c.value);
    return DropdownEditorRow(
      label: c.label,
      value: names.contains(selected) ? selected : names.first,
      options: names,
      onChanged: (name) =>
          c.onChanged(kind.values.firstWhere((v) => v.name == name)),
    );
  }

  static String _enumName(Object? value) =>
      value is Enum ? value.name : (value?.toString() ?? '');

  /// A list or a map, as rows rather than as JSON to hand-edit.
  static Widget _json(FieldEditorContext c) => CollectionEditor(
    label: c.label,
    value: c.value,
    readOnly: c.readOnly,
    template: c.hint.itemTemplate,
    description: c.hint.description,
    onChanged: c.onChanged,
  );

  /// Compound numeric editors: one scrub row per axis, sharing the hint.
  static Widget _axes(
    FieldEditorContext c,
    List<(String, double)> axes,
    Object Function(List<double> next) build,
  ) {
    final values = [for (final a in axes) a.$2];
    // Axes scrub even when the hint asked for nothing: a vector typed as
    // text is the one thing nobody wants.
    final scrub =
        c.scrub ??
        NumberScrubConfig(
          fractionDigits: 1,
          min: c.field.min,
          max: c.field.max,
        );
    return AxesFieldRow(
      label: c.label,
      axes: [for (final a in axes) a.$1],
      values: values,
      scrubConfig: scrub,
      readOnly: c.readOnly,
      onChanged: (next) => c.onChanged(build(next)),
    );
  }

  static Widget _vector2(FieldEditorContext c) {
    final v = c.value is jge.Vector2
        ? c.value as jge.Vector2
        : jge.Vector2.zero();
    return _axes(c, [('X', v.x), ('Y', v.y)], (n) => jge.Vector2(n[0], n[1]));
  }

  static Widget _vector3(FieldEditorContext c) {
    final v = c.value is jge.Vector3
        ? c.value as jge.Vector3
        : jge.Vector3.zero();
    return _axes(c, [
      ('X', v.x),
      ('Y', v.y),
      ('Z', v.z),
    ], (n) => jge.Vector3(n[0], n[1], n[2]));
  }

  static Widget _offset(FieldEditorContext c) {
    final o = c.value is Offset ? c.value as Offset : Offset.zero;
    return _axes(c, [('X', o.dx), ('Y', o.dy)], (n) => Offset(n[0], n[1]));
  }

  static Widget _offsetList(FieldEditorContext c) {
    final points = c.value;
    return OffsetListEditorRow(
      label: c.label,
      points: points is List<Offset> ? points : const <Offset>[],
      onChanged: c.readOnly ? (_) {} : c.onChanged,
    );
  }

  /// A colour, which may be one the field does not set.
  ///
  /// An unset colour used to show as white, which is indistinguishable
  /// from a white somebody chose. It now shows what it actually falls back
  /// to — the theme role the component names, or nothing at all — muted,
  /// with a way to put it back where it is set.
  static Widget _color(FieldEditorContext c) {
    final set = c.value is Color;
    final fallback = _fallbackColor(c);
    return ColorEditorRow(
      label: c.label,
      paintStyle: jge.ShapePaintStyle(
        color: set
            ? c.value! as Color
            : (fallback?.color ?? const Color(0x00000000)),
      ),
      inherited: !set,
      inheritedFrom: fallback?.from ?? (set ? '' : 'not set'),
      onClear: set && fallback != null ? () => c.onChanged(null) : null,
      onChanged: (s) => c.onChanged(s.color),
    );
  }

  /// What a colour field falls back to when it is not set, and what to
  /// call that.
  ///
  /// The components decide — `colorUnder`, `borderColorUnder` — so what the
  /// inspector says a colour inherits and what the screen actually draws
  /// cannot drift apart.
  static ({Color color, String from})? _fallbackColor(FieldEditorContext c) {
    final theme = jge.UiThemes.preview;
    final component = c.component;
    final name = c.field.name;
    return switch ((component, name)) {
      (final jge.UiPanelComponent panel, 'color') => (
        color: theme.color(
          panel.colorRole,
          fallbackColor: theme.palette.surface,
        ),
        from: panel.colorRole,
      ),
      (final jge.UiPanelComponent _, 'borderColor') => (
        color: theme.palette.outline,
        from: 'outline',
      ),
      (final jge.UiProgressComponent bar, 'color') => (
        color: theme.color(bar.colorRole, fallbackColor: theme.palette.accent),
        from: bar.colorRole,
      ),
      (final jge.UiProgressComponent _, 'trackColor') => (
        color: theme.palette.outline,
        from: 'outline',
      ),
      (final jge.ButtonComponent button, 'color') => (
        color: theme.color(
          button.colorRole,
          fallbackColor: theme.palette.primary,
        ),
        from: button.colorRole,
      ),
      // A colour with nothing behind it: unset means no border, no tint.
      _ => null,
    };
  }

  static Widget _shapePaintStyle(FieldEditorContext c) => ColorEditorRow(
    label: c.label,
    paintStyle: c.value is jge.ShapePaintStyle
        ? c.value as jge.ShapePaintStyle
        : const jge.ShapePaintStyle(),
    supportsGradient: true,
    onChanged: c.onChanged,
  );
}
