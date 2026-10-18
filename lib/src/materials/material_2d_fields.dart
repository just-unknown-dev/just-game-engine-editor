import 'package:flutter/material.dart';
import 'package:just_editor_core/just_editor_core.dart';

/// A gradient's stops: a bar of the gradient, then each stop's place
/// (0 to 1) and colour, with a way to add one (up to [maxItems]) and take
/// one away (never below two).
class GradientStopsEditor extends StatelessWidget {
  const GradientStopsEditor({
    super.key,
    required this.stops,
    required this.onChanged,
    this.onPreview,
    this.onPreviewEnd,
    this.maxItems = 8,
  });

  /// Where each colour sits (0-1), and the colour (ARGB).
  final List<(double, int)> stops;

  /// The stops changed: one undo step.
  final ValueChanged<List<(double, int)>> onChanged;

  /// A colour being picked, shown before it is a step.
  final ValueChanged<List<(double, int)>>? onPreview;

  /// The picking stopped.
  final VoidCallback? onPreviewEnd;

  /// The most stops.
  final int maxItems;

  static List<(double, int)> _sorted(List<(double, int)> stops) =>
      [...stops]..sort((a, b) => a.$1.compareTo(b.$1));

  /// [stops] with one more in the middle of the widest gap, its colour
  /// halfway between the stops either side.
  static List<(double, int)> withOneMore(List<(double, int)> stops) {
    final s = _sorted(stops);
    if (s.isEmpty) return const [(0, 0xFF000000), (1, 0xFFFFFFFF)];
    if (s.length == 1) return [...s, (1, 0xFFFFFFFF)];
    var at = 0;
    for (var i = 1; i < s.length - 1; i++) {
      if (s[i + 1].$1 - s[i].$1 > s[at + 1].$1 - s[at].$1) at = i;
    }
    final a = s[at], b = s[at + 1];
    final mid = Color.lerp(Color(a.$2), Color(b.$2), 0.5)!.toARGB32();
    return _sorted([...s, ((a.$1 + b.$1) / 2, mid)]);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted(stops);
    final muted = TextStyle(color: EditorTheme.textMuted, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 14,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: EditorTheme.border),
            gradient: sorted.length < 2
                ? null
                : LinearGradient(
                    colors: [for (final s in sorted) Color(s.$2)],
                    stops: [for (final s in sorted) s.$1.clamp(0.0, 1.0)],
                  ),
          ),
        ),
        for (var i = 0; i < sorted.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: MiniNumberField(
                    key: ValueKey('stop$i:${sorted[i].$1}'),
                    value: sorted[i].$1,
                    fractionDigits: 2,
                    onSubmitted: (v) {
                      if (!v.isFinite) return;
                      final next = [...sorted];
                      next[i] = (v.clamp(0.0, 1.0), sorted[i].$2);
                      onChanged(_sorted(next));
                    },
                  ),
                ),
                const SizedBox(width: 6),
                MiniColorField(
                  key: ValueKey('stopColour$i:${sorted[i].$2}'),
                  color: Color(sorted[i].$2),
                  title: 'Stop ${i + 1}',
                  onPreview: onPreview == null
                      ? null
                      : (c) {
                          final next = [...sorted];
                          next[i] = (sorted[i].$1, c.toARGB32());
                          onPreview!(next);
                        },
                  onPreviewEnd: onPreviewEnd,
                  onChanged: (c) {
                    final next = [...sorted];
                    next[i] = (sorted[i].$1, c.toARGB32());
                    onChanged(next);
                  },
                ),
                const Spacer(),
                if (sorted.length > 2)
                  EditorButton(
                    label: 'Remove',
                    kind: EditorButtonKind.ghost,
                    onPressed: () => onChanged([...sorted]..removeAt(i)),
                  ),
              ],
            ),
          ),
        Row(
          children: [
            Text('${sorted.length} of $maxItems', style: muted),
            const Spacer(),
            EditorButton(
              label: 'Add stop',
              icon: Icons.add,
              kind: EditorButtonKind.ghost,
              onPressed: sorted.length >= maxItems
                  ? null
                  : () => onChanged(withOneMore(sorted)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Colour swaps: each colour and what it becomes, with a way to add one
/// (up to [maxItems]) — offering the colours [suggestions] has first — and
/// take one away.
class ColourSwapsEditor extends StatelessWidget {
  const ColourSwapsEditor({
    super.key,
    required this.swaps,
    required this.onChanged,
    this.onPreview,
    this.onPreviewEnd,
    this.maxItems = 8,
    this.suggestions = const [],
  });

  /// Each colour (ARGB) and what it becomes.
  final List<(int, int)> swaps;

  /// The swaps changed: one undo step.
  final ValueChanged<List<(int, int)>> onChanged;

  /// A colour being picked, shown before it is a step.
  final ValueChanged<List<(int, int)>>? onPreview;

  /// The picking stopped.
  final VoidCallback? onPreviewEnd;

  /// The most swaps.
  final int maxItems;

  /// Colours a new swap starts from, in order — the colours of what the
  /// preview shows — skipping those already swapped.
  final List<int> suggestions;

  /// [swaps] with one more: the first of [suggestions] not swapped yet,
  /// becoming itself; black to white when none is left.
  static List<(int, int)> withOneMore(
    List<(int, int)> swaps,
    List<int> suggestions,
  ) {
    final taken = {for (final s in swaps) s.$1};
    for (final c in suggestions) {
      if (!taken.contains(c)) return [...swaps, (c, c)];
    }
    return [...swaps, (0xFF000000, 0xFFFFFFFF)];
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: EditorTheme.textMuted, fontSize: 11);
    List<(int, int)> replaced(int i, {int? from, int? to}) => [
      for (var j = 0; j < swaps.length; j++)
        j == i ? (from ?? swaps[j].$1, to ?? swaps[j].$2) : swaps[j],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (swaps.isEmpty) Text('Nothing swapped yet.', style: muted),
        for (var i = 0; i < swaps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                MiniColorField(
                  key: ValueKey('from$i:${swaps[i].$1}'),
                  color: Color(swaps[i].$1),
                  showHex: false,
                  title: 'Swap ${i + 1}: this colour',
                  onPreview: onPreview == null
                      ? null
                      : (c) => onPreview!(replaced(i, from: c.toARGB32())),
                  onPreviewEnd: onPreviewEnd,
                  onChanged: (c) => onChanged(replaced(i, from: c.toARGB32())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: EditorTheme.textMuted,
                  ),
                ),
                MiniColorField(
                  key: ValueKey('to$i:${swaps[i].$2}'),
                  color: Color(swaps[i].$2),
                  showHex: false,
                  title: 'Swap ${i + 1}: becomes',
                  onPreview: onPreview == null
                      ? null
                      : (c) => onPreview!(replaced(i, to: c.toARGB32())),
                  onPreviewEnd: onPreviewEnd,
                  onChanged: (c) => onChanged(replaced(i, to: c.toARGB32())),
                ),
                const Spacer(),
                EditorButton(
                  label: 'Remove',
                  kind: EditorButtonKind.ghost,
                  onPressed: () => onChanged([...swaps]..removeAt(i)),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Text('${swaps.length} of $maxItems', style: muted),
            const Spacer(),
            EditorButton(
              label: 'Add swap',
              icon: Icons.add,
              kind: EditorButtonKind.ghost,
              onPressed: swaps.length >= maxItems
                  ? null
                  : () => onChanged(withOneMore(swaps, suggestions)),
            ),
          ],
        ),
      ],
    );
  }
}
