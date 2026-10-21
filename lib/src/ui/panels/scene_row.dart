import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' show SceneMode;

import 'package:just_editor_core/host.dart';

/// `saved 5 min ago`: when [savedAt] was, from [now], in words.
String savedAgo(DateTime savedAt, DateTime now) {
  final d = now.difference(savedAt);
  if (d.inSeconds < 45) return 'saved just now';
  if (d.inMinutes < 60) return 'saved ${math.max(1, d.inMinutes)} min ago';
  if (d.inHours < 24) return 'saved ${d.inHours} h ago';
  if (d.inDays == 1) return 'saved yesterday';
  if (d.inDays < 7) return 'saved ${d.inDays} days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = savedAt.year == now.year ? '' : ' ${savedAt.year}';
  return 'saved ${savedAt.day} ${months[savedAt.month - 1]}$year';
}

/// `2026-09-29 14:05`, for a tooltip.
String savedAt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// One scene in the Scenes list.
///
/// Its place in the play order (a grip to drag it by, while the list can be
/// reordered), its name — the part matching the search lit — a START tag on
/// the scene the game begins with, and a line about it: 2D or 3D, how many
/// entities, when it was saved. The ⋮ shows on hover and on the row the
/// keys are on; a right-click opens the same menu.
class SceneRow extends StatefulWidget {
  const SceneRow({
    super.key,
    required this.name,
    required this.onOpen,
    required this.onMenu,
    this.summary,
    this.playIndex,
    this.isStart = false,
    this.isProtected = false,
    this.isCursor = false,
    this.query = '',
    this.dragIndex,
    this.showPlace = false,
    this.compact = false,
    this.now,
  });

  final String name;
  final SceneSummary? summary;

  /// Where it is in the play order, from 0; null when the game never loads
  /// it.
  final int? playIndex;

  /// The first in the play order: where the game starts.
  final bool isStart;
  final bool isProtected;

  /// The row the keys act on.
  final bool isCursor;

  /// What is being searched for, lit in the name.
  final String query;

  /// Its index in a reorderable list; null when it cannot be dragged.
  final int? dragIndex;

  /// Leads with its place in the play order rather than its kind.
  final bool showPlace;

  /// One line and no place number: the Recent group.
  final bool compact;

  /// The clock the saved time is read against; now when null.
  final DateTime? now;

  final VoidCallback onOpen;

  /// Opens the row's menu at a global point.
  final void Function(Offset at) onMenu;

  @override
  State<SceneRow> createState() => _SceneRowState();
}

