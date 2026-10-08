/// Rearranging an entity's components in the inspector: by the grip on a
/// card's header, or from its ⋮ menu. The order is the entity's own
/// (`Entity.reorderComponents`) — what the inspector lists and what the
/// scene saves; the game finds components by type, so it runs as before.
/// Transform keeps the first place.
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../kit/buttons.dart' show EditorIconButton;
import '../widgets/editor_menu.dart';

/// Whether components of [type] keep the first place and do not move:
/// what an entity is placed by heads its list.
bool isPinnedComponent(Type type) => type == jge.TransformComponent;

/// [order] with [type] taken out and put back just before [before] or just
/// after [after] — at the end when neither is found. Pinned types stay
/// first, as they were.
List<Type> placeComponent(
  List<Type> order,
  Type type, {
  Type? before,
  Type? after,
}) {
  final rest = [
    for (final t in order)
      if (t != type) t,
  ];
  var at = before != null
      ? rest.indexOf(before)
      : after != null
      ? rest.indexOf(after) + 1
      : -1;
  if (at < 0 || (after != null && at == 0)) at = rest.length;
  rest.insert(at, type);
  return [
    for (final t in rest)
      if (isPinnedComponent(t)) t,
    for (final t in rest)
      if (!isPinnedComponent(t)) t,
  ];
}

/// What a drag carries: which component of which entity.
@immutable
class ComponentDrag {
  const ComponentDrag({
    required this.entity,
    required this.type,
    required this.title,
  });

  final jge.Entity entity;
  final Type type;
  final String title;
}

/// One card's place among the cards shown for its entity, and the moves
/// it can make. [shown] is the movable cards' types, in order.
class ComponentPlacement {
  const ComponentPlacement({
    required this.entity,
    required this.type,
    required this.title,
    required this.shown,
    required this.move,
  });

  final jge.Entity entity;
  final Type type;
  final String title;
  final List<Type> shown;

  /// Moves a component to just before or just after another.
  final void Function(Type type, {Type? before, Type? after}) move;

  int get _index => shown.indexOf(type);
  bool get canMoveUp => _index > 0;
  bool get canMoveDown => _index >= 0 && _index < shown.length - 1;

  void moveUp() {
    if (canMoveUp) move(type, before: shown[_index - 1]);
  }

  void moveDown() {
    if (canMoveDown) move(type, after: shown[_index + 1]);
  }

  void moveToTop() {
    if (canMoveUp) move(type, before: shown.first);
  }

  void moveToBottom() {
    if (canMoveDown) move(type, after: shown.last);
  }

  ComponentDrag get drag =>
      ComponentDrag(entity: entity, type: type, title: title);
}

/// The order a set of moves leaves [entity] in, or null when nothing moves.
List<Type>? reorderedTypes(
  jge.Entity entity,
  Type type, {
  Type? before,
  Type? after,
}) {
  final was = entity.componentTypes;
  final now = placeComponent(was, type, before: before, after: after);
  return listEquals(was, now) ? null : now;
}

/// The grip at the left of a card's header: drag it to move the card. The
/// inspector scrolls while it is held at the panel's top or bottom edge.
class ComponentDragGrip extends StatefulWidget {
  const ComponentDragGrip({super.key, required this.placement});

  final ComponentPlacement placement;

  @override
  State<ComponentDragGrip> createState() => _ComponentDragGripState();
}

class _ComponentDragGripState extends State<ComponentDragGrip> {
  EdgeDraggingAutoScroller? _scroller;

