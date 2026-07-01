import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_colours/just_colours.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/ecs/generator/component_registry.dart';
import '../../core/state/editor_scene_state.dart';
import '../theme/editor_theme.dart';
import '../widgets/scrubbable_number_field.dart';

List<Widget> buildCustomComponentSections({
  required jge.Entity entity,
  required EditorSceneState sceneState,
}) {
  final sections = <Widget>[];
  for (final component in entity.components) {
    final descriptor = CustomComponentRegistry.instance.descriptorForComponent(
      component,
    );
    if (descriptor == null) continue;

    sections.add(
      CustomComponentSection(
        component: component,
        descriptor: descriptor,
        onDelete: () {
          entity.removeComponentByType(component.componentType);
          sceneState.markDirty();
          sceneState.refresh();
        },
        onChanged: () {
          sceneState.syncEntityNode(entity);
          sceneState.markDirty();
          sceneState.refresh();
        },
      ),
    );
  }
  return sections;
}

class CustomComponentSection extends StatelessWidget {
  const CustomComponentSection({
    super.key,
    required this.component,
    required this.descriptor,
    required this.onDelete,
    required this.onChanged,
  });

  final jge.Component component;
  final EditorComponent descriptor;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = descriptor.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: EditorTheme.dialogBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EditorTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              border: accent != null
                  ? Border(left: BorderSide(color: accent, width: 3))
                  : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(5),
                topRight: Radius.circular(5),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                if (descriptor.icon != null) ...[
                  Icon(
                    descriptor.icon,
                    size: 13,
                    color: accent ?? EditorTheme.primaryMutedLight,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  descriptor.name,
                  style: const TextStyle(
                    color: EditorTheme.primaryMutedLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                _ComponentTag(componentType: descriptor.componentType),
                const Spacer(),
                if (descriptor.deletable)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: EditorTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: EditorTheme.border),
          // ── Fields ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (descriptor.description != null &&
                    descriptor.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      descriptor.description!,
                      style: const TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (descriptor.fieldGroups != null)
                  ..._buildGroupedFields(descriptor.fieldGroups!)
                else
                  ..._buildFlatFields(
                    descriptor.fields.where((f) => f.visible).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedFields(List<EditorFieldGroup> groups) {
    final visibleGroups = groups
        .where((g) => g.fields.any((f) => f.visible))
        .toList();

    if (visibleGroups.isEmpty) {
      return [
        const Text(
          'No visible properties',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (var i = 0; i < visibleGroups.length; i++) {
      final group = visibleGroups[i];
      final visibleFields = group.fields.where((f) => f.visible).toList();
      if (i > 0) widgets.add(const SizedBox(height: 6));
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            group.name.toUpperCase(),
            style: const TextStyle(
              color: EditorTheme.primaryMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
      widgets.addAll(_buildFlatFields(visibleFields));
    }
    return widgets;
  }

  List<Widget> _buildFlatFields(List<EditorComponentField> fields) {
    if (fields.isEmpty) {
      return [
        const Text(
          'No visible properties',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      ];
    }
    return fields.map((field) {
      final value = field.read(component);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _EditorFieldControl(
          label: field.displayLabel,
          field: field,
          value: value,
          onChanged: (next) {
            final writer = field.write;
            if (writer == null) return;
            writer(component, next);
            onChanged();
          },
        ),
      );
    }).toList();
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _ComponentTag extends StatelessWidget {
  const _ComponentTag({required this.componentType});

  final ComponentType componentType;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg, border) = switch (componentType) {
      ComponentType.core => (
        'CORE',
        EditorTheme.primaryMutedLight,
        EditorTheme.primaryMuted.withValues(alpha: 0.18),
        EditorTheme.primaryMuted.withValues(alpha: 0.5),
      ),
      ComponentType.editor => (
        'EDITOR',
        const Color(0xFF81C9E8),
        const Color(0xFF81C9E8).withValues(alpha: 0.12),
        const Color(0xFF81C9E8).withValues(alpha: 0.45),
      ),
      ComponentType.experimental => (
        'EXP',
        const Color(0xFFE8C47A),
        const Color(0xFFE8C47A).withValues(alpha: 0.12),
        const Color(0xFFE8C47A).withValues(alpha: 0.45),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Field control dispatcher ──────────────────────────────────────────────────

class _EditorFieldControl extends StatelessWidget {
  const _EditorFieldControl({
    required this.label,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final EditorComponentField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.isReadOnly) {
      return _ReadonlyRow(label: label, value: _displayValue(field, value));
    }

    switch (field.kind) {
      case EditorFieldKind.boolean:
        return _BoolEditorRow(
          label: label,
          value: value == true,
          onChanged: (v) => onChanged(v),
        );
      case EditorFieldKind.decimal:
        if (field.scrubConfig != null) {
          return _ScrubFieldRow(
            label: label,
            value: (value as num?)?.toDouble() ?? 0.0,
            scrubConfig: field.scrubConfig!,
            onChanged: (v) => onChanged(v),
          );
        }
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = double.tryParse(text.trim());
            if (parsed != null) onChanged(parsed);
          },
        );
      case EditorFieldKind.integer:
        if (field.scrubConfig != null) {
          return _ScrubFieldRow(
            label: label,
            value: (value as num?)?.toDouble() ?? 0.0,
            scrubConfig: field.scrubConfig!,
            onChanged: (v) =>
                onChanged(field.scrubConfig!.integer ? v.round() : v),
          );
        }
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) onChanged(parsed);
          },
        );
      case EditorFieldKind.enumeration:
        final options = field.enumValues ?? const <String>[];
        final selected = _enumSelectedValue(value);
        if (options.isEmpty) {
          return _ReadonlyRow(label: label, value: _displayValue(field, value));
        }
        return _DropdownEditorRow(
          label: label,
          value: options.contains(selected) ? selected : options.first,
          options: options,
          onChanged: (next) {
            if (field.enumParser != null) {
              onChanged(field.enumParser!(next));
            } else {
              onChanged(next);
            }
          },
        );
      case EditorFieldKind.color:
        final colorStyle = value is Color
            ? jge.ShapePaintStyle(color: value as Color)
            : const jge.ShapePaintStyle();
        return _ColorEditorRow(
          label: label,
          paintStyle: colorStyle,
          onChanged: (s) => onChanged(s.color),
        );
      case EditorFieldKind.shapePaintStyle:
        final paintStyle = value is jge.ShapePaintStyle
            ? value as jge.ShapePaintStyle
            : const jge.ShapePaintStyle();
        return _ColorEditorRow(
          label: label,
          paintStyle: paintStyle,
          supportsGradient: true,
          onChanged: (s) => onChanged(s),
        );
      case EditorFieldKind.assetRef:
        return _AssetRefEditorRow(
          label: label,
          value: value as String? ?? '',
          onChanged: (path) => onChanged(path),
        );
      case EditorFieldKind.text:
      case EditorFieldKind.list:
      case EditorFieldKind.map:
      case EditorFieldKind.vector2:
      case EditorFieldKind.vector3:
      case EditorFieldKind.offset:
      case EditorFieldKind.unknown:
        return _TextEditorRow(
          label: label,
          initialValue: _displayValue(field, value),
          onSubmitted: (text) {
            final parsed = _parseTextValue(field, text, previous: value);
            if (parsed != null || field.kind == EditorFieldKind.text) {
              onChanged(parsed);
            }
          },
        );
    }
  }

  static String _enumSelectedValue(Object? value) {
    if (value == null) return '';
    final raw = value.toString();
    if (raw.contains('.')) return raw.split('.').last;
    return raw;
  }

  static String _displayValue(EditorComponentField field, Object? value) {
    if (field.valueFormatter != null) return field.valueFormatter!(value);
    if (value == null) return '';

    switch (field.kind) {
      case EditorFieldKind.list:
      case EditorFieldKind.map:
        return const JsonEncoder.withIndent('  ').convert(value);
      case EditorFieldKind.vector2:
        if (value is jge.Vector2) return '${value.x}, ${value.y}';
        return value.toString();
      case EditorFieldKind.vector3:
        if (value is jge.Vector3) {
          return '${value.x}, ${value.y}, ${value.z}';
        }
        return value.toString();
      case EditorFieldKind.offset:
        if (value is Offset) return '${value.dx}, ${value.dy}';
        return value.toString();
      case EditorFieldKind.color:
        if (value is Color) {
          final hex = value.toARGB32().toRadixString(16).padLeft(8, '0');
          return '#${hex.toUpperCase()}';
        }
        return value.toString();
      case EditorFieldKind.shapePaintStyle:
        if (value is jge.ShapePaintStyle) {
          return value.gradient != null
              ? 'Gradient'
              : '#${value.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
        }
        return value.toString();
      case EditorFieldKind.boolean:
      case EditorFieldKind.integer:
      case EditorFieldKind.decimal:
      case EditorFieldKind.text:
      case EditorFieldKind.assetRef:
      case EditorFieldKind.enumeration:
      case EditorFieldKind.unknown:
        return value.toString();
    }
  }

  static Object? _parseTextValue(
    EditorComponentField field,
    String text, {
    required Object? previous,
  }) {
    final raw = text.trim();
    switch (field.kind) {
      case EditorFieldKind.integer:
        return int.tryParse(raw) ?? previous;
      case EditorFieldKind.decimal:
        return double.tryParse(raw) ?? previous;
      case EditorFieldKind.text:
      case EditorFieldKind.assetRef:
        return raw;
      case EditorFieldKind.list:
        try {
          final decoded = jsonDecode(raw);
          return (decoded is List) ? decoded : previous;
        } catch (_) {
          return previous;
        }
      case EditorFieldKind.map:
        try {
          final decoded = jsonDecode(raw);
          return (decoded is Map) ? decoded.cast<String, dynamic>() : previous;
        } catch (_) {
          return previous;
        }
      case EditorFieldKind.vector2:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 2) return previous;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        if (x == null || y == null) return previous;
        return jge.Vector2(x, y);
      case EditorFieldKind.vector3:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 3) return previous;
        final x = double.tryParse(parts[0]);
        final y = double.tryParse(parts[1]);
        final z = double.tryParse(parts[2]);
        if (x == null || y == null || z == null) return previous;
        return jge.Vector3(x, y, z);
      case EditorFieldKind.offset:
        final parts = raw.split(',').map((s) => s.trim()).toList();
        if (parts.length != 2) return previous;
        final dx = double.tryParse(parts[0]);
        final dy = double.tryParse(parts[1]);
        if (dx == null || dy == null) return previous;
        return Offset(dx, dy);
      case EditorFieldKind.color:
        final normalized = raw.replaceFirst('#', '');
        final argb = int.tryParse(normalized, radix: 16);
        if (argb == null) return previous;
        return Color(argb);
      case EditorFieldKind.shapePaintStyle:
      case EditorFieldKind.boolean:
      case EditorFieldKind.enumeration:
      case EditorFieldKind.unknown:
        return previous;
    }
  }
}

// ── Colour ↔ ShapePaintStyle bridge ──────────────────────────────────────────

jge.ShapePaintStyle _selectionToShapePaintStyle(ColourSelection sel) {
  if (!sel.useGradient) return jge.ShapePaintStyle(color: sel.color);
  final cfg = sel.gradient;
  final colors = cfg.colors.isEmpty ? [sel.color] : cfg.colors;
  jge.ShapeGradient gradient;
  switch (cfg.type) {
    case GradientType.linear:
      final rad = cfg.angle * math.pi / 180;
      gradient = jge.ShapeGradient.linear(
        colors: colors,
        stops: cfg.stops,
        begin: Alignment(math.cos(rad + math.pi), math.sin(rad + math.pi)),
        end: Alignment(math.cos(rad), math.sin(rad)),
        tileMode: cfg.tileMode,
      );
    case GradientType.radial:
      gradient = jge.ShapeGradient.radial(
        colors: colors,
        stops: cfg.stops,
        center: cfg.center,
        radius: cfg.radius,
        tileMode: cfg.tileMode,
      );
    case GradientType.sweep:
      gradient = jge.ShapeGradient.sweep(
        colors: colors,
        stops: cfg.stops,
        center: cfg.center,
        tileMode: cfg.tileMode,
      );
  }
  return jge.ShapePaintStyle(color: sel.color, gradient: gradient);
}

ColourSelection _shapePaintStyleToSelection(jge.ShapePaintStyle style) {
  final g = style.gradient;
  if (g == null) return ColourSelection(color: style.color);
  GradientType type;
  switch (g.kind) {
    case jge.ShapeGradientKind.linear:
      type = GradientType.linear;
    case jge.ShapeGradientKind.radial:
      type = GradientType.radial;
    case jge.ShapeGradientKind.sweep:
      type = GradientType.sweep;
  }
  final angle = type == GradientType.linear
      ? math.atan2(
              g.end is Alignment ? (g.end as Alignment).y : 0.0,
              g.end is Alignment ? (g.end as Alignment).x : 1.0,
            ) *
            180 /
            math.pi
      : 0.0;
  return ColourSelection(
    color: style.color,
    useGradient: true,
    gradient: GradientConfig(
      type: type,
      colors: g.colors,
      stops: g.stops,
      angle: angle,
      center: g.center is Alignment ? g.center as Alignment : Alignment.center,
      radius: g.radius,
      tileMode: g.tileMode,
    ),
  );
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _ColorEditorRow extends StatelessWidget {
  const _ColorEditorRow({
    required this.label,
    required this.paintStyle,
    required this.onChanged,
    this.supportsGradient = false,
  });

  final String label;
  final jge.ShapePaintStyle paintStyle;
  final ValueChanged<jge.ShapePaintStyle> onChanged;
  final bool supportsGradient;

  @override
  Widget build(BuildContext context) {
    final hasGradient = supportsGradient && paintStyle.gradient != null;
    final gradColors = paintStyle.gradient?.colors ?? [];
    final hex =
        '#${paintStyle.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () async {
              final initial = _shapePaintStyleToSelection(paintStyle);
              final picked = await JustColourDialog.show(
                context,
                initialSelection: initial,
                view: supportsGradient
                    ? ColourDialogView.both
                    : ColourDialogView.colourOnly,
              );
              if (picked != null)
                onChanged(_selectionToShapePaintStyle(picked));
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: EditorTheme.inputBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: EditorTheme.border),
              ),
              child: Row(
                children: [
                  // Swatch: gradient preview or solid colour
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: hasGradient ? null : paintStyle.color,
                      gradient: hasGradient && gradColors.length >= 2
                          ? LinearGradient(colors: gradColors.take(2).toList())
                          : null,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasGradient ? 'Gradient' : hex,
                    style: const TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.colorize_rounded,
                    size: 13,
                    color: EditorTheme.primaryMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadonlyRow extends StatelessWidget {
  const _ReadonlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _BoolEditorRow extends StatelessWidget {
  const _BoolEditorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: EditorTheme.primaryMutedLight,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: const BorderSide(color: EditorTheme.border),
          ),
        ),
      ],
    );
  }
}

class _ScrubFieldRow extends StatefulWidget {
  const _ScrubFieldRow({
    required this.label,
    required this.value,
    required this.scrubConfig,
    required this.onChanged,
  });

  final String label;
  final double value;
  final NumberScrubConfig scrubConfig;
  final ValueChanged<double> onChanged;

  @override
  State<_ScrubFieldRow> createState() => _ScrubFieldRowState();
}

class _ScrubFieldRowState extends State<_ScrubFieldRow> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(_ScrubFieldRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != old.value) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (widget.scrubConfig.integer) return v.round().toString();
    return v.toStringAsFixed(widget.scrubConfig.fractionDigits);
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text.trim());
    if (v != null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return ScrubbableNumberField(
      label: widget.label,
      controller: _ctrl,
      focusNode: _focus,
      onCommit: _commit,
      config: widget.scrubConfig,
      labelWidth: 96,
    );
  }
}

class _TextEditorRow extends StatelessWidget {
  const _TextEditorRow({
    required this.label,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              label,
              style: const TextStyle(
                color: EditorTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            initialValue: initialValue,
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
            ),
            minLines: 1,
            maxLines: 4,
            onFieldSubmitted: onSubmitted,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              filled: true,
              fillColor: EditorTheme.inputBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: EditorTheme.primaryActive),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownEditorRow extends StatelessWidget {
  const _DropdownEditorRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: EditorTheme.inputBg,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EditorTheme.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: EditorTheme.dialogBg,
                style: const TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 11,
                ),
                items: options
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (next) {
                  if (next != null) onChanged(next);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Asset path picker row ─────────────────────────────────────────────────────

class _AssetRefEditorRow extends StatefulWidget {
  const _AssetRefEditorRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_AssetRefEditorRow> createState() => _AssetRefEditorRowState();
}

class _AssetRefEditorRowState extends State<_AssetRefEditorRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _sizeAnim;
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _pngPaths = [];
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _sizeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _scanPngs();
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanPngs() async {
    final base = Directory.current.path.replaceAll(r'\', '/');
    final assetsDir = Directory('$base/assets');
    if (!await assetsDir.exists()) return;
    final paths = <String>[];
    await for (final entity in assetsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        final relative = entity.path
            .replaceAll(r'\', '/')
            .replaceFirst('$base/', '');
        paths.add(relative);
      }
    }
    paths.sort();
    if (!mounted) return;
    setState(() => _pngPaths = paths);
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    });
  }

  void _selectPath(String path) {
    widget.onChanged(path);
    setState(() {
      _isExpanded = false;
      _anim.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _pngPaths
        : _pngPaths
              .where(
                (p) =>
                    p.split('/').last.toLowerCase().contains(query) ||
                    p.toLowerCase().contains(query),
              )
              .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 96,
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) =>
                    details.data.toLowerCase().endsWith('.png'),
                onAcceptWithDetails: (details) => _selectPath(details.data),
                builder: (context, candidateData, rejectedData) {
                  Color borderColor = EditorTheme.border;
                  if (candidateData.isNotEmpty) {
                    borderColor = const Color(0xFF4CAF50);
                  } else if (rejectedData.isNotEmpty) {
                    borderColor = EditorTheme.error;
                  }
                  return GestureDetector(
                    onTap: _toggleExpanded,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: EditorTheme.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(
                            Icons.image_outlined,
                            size: 12,
                            color: EditorTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.value.isEmpty
                                  ? 'Select PNG…'
                                  : widget.value,
                              style: TextStyle(
                                color: widget.value.isEmpty
                                    ? EditorTheme.textMuted
                                    : EditorTheme.textPrimary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            _isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 14,
                            color: EditorTheme.textMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        SizeTransition(
          sizeFactor: _sizeAnim,
          child: Container(
            margin: const EdgeInsets.only(left: 96, top: 4),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: EditorTheme.surfaceDark,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: EditorTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    height: 24,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 11,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search PNG files…',
                        hintStyle: const TextStyle(
                          color: EditorTheme.textMuted,
                          fontSize: 11,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          size: 14,
                          color: EditorTheme.textMuted,
                        ),
                        filled: true,
                        fillColor: EditorTheme.inputBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: EditorTheme.border,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: EditorTheme.border,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(
                            color: EditorTheme.primaryActive,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1, color: EditorTheme.border),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _pngPaths.isEmpty
                                ? 'No PNG files found in assets/'
                                : 'No matches for "$query"',
                            style: const TextStyle(
                              color: EditorTheme.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final path = filtered[index];
                            final isSelected = path == widget.value;
                            final filename = path.split('/').last;
                            return InkWell(
                              onTap: () => _selectPath(path),
                              child: Container(
                                color: isSelected
                                    ? EditorTheme.selectionBg
                                    : Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.image_outlined,
                                      size: 12,
                                      color: Color(0xFF7DD8E0),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            filename,
                                            style: TextStyle(
                                              color: isSelected
                                                  ? EditorTheme.textPrimary
                                                  : EditorTheme.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            path,
                                            style: const TextStyle(
                                              color: EditorTheme.textMuted,
                                              fontSize: 9,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_rounded,
                                        size: 12,
                                        color: EditorTheme.primaryMutedLight,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
