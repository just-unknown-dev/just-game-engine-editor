import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/state/scene_mode_filters.dart';
import '../widgets/scrubbable_number_field.dart' show NumberScrubConfig;
import 'edge_insets_row.dart';
import 'field_editor.dart';
import 'field_rows.dart';
import 'physics_shape_editor.dart';
import 'collection_editor.dart';
import 'tag_field_editors.dart';
import 'physics_field_editors.dart';

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
    jge.FieldTypes.euler.id: _euler,
    jge.FieldTypes.offset.id: _offset,
    jge.FieldTypes.offsetList.id: _offsetList,
    jge.FieldTypes.color.id: _color,
    jge.FieldTypes.shapePaintStyle.id: _shapePaintStyle,
    jge.FieldTypes.physicsShape.id: (c) => PhysicsShapeEditor(ctx: c),
    jge.FieldTypes.edgeInsets.id: _edgeInsets,
    jge.FieldTypes.unknown.id: _readonly,
    ...TagFieldEditors.all,
    ...PhysicsFieldEditors.all,
  };

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
    final min = c.field.min, max = c.field.max;
    if (c.hint.slider && min != null && max != null && !isInt) {
      return SliderFieldRow(
        label: c.label,
        value: shown,
        min: min,
        max: max,
        step: scrub?.step ?? 0.05,
        decimals: scrub?.fractionDigits ?? 2,
        unit: scrub?.suffix ?? '',
        onChanged: (v) => c.onChanged(toValue(v)),
      );
    }
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
    itemCell: c.hint.itemKinds == null
        ? null
        : (key, json, onChanged) {
            final kind = c.hint.itemKinds![key];
            if (kind == null) return null;
            // An item's key edited by its type's own editor: saved as that type
            // saves, so the item stays the JSON the component reads.
            return c.editors.build(
              FieldEditorContext(
                field: jge.SchemaField(
                  name: key,
                  kind: kind,
                  read: (_) => null,
                ),
                hint: jge.FieldHint(
                  label: key.isEmpty
                      ? key
                      : key[0].toUpperCase() + key.substring(1),
                ),
                value: kind.decodeAny(json, jge.FieldConstraints.none),
                component: c.component,
                onChanged: (next) => onChanged(kind.encodeAny(next)),
                editors: c.editors,
                entityNames: c.entityNames,
                world: c.world,
                sceneState: c.sceneState,
                scope: c.scope,
              ),
            );
          },
  );

  /// Compound numeric editors: one scrub row per axis, sharing the hint.
  /// A vector's axes on one row: `(label, channel, value)` each. Only the
  /// channels the scene's mode shows appear (a 2-D scene hides a position's
  /// z); [build] still gets every value, the hidden ones unchanged.
  static Widget _axes(
    FieldEditorContext c,
    List<(String, String, double)> all,
    Object Function(List<double> next) build,
  ) {
    final visible = SceneModeFilters.visibleChannels(
      c.field,
      c.hint,
      c.sceneState?.editingMode ?? jge.SceneMode.twoD,
    );
    final shownAt = [
      for (var i = 0; i < all.length; i++)
        if (visible.contains(all[i].$2)) i,
    ];
    final axes = [for (final i in shownAt) (all[i].$1, all[i].$3)];
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
      onChanged: (next) {
        final full = [for (final a in all) a.$3];
        for (var k = 0; k < shownAt.length; k++) {
          full[shownAt[k]] = next[k];
        }
        c.onChanged(build(full));
      },
    );
  }

  static Widget _vector2(FieldEditorContext c) {
    final v = c.value is jge.Vector2
        ? c.value as jge.Vector2
        : jge.Vector2.zero();
    return _axes(c, [
      ('X', 'x', v.x),
      ('Y', 'y', v.y),
    ], (n) => jge.Vector2(n[0], n[1]));
  }

  static Widget _vector3(FieldEditorContext c) {
    final v = c.value is jge.Vector3
        ? c.value as jge.Vector3
        : jge.Vector3.zero();
    return _axes(c, [
      ('X', 'x', v.x),
      ('Y', 'y', v.y),
      ('Z', 'z', v.z),
    ], (n) => jge.Vector3(n[0], n[1], n[2]));
  }

  /// A rotation's three angles, shown in degrees and kept in radians.
  ///
  /// A 2-D scene shows only the turn in the plane, as one number — called
  /// "Angle", as a rotation always was there, unless the field is labelled
  /// something other than "Rotation". The other two angles keep their values.
  static Widget _euler(FieldEditorContext c) {
    final v = c.value is jge.Vector3
        ? c.value as jge.Vector3
        : jge.Vector3.zero();
    const toDegrees = 180 / math.pi;
    final visible = SceneModeFilters.visibleChannels(
      c.field,
      c.hint,
      c.sceneState?.editingMode ?? jge.SceneMode.twoD,
    );
    if (visible.length == 1 && visible.contains('z')) {
      final label = (c.hint.label == null || c.hint.label == 'Rotation')
          ? 'Angle'
          : c.label;
      final degrees = v.z * toDegrees;
      if (c.readOnly) {
        return ReadonlyRow(label: label, value: degrees.toStringAsFixed(1));
      }
      return ScrubFieldRow(
        label: label,
        value: degrees,
        scrubConfig: c.scrub ?? const NumberScrubConfig(fractionDigits: 1),
        onChanged: (d) => c.onChanged(jge.Vector3(v.x, v.y, d / toDegrees)),
      );
    }
    return _axes(
      c,
      [
        ('X', 'x', v.x * toDegrees),
        ('Y', 'y', v.y * toDegrees),
        ('Z', 'z', v.z * toDegrees),
      ],
      (n) => jge.Vector3(n[0] / toDegrees, n[1] / toDegrees, n[2] / toDegrees),
    );
  }

  static Widget _offset(FieldEditorContext c) {
    final o = c.value is Offset ? c.value as Offset : Offset.zero;
    return _axes(c, [
      ('X', 'dx', o.dx),
      ('Y', 'dy', o.dy),
    ], (n) => Offset(n[0], n[1]));
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
    // What the component draws when this is left unset, if anything does —
    // a module's to say (a theme's panel colour), not the inspector's.
    final inherited = c.editors.inheritedColor(c.component, c.field.name);
    return ColorEditorRow(
      label: c.label,
      paintStyle: jge.ShapePaintStyle(
        color: set
            ? c.value! as Color
            : (inherited?.color ?? const Color(0x00000000)),
      ),
      inherited: !set,
      inheritedFrom: set ? '' : (inherited?.from ?? 'not set'),
      onClear: set && inherited != null ? () => c.onChanged(null) : null,
      onChanged: (s) => c.onChanged(s.color),
      onPreview: c.preview == null ? null : (s) => c.preview!.show(s.color),
      onPreviewEnd: c.preview?.restore,
    );
  }

  static Widget _shapePaintStyle(FieldEditorContext c) => ColorEditorRow(
    label: c.label,
    paintStyle: c.value is jge.ShapePaintStyle
        ? c.value as jge.ShapePaintStyle
        : const jge.ShapePaintStyle(),
    supportsGradient: true,
    onChanged: c.onChanged,
    onPreview: c.preview?.show,
    onPreviewEnd: c.preview?.restore,
  );
}