class _SceneRowState extends State<SceneRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final lit = widget.isCursor;
    final showMore = _hover || lit;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => widget.onMenu(d.globalPosition),
        child: Semantics(
          button: true,
          selected: lit,
          label: [
            'Scene ${widget.name}',
            if (widget.isStart) 'where the game starts',
            if (widget.playIndex != null)
              'number ${widget.playIndex! + 1} in the play order',
          ].join(', '),
          child: Material(
            color: lit
                ? EditorTheme.selectionBg
                : _hover
                ? EditorTheme.hoverBg
                : Colors.transparent,
            child: InkWell(
              onTap: widget.onOpen,
              excludeFromSemantics: true,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: lit ? EditorTheme.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  8,
                  widget.compact ? 4 : 6,
                  6,
                  widget.compact ? 4 : 6,
                ),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Center(child: _leading())),
                    const SizedBox(width: 8),
                    Expanded(child: _body()),
                    if (widget.isProtected)
                      Tooltip(
                        message:
                            "Used by the game's own code: it can't be "
                            'renamed or deleted',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.shield_outlined,
                            size: 13,
                            color: EditorTheme.textMuted,
                          ),
                        ),
                      ),
                    Visibility.maintain(
                      visible: showMore,
                      child: Builder(
                        builder: (context) => EditorIconButton(
                          icon: Icons.more_vert_rounded,
                          tooltip: 'More for ${widget.name}',
                          size: 24,
                          onTap: () {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            if (box == null) return;
                            widget.onMenu(
                              box.localToGlobal(
                                box.size.bottomLeft(Offset.zero),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The grip, the place number, or the kind of scene.
  Widget _leading() {
    final muted = EditorTheme.textMuted;
    if (widget.compact) {
      return Icon(Icons.history_rounded, size: 14, color: muted);
    }
    final dragIndex = widget.dragIndex;
    if (dragIndex != null && (_hover || widget.isCursor)) {
      return ReorderableDragStartListener(
        index: dragIndex,
        child: Tooltip(
          message: 'Drag to change the play order',
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Icon(Icons.drag_indicator_rounded, size: 16, color: muted),
          ),
        ),
      );
    }
    if (!widget.showPlace) return _kindIcon(muted);
    final index = widget.playIndex;
    if (index == null) {
      return Tooltip(
        message: "Not in the play order (scenes.json): the game never loads it",
        child: Text('–', style: TextStyle(color: muted, fontSize: 12)),
      );
    }
    return Text(
      '${index + 1}',
      style: TextStyle(
        color: widget.isStart ? EditorTheme.success : EditorTheme.textSecondary,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _kindIcon(Color colour) => Icon(
    widget.summary?.mode == SceneMode.threeD
        ? Icons.view_in_ar_rounded
        : Icons.map_outlined,
    size: 15,
    color: colour,
  );

  Widget _body() {
    final name = Row(
      children: [
        Flexible(child: _name()),
        if (widget.isStart) ...[
          const SizedBox(width: 6),
          Tooltip(
            message: 'The game starts here: first in the play order',
            child: EditorBadge(label: 'START', accent: EditorTheme.success),
          ),
        ],
      ],
    );
    if (widget.compact) return name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [name, const SizedBox(height: 3), _facts()],
    );
  }

  /// The name, with what the search matched lit.
  Widget _name() {
    final style = TextStyle(
      color: EditorTheme.textPrimary,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
    );
    final query = widget.query.trim().toLowerCase();
    final at = query.isEmpty ? -1 : widget.name.toLowerCase().indexOf(query);
    if (at < 0) {
      return Text(widget.name, style: style, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: widget.name.substring(0, at)),
          TextSpan(
            text: widget.name.substring(at, at + query.length),
            style: TextStyle(
              color: EditorTheme.primaryBright,
              backgroundColor: EditorTheme.accent.withValues(alpha: 0.18),
            ),
          ),
          TextSpan(text: widget.name.substring(at + query.length)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  /// `2D · 14 entities · saved 5 min ago`.
  Widget _facts() {
    final muted = TextStyle(color: EditorTheme.textMuted, fontSize: 10.5);
    final summary = widget.summary;
    if (summary == null) return Text(' ', style: muted);
    if (!summary.isReadable) {
      return Text(
        "Can't read this file",
        style: muted.copyWith(color: EditorTheme.warning),
      );
    }
    final count = summary.entityCount ?? 0;
    return Row(
      children: [
        _ModeTag(summary.mode!),
        const SizedBox(width: 6),
        Flexible(
          child: Tooltip(
            message: 'Saved ${savedAt(summary.savedAt)}',
            child: Text(
              '$count ${count == 1 ? 'entity' : 'entities'} · '
              '${savedAgo(summary.savedAt, widget.now ?? DateTime.now())}',
              style: muted,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}

/// `2D` or `3D`, outlined.
class _ModeTag extends StatelessWidget {
  const _ModeTag(this.mode);

  final SceneMode mode;

  @override
  Widget build(BuildContext context) {
    final threeD = mode == SceneMode.threeD;
    final colour = threeD ? EditorTheme.info : EditorTheme.textSecondary;
    return Tooltip(
      message: threeD ? 'A 3D scene' : 'A 2D scene',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(EditorMetrics.radiusXs),
          border: Border.all(color: colour.withValues(alpha: 0.5)),
        ),
        child: Text(
          threeD ? '3D' : '2D',
          style: TextStyle(
            color: colour,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
