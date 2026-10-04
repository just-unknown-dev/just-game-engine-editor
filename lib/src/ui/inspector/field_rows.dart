/// The inspector's row widgets: one label-plus-control per field kind.
///
/// Public so a module's own field editor can be built from the same parts
/// and look like the rest of the inspector.
library;

import 'field_style.dart';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_colours/just_colours.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import '../widgets/scrubbable_number_field.dart';
import '../widgets/editor_dropdown.dart';
import '../kit/buttons.dart';
import '../kit/controls.dart' show EditorSlider;
import '../kit/fields.dart';

// ── Colour ↔ ShapePaintStyle bridge ──────────────────────────────────────────

jge.ShapePaintStyle selectionToShapePaintStyle(ColourSelection sel) {
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

ColourSelection shapePaintStyleToSelection(jge.ShapePaintStyle style) {
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

class ColorEditorRow extends StatelessWidget {
  const ColorEditorRow({
    super.key,
    required this.label,
    required this.paintStyle,
    required this.onChanged,
    this.supportsGradient = false,
    this.inherited = false,
    this.inheritedFrom = '',
    this.onClear,
  });

  final String label;
  final jge.ShapePaintStyle paintStyle;
  final ValueChanged<jge.ShapePaintStyle> onChanged;
  final bool supportsGradient;

  /// Whether this colour is not the field's own but the one it falls back
  /// to. The swatch still shows what will be drawn; the value beside it is
  /// muted, because a colour nobody chose here must not read as one
  /// somebody did.
  final bool inherited;

  /// What it falls back to, for the note beside it: a theme role, or
  /// "nothing" where an unset colour means no colour at all.
  final String inheritedFrom;

  /// Puts the colour back to whatever it inherits. Null where the field
  /// must always have one.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasGradient = supportsGradient && paintStyle.gradient != null;
    final gradColors = paintStyle.gradient?.colors ?? [];
    final hex =
        '#${paintStyle.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

    return Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Text(label, style: InspectorField.labelStyle),
        ),
        Expanded(
          child: InkWell(
            onTap: () async {
              final initial = shapePaintStyleToSelection(paintStyle);
              final picked = await JustColourDialog.show(
                context,
                initialSelection: initial,
                view: supportsGradient
                    ? ColourDialogView.both
                    : ColourDialogView.colourOnly,
              );
              if (picked != null) {
                onChanged(selectionToShapePaintStyle(picked));
              }
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: InspectorField.height,
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  // One stretch for the words, so the picker icon is always
                  // at the box's end: a text and a spacer each took a share
                  // of the room, and the icon moved with every value.
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            hasGradient ? 'Gradient' : hex,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: inherited
                                  ? EditorTheme.textMuted
                                  : EditorTheme.textPrimary,
                              fontSize: 11,
                              fontStyle: inherited
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (inherited && inheritedFrom.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              inheritedFrom,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: EditorTheme.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.colorize_rounded,
                    size: 13,
                    color: EditorTheme.primaryMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        // Only where there is something to put back: a row that always
        // offers to clear reads as though something is always set.
        if (!inherited && onClear != null)
          Tooltip(
            message: inheritedFrom.isEmpty ? 'Clear' : 'Back to $inheritedFrom',
            child: IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.settings_backup_restore_rounded),
              iconSize: 14,
              color: EditorTheme.textMuted,
              splashRadius: 12,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            ),
          ),
      ],
    );
  }
}

