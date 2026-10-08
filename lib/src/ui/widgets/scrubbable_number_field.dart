import '../inspector/field_style.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../kit/fields.dart' show PendingFieldEdits, isEscapeDown;

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

  /// The text when the field took the keyboard, or when it last kept a
  /// value: what is not a change, and what Esc or a typo puts back.
  String? _kept;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant ScrubbableNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    PendingFieldEdits.leave(_keep);
    super.dispose();
  }

  /// Taking the keyboard remembers what is there; leaving it — Tab, a click
  /// anywhere else — keeps what was typed, as Enter does. A value typed and
  /// left used to stay on screen without ever reaching the component.
  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _kept = widget.controller.text;
      PendingFieldEdits.join(_keep);
    } else {
      PendingFieldEdits.leave(_keep);
      _keep();
    }
  }

  /// Keeps what was typed, once per change: on Enter, on leaving the field,
  /// and before a command that runs while it is typed in (Save). Text that
  /// is not a number puts back what was there rather than writing 0.
  void _keep() {
    if (!mounted) return;
    final text = widget.controller.text;
    if (text == _kept) return;
    if (double.tryParse(text.trim()) == null) {
      if (_kept != null) widget.controller.text = _kept!;
      return;
    }
    _commit();
    _kept = widget.controller.text;
  }

  /// Esc, with a change typed: what was there, and out of the field. With
  /// nothing typed Esc is left to whoever wants it.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final kept = _kept;
    if (!isEscapeDown(event) || kept == null) return KeyEventResult.ignored;
    if (widget.controller.text == kept) return KeyEventResult.ignored;
    widget.controller.text = kept;
    widget.focusNode.unfocus();
    return KeyEventResult.handled;
  }

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
    // Scrubbed is kept: leaving the field after does not keep it again.
    if (widget.focusNode.hasFocus) _kept = text;
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

  Widget _field(bool highlight) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: TextField(
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
      // Enter keeps the value and the field keeps the keyboard. Once: this
      // and onSubmitted both used to run, writing every Enter twice.
      onEditingComplete: _keep,
    ),
  );
}
