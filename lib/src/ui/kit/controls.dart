import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';
import 'fields.dart';
import 'focus.dart';

/// On or off: a small switch that takes the keyboard like a button.
class EditorToggle extends StatelessWidget {
  const EditorToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.accent,
  });

  final bool value;

  /// Null greys it out.
  final ValueChanged<bool>? onChanged;

  /// What a screen reader says it switches.
  final String label;

  /// The accent when null.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? EditorTheme.accent;
    final enabled = onChanged != null;
    return Semantics(
      label: label,
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: FocusOutline(
          radius: EditorMetrics.radiusPill,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(EditorMetrics.radiusPill),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? () => onChanged!(!value) : null,
              hoverColor: accent.withValues(alpha: 0.10),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AnimatedContainer(
                  duration: EditorMetrics.motionFast,
                  width: 36,
                  height: 20,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: value
                        ? accent.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(
                      EditorMetrics.radiusPill,
                    ),
                    border: Border.all(
                      color: value
                          ? accent
                          : Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: AnimatedAlign(
                    duration: EditorMetrics.motionFast,
                    curve: Curves.easeOutCubic,
                    alignment: value
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: value ? Colors.white : EditorTheme.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a few: the choices side by side, the picked one lit. Narrower
/// than its labels, the choices share what there is.
///
/// A choice in [disabled] shows greyed with a lock and cannot be picked;
/// its [tooltips] entry says why — say it on the page too, since a tooltip
/// alone is found only by pointing at it.
class EditorSegmented<T> extends StatelessWidget {
  const EditorSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.accent,
    this.disabled = const {},
    this.tooltips = const {},
    this.expand = false,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final Color? accent;

  /// Choices shown but not available.
  final Set<T> disabled;

  /// A tooltip for a choice — why it is disabled, say.
  final Map<T, String> tooltips;

  /// Whether the choices share all the width they are given, in equal
  /// parts, rather than each taking what its label needs.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? EditorTheme.accent;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDarker,
        borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final (option, label) in options)
            Flexible(
              fit: expand ? FlexFit.tight : FlexFit.loose,
              child: _Segment(
                label: label,
                selected: option == value,
                accent: accent,
                enabled: !disabled.contains(option),
                tooltip: tooltips[option],
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? EditorTheme.textMuted
        : selected
        ? accent
        : EditorTheme.textSecondary;
    Widget segment = Semantics(
      selected: selected,
      enabled: enabled,
      button: true,
      child: FocusOutline(
        child: Material(
          color: selected ? accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // Still focusable, so the keyboard can reach the tooltip.
            onTap: enabled ? onTap : null,
            canRequestFocus: true,
            hoverColor: accent.withValues(alpha: 0.10),
            child: Container(
              height: EditorMetrics.minTarget,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (!enabled) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.lock_outline, size: 12, color: color),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final tip = tooltip;
    if (tip != null) segment = Tooltip(message: tip, child: segment);
    return segment;
  }
}

/// A continuous value: a slider to drag, and the number beside it to type.
///
/// [onChanged] follows the drag, for a live preview; [onChangeEnd] is the
/// value to keep — at the end of a drag, or when a typed number is entered.
/// [displayScale] and [unit] are how the number reads: 1.1 shown as `110%`
/// is a scale of 100 and a unit of `%`.
class EditorSlider extends StatefulWidget {
  const EditorSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    required this.onChangeEnd,
    this.accent,
    this.displayScale = 1,
    this.decimals = 0,
    this.unit = '',
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final Color? accent;
  final double displayScale;
  final int decimals;
  final String unit;

  @override
  State<EditorSlider> createState() => _EditorSliderState();
}

class _EditorSliderState extends State<EditorSlider> {
  late final TextEditingController _text = TextEditingController(
    text: _format(widget.value),
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  // Leaving the field keeps what was typed, as Enter does.
  void _onFocus() {
    if (!_focus.hasFocus && mounted) _commitText();
  }

  @override
  void didUpdateWidget(covariant EditorSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focus.hasFocus) {
      _text.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _text.dispose();
    super.dispose();
  }

  String _format(double value) =>
      (value * widget.displayScale).toStringAsFixed(widget.decimals);

  double _snap(double value) {
    final clamped = value.clamp(widget.min, widget.max).toDouble();
    final steps = ((clamped - widget.min) / widget.step).round();
    final snapped = (widget.min + steps * widget.step)
        .clamp(widget.min, widget.max)
        .toDouble();
    // 0.85 + 3 × 0.05 is 0.9999999999999999, not the default of 1.
    return double.parse(snapped.toStringAsFixed(6));
  }

  void _commitText() {
    final typed = double.tryParse(
      _text.text.replaceAll(RegExp(r'[^0-9.\-]'), ''),
    );
    final next = typed == null
        ? widget.value
        : _snap(typed / widget.displayScale);
    _text.text = _format(next);
    if (next != widget.value) widget.onChangeEnd(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? EditorTheme.accent;
    final divisions = ((widget.max - widget.min) / widget.step).round();
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.14),
              trackShape: const RoundedRectSliderTrackShape(),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              tickMarkShape: SliderTickMarkShape.noTickMark,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: widget.value.clamp(widget.min, widget.max).toDouble(),
              min: widget.min,
              max: widget.max,
              divisions: divisions > 0 ? divisions : null,
              onChanged: (v) => widget.onChanged(_snap(v)),
              onChangeEnd: (v) => widget.onChangeEnd(_snap(v)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 72,
          height: 26,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _commitText(),
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            cursorColor: accent,
            decoration: editorFieldDecoration(
              suffixText: widget.unit.isEmpty ? null : widget.unit,
            ),
          ),
        ),
      ],
    );
  }
}

/// Round colour swatches, the picked one ringed.
class EditorSwatches extends StatelessWidget {
  const EditorSwatches({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  /// Id, label, colour.
  final List<(String, String, Color)> options;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    alignment: WrapAlignment.end,
    children: [
      for (final (id, label, colour) in options)
        Tooltip(
          message: label,
          child: Semantics(
            label: label,
            selected: id == selectedId,
            button: true,
            child: FocusOutline(
              radius: EditorMetrics.radiusPill,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(id),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 26,
                    height: 26,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: id == selectedId ? colour : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                      ),
                      child: id == selectedId
                          ? const Icon(
                              Icons.check_rounded,
                              size: 12,
                              color: Color(0xDD000000),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// A filter or a switch that says how many things it would show:
/// `Errors 3`. Lit while [selected].
class EditorChip extends StatelessWidget {
  const EditorChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.color,
    this.icon,
    this.tooltip,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  /// The accent when [selected]; the editor's accent when null.
  final Color? color;
  final IconData? icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? EditorTheme.primaryBright;
    final radius = BorderRadius.circular(EditorMetrics.radiusPill);
    final chip = Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Semantics(
        button: true,
        selected: selected,
        child: FocusOutline(
          radius: EditorMetrics.radiusPill,
          child: Material(
            color: selected
                ? color.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: EditorMetrics.minTarget,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected
                        ? color.withValues(alpha: 0.6)
                        : EditorTheme.borderStrong.withValues(alpha: 0.6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 11,
                        color: selected ? color : EditorTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? EditorTheme.textPrimary
                            : EditorTheme.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: TextStyle(
                          color: selected ? color : EditorTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// A small status pill: tinted with its [accent] rather than filled with it.
///
/// A solid bright pill with white text is both the loudest thing on screen
/// and the hardest to read (white on the warning yellow is about 1.4:1):
/// this is a faint fill, a hair of border, and the accent as the text.
class EditorBadge extends StatelessWidget {
  const EditorBadge({
    super.key,
    required this.label,
    this.accent,
    this.showDot = false,
  });

  final String label;

  /// What it is tinted with; the accent when null.
  final Color? accent;

  /// A leading dot, for a badge that reports a state rather than a label.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final accent = this.accent ?? EditorTheme.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(EditorMetrics.radiusPill),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EditorMetrics.space(8),
          vertical: EditorMetrics.space(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDot) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A key as it is printed on a keycap: `Ctrl+Shift+Z`.
class KeyCap extends StatelessWidget {
  const KeyCap(this.keys, {super.key});

  final String keys;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: EditorTheme.surfaceDarker,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusXs),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Text(
      keys,
      style: TextStyle(
        color: EditorTheme.textSecondary,
        fontSize: 10.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}
