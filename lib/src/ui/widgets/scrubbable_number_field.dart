import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/ecs/generator/component_registry.dart' show NumberScrubConfig;
import '../theme/editor_theme.dart';

export '../../core/ecs/generator/component_registry.dart' show NumberScrubConfig;

class ScrubbableNumberField extends StatefulWidget {
  const ScrubbableNumberField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
    required this.config,
    this.labelWidth = 52,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCommit;
  final NumberScrubConfig config;
  final double labelWidth;

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

  @override
  Widget build(BuildContext context) {
    final highlight = _isDragging || _isHovering;

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
                          : EditorTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              filled: true,
              fillColor: EditorTheme.surfaceDarker,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: EditorTheme.primaryMutedLight),
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
          ),
        ),
      ],
    );
  }
}