class ReadonlyRow extends StatelessWidget {
  const ReadonlyRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: InspectorField.labelStyle,
          ),
        ),
        // The same box as every other row, so it sits on the same lines —
        // left unfilled and quieter, since there is nothing in it to change.
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: InspectorField.height),
            // Less the border's pixel on each side, which a box's padding
            // grows by: then one line comes out at the height of the rest.
            padding: InspectorField.padding - const EdgeInsets.all(1),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(InspectorField.radius),
              border: Border.all(color: EditorTheme.border),
            ),
            child: Text(
              value,
              style: InspectorField.valueStyle.copyWith(
                color: EditorTheme.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class BoolEditorRow extends StatelessWidget {
  const BoolEditorRow({
    super.key,
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
          width: InspectorField.labelWidth,
          child: Text(label, style: InspectorField.labelStyle),
        ),
        Expanded(
          child: Semantics(
            label: label,
            checked: value,
            child: InkWell(
              onTap: () => onChanged(!value),
              borderRadius: BorderRadius.circular(InspectorField.radius),
              child: Container(
                height: InspectorField.height,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: InspectorField.boxDecoration(),
                child: Row(
                  children: [
                    Icon(
                      value
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      size: 14,
                      color: value
                          ? EditorTheme.primaryMutedLight
                          : EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      value ? 'On' : 'Off',
                      style: InspectorField.valueStyle.copyWith(
                        color: value
                            ? EditorTheme.textPrimary
                            : EditorTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ScrubFieldRow extends StatefulWidget {
  const ScrubFieldRow({
    super.key,
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
  State<ScrubFieldRow> createState() => _ScrubFieldRowState();
}

class _ScrubFieldRowState extends State<ScrubFieldRow> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(ScrubFieldRow old) {
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
      labelWidth: InspectorField.labelWidth,
    );
  }
}

/// A number between two limits as a slider, with the value beside it to
/// type: for a setting whose range matters more than its digits.
class SliderFieldRow extends StatelessWidget {
  const SliderFieldRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 0.05,
    this.decimals = 2,
    this.unit = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final int decimals;
  final String unit;

  /// Every value the drag passes through, and the one it ends on. (An
  /// inspector edit merges consecutive writes, so a drag is one undo.)
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: InspectorField.labelWidth,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: InspectorField.labelStyle,
        ),
      ),
      Expanded(
        child: SizedBox(
          height: InspectorField.height,
          child: EditorSlider(
            value: value,
            min: min,
            max: max,
            step: step,
            decimals: decimals,
            unit: unit,
            accent: EditorTheme.primaryMutedLight,
            onChanged: (v) {
              if (v != value) onChanged(v);
            },
            onChangeEnd: (v) {
              if (v != value) onChanged(v);
            },
          ),
        ),
      ),
    ],
  );
}

/// A vector on one row: the field's label, then a scrubbable cell per axis —
/// `Position  X [ 0.0 ]  Y [ 0.0 ]`. Each cell's letter is its drag handle,
/// in the axis colour the gizmos use.
class AxesFieldRow extends StatefulWidget {
  const AxesFieldRow({
    super.key,
    required this.label,
    required this.axes,
    required this.values,
    required this.scrubConfig,
    required this.onChanged,
    this.scrubConfigs,
    this.readOnly = false,
  }) : assert(axes.length == values.length),
       assert(scrubConfigs == null || scrubConfigs.length == values.length);

  final String label;

  /// The axis letters, one per value: `['X', 'Y']`.
  final List<String> axes;
  final List<double> values;
  final NumberScrubConfig scrubConfig;

  /// One per cell, where they differ — a row of separate fields, each with
  /// its own limits. Null gives every cell [scrubConfig].
  final List<NumberScrubConfig>? scrubConfigs;
  final bool readOnly;

  /// Every value, with the edited one replaced.
  final ValueChanged<List<double>> onChanged;

  /// Red, green, blue, then amber for a fourth.
  static const List<Color> axisColors = [
    Color(0xFFE5737B),
    Color(0xFF7DD68A),
    Color(0xFF6FA8F5),
    Color(0xFFE6C36B),
  ];

  @override
  State<AxesFieldRow> createState() => _AxesFieldRowState();
}

class _AxesFieldRowState extends State<AxesFieldRow> {
  final List<TextEditingController> _ctrls = [];
  final List<FocusNode> _focus = [];

  @override
  void initState() {
    super.initState();
    _grow();
  }

  void _grow() {
    while (_ctrls.length < widget.values.length) {
      _ctrls.add(
        TextEditingController(
          text: _fmt(_ctrls.length, widget.values[_ctrls.length]),
        ),
      );
      _focus.add(FocusNode());
    }
  }

  @override
  void didUpdateWidget(AxesFieldRow old) {
    super.didUpdateWidget(old);
    _grow();
    for (var i = 0; i < widget.values.length; i++) {
      final was = i < old.values.length ? old.values[i] : null;
      if (!_focus[i].hasFocus && widget.values[i] != was) {
        _ctrls[i].text = _fmt(i, widget.values[i]);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    for (final f in _focus) {
      f.dispose();
    }
    super.dispose();
  }

  NumberScrubConfig _config(int i) =>
      widget.scrubConfigs?[i] ?? widget.scrubConfig;

  /// A letter's width, or room for the longest of `Min` / `Max`.
  double get _cellLabelWidth {
    final longest = widget.axes.fold(0, (n, a) => math.max(n, a.length));
    return longest <= 1 ? 12 : 6.0 * longest + 6;
  }

  String _fmt(int i, double v) {
    final config = _config(i);
    if (config.integer) return v.round().toString();
    return v.toStringAsFixed(config.fractionDigits);
  }

  void _commit(int i) {
    final v = double.tryParse(_ctrls[i].text.trim());
    if (v == null) return;
    widget.onChanged(List<double>.of(widget.values)..[i] = v);
  }

  Widget _cell(int i) {
    final color = AxesFieldRow.axisColors[i % AxesFieldRow.axisColors.length];
    if (widget.readOnly) {
      return Row(
        children: [
          SizedBox(
            width: _cellLabelWidth,
            child: Text(
              widget.axes[i],
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _fmt(i, widget.values[i]),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
            ),
          ),
        ],
      );
    }
    return Tooltip(
      message: '${widget.label} ${widget.axes[i]}',
      child: ScrubbableNumberField(
        label: widget.axes[i],
        labelInside: true,
        labelColor: color,
        controller: _ctrls[i],
        focusNode: _focus[i],
        onCommit: () => _commit(i),
        config: _config(i),
      ),
    );
  }

  /// Below this a cell cannot show `-1234.5` next to its letter.
  static const double _minCell = 62;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      widget.label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w500,
      ),
    );
    final cells = Row(
      children: [
        for (var i = 0; i < widget.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _cell(i)),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final n = widget.values.length;
        final fits =
            box.maxWidth - 96 - 6 * (n - 1) >=
            (_minCell - 12 + _cellLabelWidth) * n;
        // A narrow panel: the label takes its own line, the axes still
        // share one.
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [label, const SizedBox(height: 4), cells],
          );
        }
        return Row(
          children: [
            SizedBox(width: 96, child: label),
            Expanded(child: cells),
          ],
        );
      },
    );
  }
}

class TextEditorRow extends StatelessWidget {
  const TextEditorRow({
    super.key,
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
          width: InspectorField.labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(label, style: InspectorField.labelStyle),
          ),
        ),
        Expanded(
          // Kept on Enter or when the field is left; an undo shows.
          child: CommitTextField(
            value: initialValue,
            style: InspectorField.valueStyle,
            maxLines: 4,
            onCommit: onSubmitted,
            decoration: InspectorField.decoration(),
          ),
        ),
      ],
    );
  }
}

class DropdownEditorRow extends StatelessWidget {
  const DropdownEditorRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.searchable = false,
    this.allowCustom = false,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  /// A filter box at the top of the list, for a long one.
  final bool searchable;

  /// With [searchable]: what was typed may be chosen even if it is not
  /// listed — an entity that does not exist yet.
  final bool allowCustom;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Text(label, style: InspectorField.labelStyle),
        ),
        Expanded(
          child: EditorDropdown<String>(
            value: value,
            options: [
              for (final option in options)
                EditorDropdownOption(value: option, label: option),
            ],
            searchable: searchable,
            customValue: allowCustom ? (typed) => typed : null,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ── Vertex list row (Polygon / RoundedPolygon / Chain) ────────────────────────

class OffsetListEditorRow extends StatefulWidget {
  const OffsetListEditorRow({
    super.key,
    required this.label,
    required this.points,
    required this.onChanged,
  });

  final String label;
  final List<Offset> points;
  final ValueChanged<List<Offset>> onChanged;

  @override
  State<OffsetListEditorRow> createState() => _OffsetListEditorRowState();
}

class _OffsetListEditorRowState extends State<OffsetListEditorRow> {
  late List<Offset> _points;

  @override
  void initState() {
    super.initState();
    _points = List<Offset>.from(widget.points);
  }

  @override
  void didUpdateWidget(OffsetListEditorRow old) {
    super.didUpdateWidget(old);
    if (!_sameOffsets(old.points, widget.points)) {
      _points = List<Offset>.from(widget.points);
    }
  }

  static bool _sameOffsets(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _commit() => widget.onChanged(List<Offset>.from(_points));

  void _setX(int index, double x) {
    setState(() => _points[index] = Offset(x, _points[index].dy));
    _commit();
  }

  void _setY(int index, double y) {
    setState(() => _points[index] = Offset(_points[index].dx, y));
    _commit();
  }

  void _remove(int index) {
    setState(() => _points.removeAt(index));
    _commit();
  }

  void _add() {
    final last = _points.isNotEmpty ? _points.last : Offset.zero;
    setState(() => _points.add(last + const Offset(20, 0)));
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.label, style: InspectorField.labelStyle),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _points.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: MiniNumberField(
                          value: _points[i].dx,
                          onSubmitted: (v) => _setX(i, v),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: MiniNumberField(
                          value: _points[i].dy,
                          onSubmitted: (v) => _setY(i, v),
                        ),
                      ),
                      const SizedBox(width: 4),
                      EditorIconButton(
                        icon: Icons.close,
                        tooltip: 'Remove this point',
                        onTap: () => _remove(i),
                      ),
                    ],
                  ),
                ),
              InkWell(
                onTap: _add,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 13,
                        color: EditorTheme.primaryMuted,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Add point',
                        style: TextStyle(
                          color: EditorTheme.primaryMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The controls below are the bare ones: a box and nothing else.
///
/// Every `…EditorRow` in this file is a *row* — a label column and then its
/// control — so one must never be put inside another row, or the label
/// column overflows whatever it was given. Anything building a row of its
/// own reaches for these instead.
class MiniNumberField extends StatelessWidget {
  const MiniNumberField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.fractionDigits = 1,
    this.inherited = false,
  });

  final double value;
  final ValueChanged<double> onSubmitted;

  /// How the number is written; 0 for a whole one.
  final int fractionDigits;

  /// Whether this is not the field's own value but the one it takes from
  /// somewhere else — a theme role, a parent. Drawn muted, so a number
  /// nobody chose here does not read as a number somebody did.
  final bool inherited;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey('$value:$inherited'),
      initialValue: value.toStringAsFixed(fractionDigits),
      style: TextStyle(
        color: inherited ? EditorTheme.textMuted : EditorTheme.textPrimary,
        fontSize: 11,
        fontStyle: inherited ? FontStyle.italic : FontStyle.normal,
      ),
      onFieldSubmitted: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null) onSubmitted(parsed);
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding: InspectorField.padding,
        filled: true,
        fillColor: InspectorField.fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: EditorTheme.primaryActive),
        ),
      ),
    );
  }
}

