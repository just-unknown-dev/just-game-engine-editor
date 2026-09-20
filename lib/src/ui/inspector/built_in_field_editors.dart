import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../widgets/scrubbable_number_field.dart' show NumberScrubConfig;
import 'field_editor.dart';
import 'field_rows.dart';
import 'physics_shape_editor.dart';

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
    jge.FieldTypes.unknown.id: _readonly,
  };

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

  /// A reference to another entity, by name: a dropdown of what the scene
  /// holds. A name the scene no longer has stays listed, so opening the
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

  static Widget _json(FieldEditorContext c) {
    final pretty = const JsonEncoder.withIndent('  ').convert(c.value);
    if (c.readOnly) return ReadonlyRow(label: c.label, value: pretty);
    return TextEditorRow(
      label: c.label,
      initialValue: pretty,
      onSubmitted: (text) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is List || decoded is Map) c.onChanged(decoded);
        } on FormatException {
          // Leave the value as it was; the field shows it again.
        }
      },
    );
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < axes.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == axes.length - 1 ? 0 : 6),
            child: c.readOnly
                ? ReadonlyRow(label: axes[i].$1, value: '${axes[i].$2}')
                : ScrubFieldRow(
                    label: axes[i].$1,
                    value: axes[i].$2,
                    scrubConfig: scrub,
                    onChanged: (v) {
                      final next = List<double>.of(values)..[i] = v;
                      c.onChanged(build(next));
                    },
                  ),
          ),
      ],
    );
  }

  static Widget _vector2(FieldEditorContext c) {
    final v = c.value is jge.Vector2
        ? c.value as jge.Vector2
        : jge.Vector2.zero();
    return _axes(c, [
      ('${c.label} X', v.x),
      ('${c.label} Y', v.y),
    ], (n) => jge.Vector2(n[0], n[1]));
  }

  static Widget _vector3(FieldEditorContext c) {
    final v = c.value is jge.Vector3
        ? c.value as jge.Vector3
        : jge.Vector3.zero();
    return _axes(c, [
      ('${c.label} X', v.x),
      ('${c.label} Y', v.y),
      ('${c.label} Z', v.z),
    ], (n) => jge.Vector3(n[0], n[1], n[2]));
  }

  static Widget _offset(FieldEditorContext c) {
    final o = c.value is Offset ? c.value as Offset : Offset.zero;
    return _axes(c, [
      ('${c.label} X', o.dx),
      ('${c.label} Y', o.dy),
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

  static Widget _color(FieldEditorContext c) => ColorEditorRow(
    label: c.label,
    paintStyle: c.value is Color
        ? jge.ShapePaintStyle(color: c.value as Color)
        : const jge.ShapePaintStyle(),
    onChanged: (s) => c.onChanged(s.color),
  );

  static Widget _shapePaintStyle(FieldEditorContext c) => ColorEditorRow(
    label: c.label,
    paintStyle: c.value is jge.ShapePaintStyle
        ? c.value as jge.ShapePaintStyle
        : const jge.ShapePaintStyle(),
    supportsGradient: true,
    onChanged: c.onChanged,
  );
}
