import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/just_editor_core.dart';

// What both material windows — 2-D and 3-D — are built from, so they look
// and work alike: side panels sized by dragging their edge, cards that
// fold, the preview's toolbar parts and the chips over its foot, and a
// menu to add from.

/// The line between two groups of a toolbar's tools.
class ToolSeparator extends StatelessWidget {
  /// A separator.
  const ToolSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: EditorTheme.textPrimary.withValues(alpha: 0.12),
  );
}

/// The edge between a side panel and the preview, dragged to size the
/// panel: [onDrag] is told how far across it moved (to the right, more).
class PanelResizeHandle extends StatelessWidget {
  /// A handle.
  const PanelResizeHandle({super.key, required this.onDrag});

  /// How far it was dragged across, in logical pixels.
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
      child: const SizedBox(
        width: 5,
        child: Center(child: VerticalDivider(width: 1)),
      ),
    ),
  );
}

/// A note over the preview's foot — what it shows, a hint, what went
/// wrong — with a way to close it when [onClose] is given.
class PreviewChip extends StatelessWidget {
  /// A chip saying [text].
  const PreviewChip(
    this.text, {
    super.key,
    required this.icon,
    this.warn = false,
    this.onClose,
  });

  /// What it says.
  final String text;

  /// Drawn before it.
  final IconData icon;

  /// Whether it says what went wrong.
  final bool warn;

  /// Closes it; no close button when null.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(8, 3, onClose == null ? 8 : 2, 3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: warn
            ? EditorTheme.warning
            : Colors.white.withValues(alpha: 0.10),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: warn ? EditorTheme.warning : Colors.white70,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: warn ? EditorTheme.warning : Colors.white,
              fontSize: 11,
            ),
          ),
        ),
        if (onClose != null)
          EditorIconButton(
            icon: Icons.close,
            tooltip: 'Close',
            iconSize: 12,
            size: 18,
            color: Colors.white70,
            onTap: onClose,
          ),
      ],
    ),
  );
}

/// A size of the preview to jump to: its name, what it does, whether it is
/// the one shown.
final class ZoomStep {
  /// A step.
  const ZoomStep(
    this.label,
    this.tooltip, {
    required this.selected,
    required this.onTap,
  });

  /// Its name on the chip: `Fit`, `1:1`, `2×`.
  final String label;

  /// What it does, with its key.
  final String tooltip;

  /// Whether the preview is at it.
  final bool selected;

  /// Goes to it.
  final VoidCallback onTap;
}

/// The preview's zoom: out, how big it is ([label]), in, and [steps] to
/// jump to.
class ZoomControls extends StatelessWidget {
  /// The controls.
  const ZoomControls({
    super.key,
    required this.label,
    required this.onZoomOut,
    required this.onZoomIn,
    this.steps = const [],
  });

  /// How big the preview is, as it says it.
  final Widget label;

  /// A step smaller.
  final VoidCallback onZoomOut;

  /// A step bigger.
  final VoidCallback onZoomIn;

  /// Sizes to jump to.
  final List<ZoomStep> steps;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      EditorIconButton(
        icon: Icons.remove,
        tooltip: 'Zoom out (−)',
        onTap: onZoomOut,
      ),
      SizedBox(width: 78, child: Center(child: label)),
      EditorIconButton(
        icon: Icons.add,
        tooltip: 'Zoom in (+)',
        onTap: onZoomIn,
      ),
      for (final s in steps)
        EditorChip(
          label: s.label,
          tooltip: s.tooltip,
          selected: s.selected,
          onTap: s.onTap,
        ),
    ],
  );
}

/// The keyboard sign whose tooltip lists a window's keys.
class ShortcutsHint extends StatelessWidget {
  /// The sign for [shortcuts], one key and what it does after another.
  const ShortcutsHint(this.shortcuts, {super.key});

  /// The keys, as they are listed.
  final String shortcuts;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: shortcuts,
    textStyle: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Colors.white,
    ),
    child: Icon(
      Icons.keyboard_outlined,
      size: 16,
      color: EditorTheme.textMuted,
    ),
  );
}

/// Which cards are folded, by id, for as long as the editor runs: a card
/// folded stays folded in the next material opened.
abstract final class MaterialCardFolds {
  static final Set<String> _folded = {};

  /// Whether the card [id] is folded.
  static bool isFolded(String id) => _folded.contains(id);

  /// Folds the card [id], or unfolds it.
  static void set(String id, bool folded) =>
      folded ? _folded.add(id) : _folded.remove(id);

  /// Unfolds every card; for tests.
  static void clear() => _folded.clear();
}

/// A group of a material's values, or one of its effects: a header with a
/// fold, its [title] (after [leading], a switch), its [actions], then a
/// line on what it does and its rows ([children]) when it is not folded.
class MaterialCard extends StatelessWidget {
  /// A card.
  const MaterialCard({
    super.key,
    required this.title,
    required this.folded,
    required this.onFold,
    this.leading,
    this.description = '',
    this.actions = const [],
    this.highlighted = false,
    this.children = const [],
  });