/// A bare line of text: the same box, no label column.
class MiniTextField extends StatelessWidget {
  const MiniTextField({
    super.key,
    required this.value,
    required this.onSubmitted,
    this.hint = '',
  });

  final String value;
  final ValueChanged<String> onSubmitted;
  final String hint;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(value),
    initialValue: value,
    style: InspectorField.valueStyle,
    onFieldSubmitted: onSubmitted,
    decoration: InspectorField.decoration().copyWith(
      hintText: hint.isEmpty ? null : hint,
      hintStyle: TextStyle(
        color: EditorTheme.textMuted,
        fontSize: InspectorField.fontSize,
      ),
    ),
  );
}

/// A bare colour swatch that opens the colour dialog: the same box, no
/// label column.
class MiniColorField extends StatelessWidget {
  const MiniColorField({
    super.key,
    required this.color,
    required this.onChanged,
    this.showHex = true,
    this.inherited = false,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  /// Whether the value is written beside the swatch. Off where the row is
  /// tight and the swatch says enough.
  final bool showHex;

  /// Whether the colour comes from somewhere else — a theme role. The
  /// swatch is still the colour that will be drawn; the text beside it is
  /// muted to say nobody chose it here.
  final bool inherited;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await JustColourDialog.show(
        context,
        initialSelection: shapePaintStyleToSelection(
          jge.ShapePaintStyle(color: color),
        ),
        view: ColourDialogView.colourOnly,
      );
      if (picked != null) {
        onChanged(selectionToShapePaintStyle(picked).color);
      }
    },
    borderRadius: BorderRadius.circular(InspectorField.radius),
    child: Container(
      height: InspectorField.height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: InspectorField.boxDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
          ),
          if (showHex) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
                overflow: TextOverflow.ellipsis,
                style: inherited
                    ? InspectorField.valueStyle.copyWith(
                        color: EditorTheme.textMuted,
                        fontStyle: FontStyle.italic,
                      )
                    : InspectorField.valueStyle,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ── Asset path picker row ─────────────────────────────────────────────────────

class AssetRefEditorRow extends StatefulWidget {
  const AssetRefEditorRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.extensions = const ['png'],
    this.onGenerate,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final List<String> extensions;

  /// When non-null, shows a wand button. Returns the generated file path or null.
  final Future<String?> Function()? onGenerate;

  @override
  State<AssetRefEditorRow> createState() => _AssetRefEditorRowState();
}

class _AssetRefEditorRowState extends State<AssetRefEditorRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _sizeAnim;
  final TextEditingController _searchCtrl = TextEditingController();
  List<String> _filePaths = [];
  bool _isExpanded = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: EditorMetrics.motionFast,
    );
    _sizeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _scanFiles();
  }

  @override
  void dispose() {
    _anim.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanFiles() async {
    final base = Directory.current.path.replaceAll(r'\', '/');
    final assetsDir = Directory('$base/assets');
    if (!await assetsDir.exists()) return;
    final exts = widget.extensions.map((e) => e.toLowerCase()).toSet();
    final paths = <String>[];
    await for (final entity in assetsDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (exts.contains(ext)) {
          final relative = entity.path
              .replaceAll(r'\', '/')
              .replaceFirst('$base/', '');
          paths.add(relative);
        }
      }
    }
    paths.sort();
    if (!mounted) return;
    setState(() => _filePaths = paths);
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

  Future<void> _handleGenerate() async {
    if (_isGenerating || widget.onGenerate == null) return;
    setState(() => _isGenerating = true);
    try {
      final path = await widget.onGenerate!();
      if (path != null && mounted) {
        widget.onChanged(path);
        await _scanFiles();
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _filePaths
        : _filePaths
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
              width: InspectorField.labelWidth,
              child: Text(widget.label, style: InspectorField.labelStyle),
            ),
            Expanded(
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) {
                  final ext = details.data.split('.').last.toLowerCase();
                  return widget.extensions
                      .map((e) => e.toLowerCase())
                      .contains(ext);
                },
                onAcceptWithDetails: (details) => _selectPath(details.data),
                builder: (context, candidateData, rejectedData) {
                  Color borderColor = EditorTheme.border;
                  if (candidateData.isNotEmpty) {
                    borderColor = EditorTheme.success;
                  } else if (rejectedData.isNotEmpty) {
                    borderColor = EditorTheme.error;
                  }
                  return GestureDetector(
                    onTap: _toggleExpanded,
                    child: Container(
                      height: InspectorField.height,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: EditorTheme.inputBg,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            widget.extensions.length == 1 &&
                                    widget.extensions.first.toLowerCase() ==
                                        'json'
                                ? Icons.data_object_rounded
                                : Icons.image_outlined,
                            size: 12,
                            color: EditorTheme.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.value.isEmpty
                                  ? 'Select ${widget.extensions.map((e) => e.toUpperCase()).join('/')}…'
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
            if (widget.onGenerate != null) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 24,
                height: 24,
                child: _isGenerating
                    ? Padding(
                        padding: EdgeInsets.all(5),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: EditorTheme.primaryActive,
                        ),
                      )
                    : Tooltip(
                        message: 'Generate template JSON',
                        child: InkWell(
                          onTap: _handleGenerate,
                          borderRadius: BorderRadius.circular(4),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: EditorTheme.primaryMuted,
                          ),
                        ),
                      ),
              ),
            ],
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
                      style: TextStyle(
                        color: EditorTheme.textPrimary,
                        fontSize: 11,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search PNG files…',
                        hintStyle: TextStyle(
                          color: EditorTheme.textMuted,
                          fontSize: 11,
                        ),
                        prefixIcon: Icon(
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
                          borderSide: BorderSide(color: EditorTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: EditorTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(
                            color: EditorTheme.primaryActive,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: EditorTheme.border),
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _filePaths.isEmpty
                                ? 'No ${widget.extensions.join('/').toUpperCase()} files found in assets/'
                                : 'No matches for "$query"',
                            style: TextStyle(
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
                                            style: TextStyle(
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
                                      Icon(
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
