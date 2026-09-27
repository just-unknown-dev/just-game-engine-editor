import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../core/constants/editor_constants.dart';
import '../inspector/field_rows.dart';
import 'tileset_session.dart';

/// Where a click inside a tile lands for a terrain set of [type]: the Wang
/// slot of the nearest corner or edge. [local] is in the tile's pixels.
int wangSlotAt(Offset local, double width, double height, WangType type) {
  final spots = <int, Offset>{
    WangSetData.top: Offset(width / 2, 0),
    WangSetData.topRight: Offset(width, 0),
    WangSetData.right: Offset(width, height / 2),
    WangSetData.bottomRight: Offset(width, height),
    WangSetData.bottom: Offset(width / 2, height),
    WangSetData.bottomLeft: Offset(0, height),
    WangSetData.left: Offset(0, height / 2),
    WangSetData.topLeft: Offset.zero,
  };
  final slots = switch (type) {
    WangType.corner => WangSetData.cornerSlots,
    WangType.edge => WangSetData.edgeSlots,
    WangType.mixed => spots.keys.toList(),
  };
  var best = slots.first;
  var bestD = double.infinity;
  for (final s in slots) {
    final d = (spots[s]! - local).distanceSquared;
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  }
  return best;
}

/// The terrains of a tileset: its terrain sets, each set's terrains, and
/// the tools to give tiles their corners and edges.
///
/// In the grid beside it, a click on a tile's corner or edge gives it the
/// chosen terrain; Alt+click clears it; Shift+click makes the whole tile
/// that terrain. A template does a whole standard block at once.
class WangSetEditor extends StatefulWidget {
  const WangSetEditor({
    super.key,
    required this.session,
    required this.set,
    required this.color,
    required this.onSet,
    required this.onColor,
  });

  final TilesetSession session;

  /// The terrain set chosen, by index.
  final int? set;

  /// The terrain painted with, from 1; 0 clears.
  final int color;

  final ValueChanged<int?> onSet;
  final ValueChanged<int> onColor;

  @override
  State<WangSetEditor> createState() => _WangSetEditorState();
}

class _WangSetEditorState extends State<WangSetEditor> {
  WangTemplate _template = WangTemplate.corner16;
  int? _firstTile;

