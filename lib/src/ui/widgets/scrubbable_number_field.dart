import '../inspector/field_style.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// Drag-to-scrub configuration for numeric inspector fields.
class NumberScrubConfig {
  const NumberScrubConfig({
    this.step = 1.0,
    this.pixelsPerStep = 12.0,
    this.fractionDigits = 2,
    this.min,
    this.max,
    this.integer = false,
    this.suffix,
  });

  final double step;
  final double pixelsPerStep;
  final int fractionDigits;
  final double? min;
  final double? max;
  final bool integer;

  /// The unit shown after the value — `px`, `/s` — or none.
  final String? suffix;
}

class ScrubbableNumberField extends StatefulWidget {
  const ScrubbableNumberField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
    required this.config,
    this.labelWidth = 52,
    this.labelInside = false,
    this.labelColor,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCommit;
  final NumberScrubConfig config;
  final double labelWidth;

  /// Draw the label inside the box, before the value, instead of in a
  /// column of its own. What an axis cell does, so that every box on every
  /// row starts at the same place.
  final bool labelInside;

  /// The label's colour at rest — an axis letter's red, green or blue.
  /// Null is the usual muted text.
  final Color? labelColor;

  @override
  State<ScrubbableNumberField> createState() => _ScrubbableNumberFieldState();
}

class _ScrubbableNumberFieldState extends State<ScrubbableNumberField> {
  bool _isHovering = false;
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartValue = 0;

  double _parseCurrentValue() {
    return double.tryParse(widget.controller.text.trim()) ?? 0.0;
  }

  double _clampValue(double value) {
    var result = value;
    if (widget.config.min != null) {
      result = math.max(result, widget.config.min!);
    }
    if (widget.config.max != null) {
      result = math.min(result, widget.config.max!);
    }
    return result;
  }

  String _formatValue(double value) {
    if (widget.config.integer) {
      return value.round().toString();
    }
    return value.toStringAsFixed(widget.config.fractionDigits);
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartX = details.globalPosition.dx;
      _dragStartValue = _parseCurrentValue();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final deltaX = details.globalPosition.dx - _dragStartX;
    final ratio = deltaX / widget.config.pixelsPerStep;
    var nextValue = _dragStartValue + (ratio * widget.config.step);
    if (widget.config.integer) {
      nextValue = nextValue.roundToDouble();
    }
    nextValue = _clampValue(nextValue);
    final text = _formatValue(nextValue);
    if (widget.controller.text == text) return;

    widget.controller.text = text;
    widget.onCommit();
    setState(() {});
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
    });
  }

  /// Clamps whatever the user typed to [NumberScrubConfig.min]/[max] before
  /// notifying [onCommit] — drag-scrubbing already clamps via [_onDragUpdate],
  /// but typing a value directly and pressing Enter/Tab used to bypass that
  /// entirely and commit an out-of-range value straight to the component.
  void _commit() {
    final clamped = _clampValue(_parseCurrentValue());
    final text = _formatValue(clamped);
    if (widget.controller.text != text) {
      widget.controller.text = text;
    }
    widget.onCommit();
  }

  /// The label, which is also the handle a value is scrubbed by.
  Widget _handle({required bool highlight, EdgeInsets? padding}) => MouseRegion(
    cursor: SystemMouseCursors.resizeLeftRight,
    onEnter: (_) => setState(() => _isHovering = true),
    onExit: (_) => setState(() => _isHovering = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () =>
          _onDragEnd(DragEndDetails(primaryVelocity: 0)),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Text(
          widget.label,
          style: TextStyle(
            color: highlight
                ? EditorTheme.primaryMutedLight
                : widget.labelColor ?? EditorTheme.textMuted,
            fontSize: 10,
            fontWeight: widget.labelColor == null
                ? FontWeight.w500
                : FontWeight.w800,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final highlight = _isDragging || _isHovering;
    if (widget.labelInside) return _field(highlight);

    return Row(
      children: <Widget>[
        SizedBox(
          width: widget.labelWidth,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            onEnter: (_) => setState(() => _isHovering = true),
            onExit: (_) => setState(() => _isHovering = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: () =>
                  _onDragEnd(DragEndDetails(primaryVelocity: 0)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: highlight
                          ? EditorTheme.primaryMutedLight
                          : widget.labelColor ?? EditorTheme.textMuted,
                      fontSize: 10,
                      fontWeight: widget.labelColor == null
                          ? FontWeight.w500
                          : FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: _field(highlight)),
      ],
    );
  }

  Widget _field(bool highlight) => TextField(
    controller: widget.controller,
    focusNode: widget.focusNode,
    style: InspectorField.valueStyle,
    decoration: InspectorField.decoration(
      prefix: widget.labelInside
          ? _handle(
              highlight: highlight,
              padding: const EdgeInsets.only(left: 8, right: 6),
            )
          : null,
      suffix: widget.config.suffix,
    ),
    keyboardType: const TextInputType.numberWithOptions(
      signed: true,
      decimal: true,
    ),
    onSubmitted: (_) => _commit(),
    onEditingComplete: _commit,
  );
}