  void _start() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    _scroller = EdgeDraggingAutoScroller(scrollable, velocityScalar: 12);
  }

  void _follow(DragUpdateDetails details) =>
      _scroller?.startAutoScrollIfNecessary(
        Rect.fromCenter(center: details.globalPosition, width: 8, height: 32),
      );

  void _stop() {
    _scroller?.stopAutoScroll();
    _scroller = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grip = Icon(
      Icons.drag_indicator_rounded,
      size: 14,
      color: EditorTheme.textMuted,
    );
    return Tooltip(
      message: 'Drag to move ${widget.placement.title}',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<ComponentDrag>(
          data: widget.placement.drag,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: _start,
          onDragUpdate: _follow,
          onDragEnd: (_) => _stop(),
          onDraggableCanceled: (_, _) => _stop(),
          feedback: _Ghost(title: widget.placement.title),
          childWhenDragging: Opacity(opacity: 0.3, child: grip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: grip,
          ),
        ),
      ),
    );
  }
}

/// What follows the pointer while a card is dragged: its name, in a chip.
class _Ghost extends StatelessWidget {
  const _Ghost({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: const Offset(10, -12),
    child: Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: EditorTheme.dialogBg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: EditorTheme.primaryBright),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: EditorTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// A card a dragged one can be dropped on: above it in its top half, below
/// it in its bottom half, a line showing which. A pinned card takes a drop
/// only below it — nothing goes above it.
class ComponentDropZone extends StatefulWidget {
  const ComponentDropZone({
    super.key,
    required this.entity,
    required this.type,
    required this.onDrop,
    required this.child,
  });

  final jge.Entity entity;

  /// The type of the card this is.
  final Type type;

  /// [dragged] dropped just before ([above]) or just after this card.
  final void Function(Type dragged, {required bool above}) onDrop;
  final Widget child;

  @override
  State<ComponentDropZone> createState() => _ComponentDropZoneState();
}

class _ComponentDropZoneState extends State<ComponentDropZone> {
  /// Where the line is, while something hovers: true above, false below.
  bool? _above;

  bool get _pinned => isPinnedComponent(widget.type);

  void _hover(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final above =
        !_pinned && box.globalToLocal(global).dy < box.size.height / 2;
    if (above != _above) setState(() => _above = above);
  }

  @override
  Widget build(BuildContext context) => DragTarget<ComponentDrag>(
    onWillAcceptWithDetails: (details) =>
        identical(details.data.entity, widget.entity) &&
        details.data.type != widget.type,
    onMove: (details) => _hover(details.offset),
    onLeave: (_) => setState(() => _above = null),
    onAcceptWithDetails: (details) {
      final above = _above ?? false;
      setState(() => _above = null);
      widget.onDrop(details.data.type, above: above);
    },
    builder: (context, _, _) => Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_above != null)
          Positioned(
            left: 0,
            right: 0,
            top: _above! ? -4 : null,
            bottom: _above! ? null : -4,
            height: 2,
            child: ColoredBox(color: EditorTheme.primaryBright),
          ),
      ],
    ),
  );
}

/// The ⋮ on a card's header: the moves, for the keyboard and for a place
/// further than a drag comfortably reaches.
class ComponentPlaceMenu extends StatelessWidget {
  const ComponentPlaceMenu({super.key, required this.placement});

  final ComponentPlacement placement;

  Future<void> _open(BuildContext anchor) async {
    final p = placement;
    final chosen = await showEditorMenuBelow<VoidCallback>(anchor, [
      editorMenuItem(
        p.moveUp,
        'Move up',
        icon: Icons.arrow_upward_rounded,
        enabled: p.canMoveUp,
      ),
      editorMenuItem(
        p.moveDown,
        'Move down',
        icon: Icons.arrow_downward_rounded,
        enabled: p.canMoveDown,
      ),
      editorMenuDivider(),
      editorMenuItem(
        p.moveToTop,
        'Move to top',
        icon: Icons.vertical_align_top_rounded,
        enabled: p.canMoveUp,
      ),
      editorMenuItem(
        p.moveToBottom,
        'Move to bottom',
        icon: Icons.vertical_align_bottom_rounded,
        enabled: p.canMoveDown,
      ),
    ]);
    chosen?.call();
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => EditorIconButton(
      icon: Icons.more_vert_rounded,
      tooltip: 'Move ${placement.title}',
      onTap: () => _open(anchor),
    ),
  );
}