  /// Its name.
  final String title;

  /// Whether only its header shows.
  final bool folded;

  /// Folds it (true) or unfolds it.
  final ValueChanged<bool> onFold;

  /// Before its name: an effect's switch.
  final Widget? leading;

  /// What it does, under its header.
  final String description;

  /// Buttons at the header's end: reset, solo, whose it is.
  final List<Widget> actions;

  /// Whether its edge is drawn in the accent colour: an effect shown alone.
  final bool highlighted;

  /// Its rows.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
    decoration: BoxDecoration(
      color: EditorTheme.textPrimary.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: highlighted
            ? EditorTheme.accent
            : EditorTheme.textPrimary.withValues(alpha: 0.10),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 3, 4, 3),
          child: Row(
            children: [
              EditorIconButton(
                icon: folded ? Icons.chevron_right : Icons.expand_more,
                tooltip: folded ? 'Unfold' : 'Fold',
                iconSize: 16,
                size: 22,
                onTap: () => onFold(!folded),
              ),
              if (leading case final leading?) ...[
                leading,
                const SizedBox(width: 6),
              ],
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onFold(!folded),
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        if (!folded) ...[
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
              child: Text(
                description,
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
              ),
            ),
          ...children,
          const SizedBox(height: 6),
        ],
      ],
    ),
  );
}

/// One choice of a [showPickMenu]: a value, its name and a line on it.
final class PickMenuItem<T> {
  /// A choice.
  const PickMenuItem(this.value, this.label, {this.detail = ''});

  /// What picking it gives.
  final T value;

  /// Its name.
  final String label;

  /// A line on what it is.
  final String detail;
}

/// Choices under a heading in a [showPickMenu].
final class PickMenuGroup<T> {
  /// A group.
  const PickMenuGroup(this.title, this.items);

  /// Its heading.
  final String title;

  /// Its choices.
  final List<PickMenuItem<T>> items;
}

/// Opens a menu below [anchor] (a button's context): a search box, then
/// [groups] of choices, each with a line on what it is. Typing keeps those
/// whose name, line or group has it; Enter picks the first shown. The value
/// picked, or null when the menu was closed.
Future<T?> showPickMenu<T extends Object>(
  BuildContext anchor, {
  required List<PickMenuGroup<T>> groups,
  double width = 320,
  String hint = 'Search',
}) {
  final button = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    button.localToGlobal(
      button.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    ),
    button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  ).translate(0, 2);
  return showMenu<T>(
    context: anchor,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: EditorTheme.menuBg,
    elevation: 6,
    menuPadding: EdgeInsets.zero,
    constraints: BoxConstraints(minWidth: width, maxWidth: width),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: EditorTheme.border),
    ),
    items: [_PickMenuBody<T>(groups: groups, hint: hint)],
  );
}

class _PickMenuBody<T extends Object> extends PopupMenuEntry<T> {
  const _PickMenuBody({required this.groups, required this.hint});

  final List<PickMenuGroup<T>> groups;
  final String hint;

  @override
  double get height => 32;

  @override
  bool represents(T? value) => false;

  @override
  State<_PickMenuBody<T>> createState() => _PickMenuBodyState<T>();
}

class _PickMenuBodyState<T extends Object> extends State<_PickMenuBody<T>> {
  String _query = '';

  List<PickMenuGroup<T>> get _shown {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.groups;
    bool has(String s) => s.toLowerCase().contains(q);
    return [
      for (final g in widget.groups)
        if (has(g.title))
          g
        else if (g.items.where((i) => has(i.label) || has(i.detail)).toList()
            case final items when items.isNotEmpty)
          PickMenuGroup(g.title, items),
    ];
  }

  void _pick(T value) => Navigator.of(context).pop(value);

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 32,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: EditorTheme.border)),
          ),
          child: TextField(
            autofocus: true,
            onChanged: (text) => setState(() => _query = text),
            onSubmitted: (_) {
              final first = _shown.firstOrNull?.items.firstOrNull;
              if (first != null) _pick(first.value);
            },
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
            cursorColor: EditorTheme.primary,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(4, 9, 8, 9),
              prefixIcon: Icon(
                Icons.search,
                size: 14,
                color: EditorTheme.textMuted,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 26),
              hintText: widget.hint,
              hintStyle: TextStyle(color: EditorTheme.textMuted, fontSize: 12),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            children: [
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Text(
                    _query.trim().isEmpty
                        ? 'Nothing left to add'
                        : 'Nothing matches',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
              for (final g in shown) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                  child: Text(
                    g.title.toUpperCase(),
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                for (final i in g.items) _item(i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(PickMenuItem<T> item) => InkWell(
    onTap: () => _pick(item.value),
    hoverColor: EditorTheme.hoverBg,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 12),
          ),
          if (item.detail.isNotEmpty)
            Text(
              item.detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
            ),
        ],
      ),
    ),
  );
}
