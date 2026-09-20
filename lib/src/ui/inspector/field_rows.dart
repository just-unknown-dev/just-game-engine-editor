/// The inspector's row widgets: one label-plus-control per field kind.
///
/// Public so a module's own field editor can be built from the same parts
/// and look like the rest of the inspector.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_colours/just_colours.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../widgets/scrubbable_number_field.dart';
import '../widgets/editor_dropdown.dart';

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

class ReadonlyRow extends StatelessWidget {
  const ReadonlyRow({super.key, required this.label, required this.value});

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
      labelWidth: 96,
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
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
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
          width: 96,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.label,
              style: const TextStyle(
                color: EditorTheme.textMuted,
                fontSize: 10,
              ),
            ),
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
                        child: _MiniNumberField(
                          value: _points[i].dx,
                          onSubmitted: (v) => _setX(i, v),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _MiniNumberField(
                          value: _points[i].dy,
                          onSubmitted: (v) => _setY(i, v),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => _remove(i),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                onTap: _add,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
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

class _MiniNumberField extends StatelessWidget {
  const _MiniNumberField({required this.value, required this.onSubmitted});

  final double value;
  final ValueChanged<double> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: ValueKey(value),
      initialValue: value.toStringAsFixed(1),
      style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      onFieldSubmitted: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null) onSubmitted(parsed);
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    );
  }
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
      duration: const Duration(milliseconds: 160),
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
                    ? const Padding(
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
                          child: const Icon(
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
                            _filePaths.isEmpty
                                ? 'No ${widget.extensions.join('/').toUpperCase()} files found in assets/'
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