  TilesetSession get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final sets = s.data.wangSets;
    final chosen = widget.set != null && widget.set! < sets.length
        ? widget.set
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _Heading('TERRAIN SETS')),
            PopupMenuButton<WangType>(
              tooltip: 'Add a terrain set',
              color: EditorTheme.menuBg,
              onSelected: (type) => widget.onSet(s.addWangSet(type: type)),
              itemBuilder: (context) => [
                for (final (type, text) in const [
                  (WangType.corner, 'Corner set: terrains meet at corners'),
                  (WangType.edge, 'Edge set: roads, rivers, fences'),
                  (WangType.mixed, 'Mixed set: corners and edges (blob)'),
                ])
                  PopupMenuItem(
                    value: type,
                    height: 28,
                    child: Text(text, style: _value),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.add,
                  size: 15,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (sets.isEmpty)
          const Text(
            'None yet. A terrain set says which tiles show which terrain at '
            'their corners or edges, so the Terrain tool can join them.',
            style: TextStyle(fontSize: 11, color: EditorTheme.textMuted),
          ),
        for (var i = 0; i < sets.length; i++)
          Material(
            color: i == chosen ? EditorTheme.selectionBg : Colors.transparent,
            child: InkWell(
              onTap: () => widget.onSet(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      switch (sets[i].type) {
                        WangType.corner => Icons.crop_square,
                        WangType.edge => Icons.border_all,
                        WangType.mixed => Icons.blur_on,
                      },
                      size: 13,
                      color: EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        sets[i].name.isEmpty
                            ? 'Terrain set ${i + 1}'
                            : sets[i].name,
                        overflow: TextOverflow.ellipsis,
                        style: _value,
                      ),
                    ),
                    Text(
                      '${sets[i].colors.length} · ${sets[i].type.name}',
                      style: _muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (chosen != null) ...[
          const SizedBox(height: 10),
          _setEditor(chosen, sets[chosen]),
        ],
      ],
    );
  }

  Widget _setEditor(int index, WangSetData set) {
    final coverage = s.coverage(index);
    final first = _firstTile ?? s.primary ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(
          label: 'Name',
          child: MiniTextField(
            value: set.name,
            onSubmitted: (v) => s.renameWangSet(index, v.trim()),
          ),
        ),
        _Line(
          label: 'Matches',
          child: PopupMenuButton<WangType>(
            tooltip: 'What the set matches tiles by',
            color: EditorTheme.menuBg,
            onSelected: (t) => s.setWangType(index, t),
            itemBuilder: (context) => [
              for (final t in WangType.values)
                PopupMenuItem(
                  value: t,
                  height: 28,
                  child: Text(t.name, style: _value),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(set.type.name, style: _value),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: EditorTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: _Heading('TERRAINS')),
            _Icon(
              icon: Icons.add,
              tooltip: 'Add a terrain',
              onTap: () => widget.onColor(s.addWangColor(index)),
            ),
          ],
        ),
        for (var c = 1; c <= set.colors.length; c++)
          _ColorRow(
            key: ValueKey(('terrain', index, c)),
            color: set.colors[c - 1],
            isChosen: widget.color == c,
            onChoose: () => widget.onColor(c),
            onName: (v) => s.editWangColor(index, c, name: v),
            onArgb: (v) => s.editWangColor(index, c, argb: v),
            onRemove: () {
              s.removeWangColor(index, c);
              // The terrains after it moved down one.
              if (widget.color >= c) {
                widget.onColor(widget.color - 1 < 1 ? 1 : widget.color - 1);
              }
            },
          ),
        Material(
          color: widget.color == 0
              ? EditorTheme.selectionBg
              : Colors.transparent,
          child: InkWell(
            onTap: () => widget.onColor(0),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_fix_normal,
                    size: 13,
                    color: EditorTheme.textMuted,
                  ),
                  SizedBox(width: 6),
                  Text('Eraser: no terrain', style: _value),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const _Heading('TEMPLATE'),
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<WangTemplate>(
            tooltip: 'A standard layout',
            color: EditorTheme.menuBg,
            onSelected: (t) => setState(() => _template = t),
            itemBuilder: (context) => [
              for (final t in WangTemplate.values)
                PopupMenuItem(
                  value: t,
                  height: 28,
                  child: Text(_templateLabel(t), style: _value),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_templateLabel(_template), style: _value),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: EditorTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            const Text('from tile', style: _muted),
            const SizedBox(width: 4),
            SizedBox(
              width: 44,
              child: MiniNumberField(
                value: first.toDouble(),
                fractionDigits: 0,
                onSubmitted: (v) => setState(() => _firstTile = v.round()),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => s.applyTemplate(index, _template, first),
              child: const Text('Apply', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          coverage.possible == null
              ? '${coverage.tiles} tiles, ${coverage.combinations} different'
              : '${coverage.tiles} tiles cover ${coverage.combinations} of the '
                    '${coverage.possible} combinations',
          style:
              coverage.possible != null &&
                  coverage.combinations < coverage.possible!
              ? const TextStyle(fontSize: 11, color: Color(0xFFFFB74D))
              : _muted,
        ),
        const SizedBox(height: 6),
        const Text(
          'Click a tile\'s corner or edge to give it the chosen terrain. '
          'Alt+click clears it; Shift+click gives the whole tile.',
          style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
        ),
      ],
    );
  }

  static String _templateLabel(WangTemplate t) => switch (t) {
    WangTemplate.corner16 => '16 corners (4 × 4)',
    WangTemplate.blob47 => '47 blob (7 wide)',
  };
}

const TextStyle _value = TextStyle(
  fontSize: 11,
  color: EditorTheme.textPrimary,
);
const TextStyle _muted = TextStyle(fontSize: 11, color: EditorTheme.textMuted);

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: EditorTheme.textMuted,
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: _muted)),
        Expanded(child: child),
      ],
    ),
  );
}

class _Icon extends StatelessWidget {
  const _Icon({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14, color: EditorTheme.textSecondary),
      ),
    ),
  );
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    super.key,
    required this.color,
    required this.isChosen,
    required this.onChoose,
    required this.onName,
    required this.onArgb,
    required this.onRemove,
  });

  final WangColorData color;
  final bool isChosen;
  final VoidCallback onChoose;
  final ValueChanged<String> onName;
  final ValueChanged<int> onArgb;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
    color: isChosen ? EditorTheme.selectionBg : Colors.transparent,
    child: InkWell(
      onTap: onChoose,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(
              isChosen
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 13,
              color: isChosen
                  ? EditorTheme.primaryBright
                  : EditorTheme.textMuted,
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 40,
              child: MiniColorField(
                color: Color(color.color),
                showHex: false,
                onChanged: (c) => onArgb(c.toARGB32()),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: MiniTextField(value: color.name, onSubmitted: onName),
            ),
            _Icon(
              icon: Icons.close,
              tooltip: 'Remove the terrain',
              onTap: onRemove,
            ),
          ],
        ),
      ),
    ),
  );
}
