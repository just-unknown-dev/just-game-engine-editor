/// The scene tree: what is in the scene, and the place its shape is
/// edited.
///
/// Built on [SceneTreeModel], so this draws a flat list and decides what a
/// click means; it works out nothing about the hierarchy itself. Every
/// edit it makes goes through the editor's one undo stack.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton, kTouchSlop;
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/entity/entity_ops.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import '../overlay/docks/extra/extra_docks.dart';
import '../widgets/editor_menu.dart';
import 'scene_tree_controller.dart';
import 'scene_tree_model.dart';
import 'scene_tree_row.dart';

class SceneTreePanel extends StatefulWidget {
  const SceneTreePanel({
    super.key,
    required this.scope,
    required this.entities,
    this.controller,
    this.authored,
    this.onFocusEntity,
    this.onCreateUi,
    this.onToggleUiMode,
    this.uiModeOn = false,
    this.contents = TreeContents.world,
    this.isHidden,
    this.isLocked,
    this.onToggleHidden,
    this.onToggleLocked,
  });

  final EditorScope scope;

  /// What makes, moves and deletes entities — all of it undoable.
  final EntityOps entities;

  /// What is open and what is being searched for. One is made if none is
  /// given, which is what a test usually wants.
  final SceneTreeController? controller;

  /// What existed when play began; anything else is the running game's and
  /// is shown under a divider. Null while not playing.
  final Set<jge.EntityId>? authored;

  /// Puts the viewport on an entity — what double-clicking a row does.
  final void Function(jge.Entity entity)? onFocusEntity;

  /// Makes a piece of interface of the given kind.
  final void Function(String kind)? onCreateUi;

  final void Function(bool on)? onToggleUiMode;
  final bool uiModeOn;

  /// The world's tree, or the interface editor's own.
  final TreeContents contents;

  final bool Function(jge.Entity entity)? isHidden;
  final bool Function(jge.Entity entity)? isLocked;
  final void Function(jge.Entity entity)? onToggleHidden;
  final void Function(jge.Entity entity)? onToggleLocked;

  @override
  State<SceneTreePanel> createState() => _SceneTreePanelState();
}

class _SceneTreePanelState extends State<SceneTreePanel> {
  late final SceneTreeController _tree =
      widget.controller ?? SceneTreeController(world: () => _world);
  final FocusNode _keys = FocusNode(debugLabel: 'sceneTree');
  final TextEditingController _search = TextEditingController();

  /// The row a drag is over, and where on it. Only meaningful while
  /// [_dragging]: a drag let go of outside the list leaves no `onLeave`
  /// behind it, and the line it drew used to stay on screen afterwards,
  /// where it read as an underline on a perfectly ordinary row.
  jge.EntityId? _dragOver;
  DropZone _dropZone = DropZone.onto;

  /// The list itself, so a drag near its edges knows where they are.
  final GlobalKey _listKey = GlobalKey(debugLabel: 'sceneTreeList');

  /// A drag resting on a shut row opens it after a moment, so something
  /// can be dropped inside without letting go of it first.
  Timer? _hoverExpand;
  jge.EntityId? _hoverExpandOf;

  /// How long a drag has to rest before the row opens.
  static const Duration _hoverExpandDelay = Duration(milliseconds: 500);

  /// How near the top or bottom the pointer has to be for the list to
  /// start moving under it.
  static const double _autoScrollMargin = 22;

  /// Held rather than asked for each time: the scope's container may be
  /// closed by the time this is disposed, and a panel taking itself down
  /// must not need anything to still be open.
  late final EditorSceneState _sceneState = widget.scope.sceneState;

  jge.World get _world => widget.scope.world;

  @override
  void initState() {
    super.initState();
    // The tree follows the selection, wherever it was made.
    _sceneState.selectedEntity.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _sceneState.selectedEntity.removeListener(_onSelectionChanged);
    _hoverExpand?.cancel();
    _cancelPendingRename();
    if (widget.controller == null) _tree.dispose();
    _keys.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Opens a shut row the drag has been resting on, and keeps the list
  /// moving while the pointer is at its edge.
  void _onDragMove(jge.Entity onto, DropZone zone, Offset at) {
    final canHold =
        onto.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
        false;
    if (zone == DropZone.onto && canHold && !_tree.isExpanded(onto.id)) {
      if (_hoverExpandOf != onto.id) {
        _hoverExpandOf = onto.id;
        _hoverExpand?.cancel();
        _hoverExpand = Timer(_hoverExpandDelay, () {
          if (mounted) _tree.expand(onto.id);
        });
      }
    } else {
      _cancelHoverExpand();
    }
    _autoScroll(at);
  }

  void _cancelHoverExpand() {
    _hoverExpand?.cancel();
    _hoverExpand = null;
    _hoverExpandOf = null;
  }

  /// Moves the list when a drag reaches its top or bottom edge, so
  /// something can be dropped further away than one screenful.
  void _autoScroll(Offset globalPosition) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !_tree.scroll.hasClients) return;
    final dy = box.globalToLocal(globalPosition).dy;
    final position = _tree.scroll.position;
    double? to;
    if (dy < _autoScrollMargin) {
      to = position.pixels - kSceneTreeRowTileHeight;
    } else if (dy > box.size.height - _autoScrollMargin) {
      to = position.pixels + kSceneTreeRowTileHeight;
    }
    if (to == null) return;
    position.jumpTo(to.clamp(0.0, position.maxScrollExtent));
  }

  void _onSelectionChanged() {
    final selected = _sceneState.selectedEntity.value;
    if (selected == null) return;
    _tree.reveal(selected.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _searchField(),
        // Its own builder: the chips say what is being filtered by, so
        // they have to be redrawn when that changes.
        SignalBuilder<TreeFilter>(
          signal: _tree.filter,
          builder: (context, filter, _) => _filterChips(filter),
        ),
        Expanded(
          child: SignalConsumer(
            signals: [
              _sceneState.activeScene,
              _sceneState.selectedEntity,
              _sceneState.multiSelectedIds,
              _sceneState.revision,
              _tree.expanded,
              _tree.colors,
              _tree.filter,
              _tree.renaming,
              _tree.renameError,
            ],
            builder: (context, _) => _list(),
          ),
        ),
      ],
    );
  }

  Widget _list() {
    final tree = SceneTreeModel.build(
      world: _world,
      rootOrder: _sceneState.rootOrder(_world),
      expanded: _tree.expanded.value,
      filter: _tree.filter.value,
      authored: widget.authored,
      contents: widget.contents,
      withProblems: _tree.filter.value.problems
          ? {
              for (final problem in ProblemScan.of(widget.scope).problems)
                ?problem.entity?.id,
            }
          : const {},
    );
    _tree.rows = tree;

    // A reveal asked for a row to be brought into view; the list now knows
    // where that row is.
    final target = _tree.takeScrollTarget();
    if (target != null) {
      final index = tree.indexOf(target);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _tree.scrollToIndex(index),
        );
      }
    }

    if (tree.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _tree.filter.value.isEmpty
              ? 'Nothing in the scene yet.'
              : 'Nothing matches.',
          style: const TextStyle(
            color: EditorTheme.primaryMuted,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      );
    }

    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: Listener(
        // Every pointer up in the list reaches here, rows included, so
        // one no row claimed is a click on the empty part of the tree:
        // nothing is selected. A widget *behind* the list would never
        // hear it — a scrollable swallows taps.
        onPointerDown: (event) {
          _emptyPressedAt = event.position;
          _emptyPressedPrimary = event.buttons & kPrimaryButton != 0;
        },
        onPointerUp: (event) {
          final tookIt = _rowTookIt;
          _rowTookIt = false;
          if (tookIt || !_emptyPressedPrimary) return;
          if ((event.position - _emptyPressedAt).distance > kTouchSlop) return;
          _keys.requestFocus();
          if (_tree.renaming.value != null) return;
          _sceneState.clearSelection();
        },
        child: _rowList(tree),
      ),
    );
  }

  Widget _rowList(SceneTree tree) {
    return DragTarget<List<jge.Entity>>(
      // Dropped past the last row: out of everything, to the top level —
      // which in the interface tree is no place at all, so there a drop
      // on nothing does nothing.
      onWillAcceptWithDetails: (_) => widget.contents != TreeContents.ui,
      onAcceptWithDetails: (details) {
        if (_dragOver != null) return;
        widget.entities.reparentAll(details.data, null);
      },
      builder: (context, _, _) => ListView.builder(
        key: _listKey,
        controller: _tree.scroll,
        padding: EdgeInsets.zero,
        itemCount: tree.length,
        itemExtent: kSceneTreeRowTileHeight,
        itemBuilder: (context, index) => _row(tree, index),
      ),
    );
  }

  Widget _row(SceneTree tree, int index) {
    final row = tree.rows[index];
    final entity = row.entity;
    final selected = _sceneState.selectedEntity.value?.id == entity.id;

    SceneTreeRowTile tileFor(DropZone? zone) => SceneTreeRowTile(
      row: row,
      isSelected: selected,
      isMultiSelected: _sceneState.isInMultiSelection(entity.id),
      icon: widget.scope.iconFor(entity),
      color: _tree.colorOf(entity.id),
      // What the editor and the modules have to say about this entity:
      // its problems, what animates it, a camera that is live.
      trailing: [
        for (final decoration in widget.scope.rowDecorations)
          ?decoration.build(context, entity),
      ],
      dropZone: zone,
      isRenaming: _tree.renaming.value == entity.id,
      renameError: _tree.renaming.value == entity.id
          ? _tree.renameError.value
          : null,
      onCommitRename: (name) => _commitRename(entity, name),
      onCancelRename: _cancelRename,
      isHidden: widget.isHidden?.call(entity) ?? false,
      isLocked: widget.isLocked?.call(entity) ?? false,
      onToggleHidden: widget.onToggleHidden == null
          ? null
          : () => widget.onToggleHidden!(entity),
      onToggleLocked: widget.onToggleLocked == null
          ? null
          : () => widget.onToggleLocked!(entity),
      onToggleExpand: ({required bool subtree}) {
        if (subtree) {
          _tree.expandSubtree(entity.id);
        } else {
          _tree.toggle(entity.id);
        }
      },
    );

    final selection = _dragSelection(entity);
    return _Draggable(
      entity: entity,
      selection: selection,
      enabled: _canDrag(selection),
      onEnded: () => setState(() {
        _cancelPendingRename();
        _dragOver = null;
        _cancelHoverExpand();
      }),
      child: Listener(
        // Clicks are read here rather than through a `GestureDetector`
        // with `onDoubleTap`, which holds every single click back for the
        // double-click window before it reports it. Selecting has to be
        // immediate; a second click that lands quickly focuses the
        // viewport, and a slower one on a row that is already selected
        // renames it — the way a file list behaves.
        onPointerDown: (event) {
          _pressedAt = event.position;
          // A `Listener` hears every button. Only the left one selects,
          // renames or focuses — the right one belongs to the context
          // menu, and used to open the rename box on its way past.
          _pressedPrimary = event.buttons & kPrimaryButton != 0;
          _pressedOn = _pressedPrimary ? entity.id : null;
        },
        onPointerUp: (event) => _onRowPointerUp(event, entity, tree),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (details) =>
              _showMenu(context, entity, details.globalPosition),
          // The row's own context. `_row` has none of its own, so
          // `context` here was the panel's: every drop was measured
          // against the whole list, which put the pointer far below the
          // 22 pixels a row is tall and made every hover read as
          // "between", whatever it was over.
          child: Builder(
            builder: (rowContext) => DragTarget<List<jge.Entity>>(
              // Whether this row can take them at all. Not where on the
              // row the pointer is: that is `onMove`'s answer, and asking
              // for it here read the *last* row's zone, so a row refused
              // on a stale answer never got the move that would have
              // corrected it and stayed dead for the rest of the drag.
              onWillAcceptWithDetails: (details) =>
                  _canAccept(details.data, entity),
              onMove: (details) {
                final box = rowContext.findRenderObject() as RenderBox?;
                final zone = _zoneFor(
                  entity,
                  box == null
                      ? DropZone.onto
                      : dropZoneFor(
                          box.globalToLocal(details.offset).dy,
                          kSceneTreeRowTileHeight,
                        ),
                );
                if (_dragOver != entity.id || _dropZone != zone) {
                  setState(() {
                    _dragOver = entity.id;
                    _dropZone = zone;
                  });
                }
                _onDragMove(entity, zone, details.offset);
              },
              onLeave: (_) {
                if (_hoverExpandOf == entity.id) _cancelHoverExpand();
                if (_dragOver == entity.id) {
                  setState(() => _dragOver = null);
                }
              },
              onAcceptWithDetails: (details) {
                final zone = _zoneFor(entity, _dropZone);
                _cancelHoverExpand();
                setState(() => _dragOver = null);
                _drop(details.data, entity, zone);
              },
              // Whether a drag is over this row is Flutter's own answer,
              // not a flag of mine: a drag let go of outside the list
              // leaves no `onLeave` behind it, and the line I was drawing
              // from my own state stayed on screen afterwards, where it
              // read as an underline on an ordinary selected row.
              builder: (context, candidates, _) => tileFor(
                candidates.isEmpty ? null : _zoneFor(entity, _dropZone),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the pointer went down, so a drag is not mistaken for a click.
  Offset _pressedAt = Offset.zero;

  /// Whether it was the left button. A pointer *up* carries no buttons,
  /// so which one it was has to be remembered from the press.
  bool _pressedPrimary = false;
  jge.EntityId? _pressedOn;

  /// Whether the pointer that just went up was on a row.
  bool _rowTookIt = false;

  /// Where a press that might turn out to be on empty space began.
  Offset _emptyPressedAt = Offset.zero;
  bool _emptyPressedPrimary = false;

  /// The last click that counted, for spotting the second of a pair.
  jge.EntityId? _clickedId;
  Duration _clickedAt = Duration.zero;

  /// How close together two clicks have to be to be one double click.
  ///
  /// Half a second, which is what Windows means by one, and comfortably
  /// clear of [_renameGap] so that an unhurried double click focuses the
  /// viewport instead of opening the rename box.
  static const Duration _doubleClick = Duration(milliseconds: 500);

  /// A rename waiting to see whether a second click is coming.
  Timer? _renameAfterDoubleClick;

  void _cancelPendingRename() {
    _renameAfterDoubleClick?.cancel();
    _renameAfterDoubleClick = null;
  }

  void _onRowPointerUp(
    PointerUpEvent event,
    jge.Entity entity,
    SceneTree tree,
  ) {
    if (_pressedOn != entity.id || !_pressedPrimary) return;
    _pressedOn = null;
    _rowTookIt = true;
    // A drag that happens to end here is not a click.
    // Only a press that wandered right off the row is not a click.
    // Dragging takes a deliberate hold now, so nothing else here needs
    // to second-guess what the pointer was doing: a click that moved a
    // little is still a click, and used to be thrown away as a drag.
    if ((event.position - _pressedAt).distance > kSceneTreeRowTileHeight * 2) {
      return;
    }
    // A click anywhere else takes the name being typed: pulling the
    // focus off the box is what commits it. The click then goes on to
    // mean what it would have meant anyway.
    final wasSelected = _sceneState.selectedEntity.value?.id == entity.id;
    if (_tree.renaming.value != null) {
      _keys.requestFocus();
      _clickedId = null;
      _clickedAt = event.timeStamp;
      _select(entity, tree, control: false, shift: false);
      return;
    }

    // Device time, not wall-clock: a test advances its own clock, and
    // `DateTime.now()` would not move with it.
    final sinceLast = event.timeStamp - _clickedAt;
    final twice = _clickedId == entity.id && sinceLast < _doubleClick;
    _clickedId = entity.id;
    _clickedAt = event.timeStamp;

    if (twice) {
      // The second of a pair: focus, and take back the rename the first
      // one was about to start.
      _cancelPendingRename();
      widget.onFocusEntity?.call(entity);
      return;
    }

    // A click on a row that was *already* selected means rename — but
    // only once it is clear no second click is coming, or a double click
    // would rename and focus both. A row selected by making it, or from
    // the viewport, is selected without having been clicked, so it takes
    // a click of its own first.
    final plain =
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed;
    if (wasSelected && plain) {
      _cancelPendingRename();
      _renameAfterDoubleClick = Timer(_doubleClick, () {
        _renameAfterDoubleClick = null;
        if (mounted) _startRename(entity);
      });
      return;
    }
    _select(
      entity,
      tree,
      control: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
  }

  // ── Selecting ────────────────────────────────────────────────────────

  void _select(
    jge.Entity entity,
    SceneTree tree, {
    required bool control,
    required bool shift,
  }) {
    _keys.requestFocus();
    if (control) {
      _sceneState.toggleMultiSelect(entity);
      return;
    }
    if (shift) {
      final anchor = _sceneState.selectedEntity.value;
      if (anchor != null) {
        // Over what is on screen, which is what "between these two" means
        // to whoever is looking at it.
        final from = tree.indexOf(anchor.id);
        final to = tree.indexOf(entity.id);
        if (from >= 0 && to >= 0) {
          final lo = from < to ? from : to;
          final hi = from < to ? to : from;
          _sceneState.selectRange([
            for (var i = lo; i <= hi; i++) tree.rows[i].entity,
          ], anchor: anchor);
          return;
        }
      }
    }
    _sceneState
      ..clearMultiSelection()
      ..selectEntity(entity);
  }

  /// What a drag from [entity] carries: the selection when it is part of
  /// it, otherwise just itself.
  List<jge.Entity> _dragSelection(jge.Entity entity) {
    final selection = widget.entities.selectionEntities;
    return selection.any((e) => e.id == entity.id) ? selection : [entity];
  }

  // ── Dropping ─────────────────────────────────────────────────────────

  /// What a drop means, as one undoable step.
  ///
  /// Dropping *into* and dropping *between* are the same move with a
  /// different destination, so both go through one command: a drag that
  /// moved three things undoes as one drag.
  /// Whether [entity] is a HUD — a canvas, which lives in the world and
  /// is only the root of what the interface tree shows.
  bool _isCanvas(jge.Entity entity) =>
      entity.getComponent<jge.UiCanvasComponent>() != null;

  /// Whether these rows can be dragged at all.
  ///
  /// A HUD belongs to the world: where it sits among the world's entities
  /// is the world tree's business, and in here it is only ever the root
  /// of a screen's contents.
  bool _canDrag(List<jge.Entity> dragged) =>
      widget.contents != TreeContents.ui || !dragged.any(_isCanvas);

  /// Whether this row could take [dragged] at all, wherever on it the
  /// pointer happens to be.
  bool _canAccept(List<jge.Entity> dragged, jge.Entity onto) =>
      !dragged.any((e) => e.id == onto.id) && _canDrag(dragged);

  /// What a drop at [zone] on [onto] actually means.
  ///
  /// Beside a HUD would mean beside it in the world, which would take the
  /// interface out of every screen there is — so in the interface tree
  /// the edges of a HUD's row mean *into* it, which is the only thing
  /// they could sensibly mean.
  DropZone _zoneFor(jge.Entity onto, DropZone zone) =>
      widget.contents == TreeContents.ui && _isCanvas(onto)
      ? DropZone.onto
      : zone;

  /// Whether [dragged] may land on [onto] the way the pointer is over it.
  bool _canDrop(List<jge.Entity> dragged, jge.Entity onto, DropZone zone) =>
      _canAccept(dragged, onto) && _zoneFor(onto, zone) == zone;

  void _drop(List<jge.Entity> dragged, jge.Entity onto, DropZone zone) {
    if (!_canDrop(dragged, onto, zone)) return;
    if (zone == DropZone.onto) {
      widget.entities.reparentAll(dragged, onto);
      _tree.expand(onto.id);
      return;
    }

    final parentId = onto.getComponent<jge.ParentComponent>()?.parentId;
    final parent = parentId == null ? null : _world.getEntity(parentId);
    final siblings = parent == null
        ? _sceneState.rootOrder(_world)
        : parent.getComponent<jge.ChildrenComponent>()?.childIds ??
              const <jge.EntityId>[];
    // Nothing in the interface tree belongs at the world's top level.
    if (parent == null && widget.contents == TreeContents.ui) return;
    var at = siblings.indexOf(onto.id);
    if (at < 0) {
      widget.entities.reparentAll(dragged, parent);
      return;
    }
    if (zone == DropZone.below) at++;
    // Anything already above the line leaves a gap behind it when it
    // moves, so the line itself shifts up by that many.
    final above = dragged.where((e) {
      final index = siblings.indexOf(e.id);
      return index >= 0 && index < at;
    }).length;
    widget.entities.reparentAll(dragged, parent, index: at - above);
  }

  /// The swatches, and the way back to no mark at all.
  Future<void> _pickColor(
    BuildContext context,
    jge.Entity entity,
    Offset at,
  ) async {
    final chosen = await showEditorMenu<int>(context, at, [
      for (var i = 0; i < SceneTreeController.swatches.length; i++)
        editorMenuItem(i, _colorNames[i], icon: Icons.square_rounded),
      editorMenuDivider(),
      editorMenuItem(-1, 'No colour', icon: Icons.format_color_reset),
    ]);
    if (chosen == null) return;
    for (final e in _dragSelection(entity)) {
      _tree.setColor(e.id, chosen < 0 ? null : chosen);
    }
  }

  static const List<String> _colorNames = [
    'Red',
    'Orange',
    'Yellow',
    'Green',
    'Teal',
    'Blue',
    'Purple',
    'Grey',
  ];

  // ── The filter bar ───────────────────────────────────────────────────

  /// What is in the scene to filter by, gathered from the scene itself:
  /// the component types it actually uses, the tags and layers it
  /// actually has. A list of everything the editor *could* show would be
  /// longer and less use.
  Set<String> _componentTypes() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        for (final component in entity.components)
          component.runtimeType.toString(),
  };

  Set<String> _tags() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        if (entity.getComponent<jge.TagComponent>()?.tag case final tag?)
          if (tag.isNotEmpty) tag,
  };

  Set<String> _layers() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        if (entity.getComponent<jge.LayerComponent>()?.layerId case final id?)
          if (id.isNotEmpty) id,
  };

  Widget _filterChips(TreeFilter filter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _FilterChip(
            label: filter.componentType.isEmpty
                ? 'Component'
                : filter.componentType,
            on: filter.componentType.isNotEmpty,
            onPressed: (at) => _pickFilter(
              at,
              _componentTypes(),
              'Any component',
              (value) =>
                  _tree.filter.value = filter.copyWith(componentType: value),
            ),
          ),
          _FilterChip(
            label: filter.tag.isEmpty ? 'Tag' : filter.tag,
            on: filter.tag.isNotEmpty,
            onPressed: (at) => _pickFilter(
              at,
              _tags(),
              'Any tag',
              (value) => _tree.filter.value = filter.copyWith(tag: value),
            ),
          ),
          _FilterChip(
            label: filter.layer.isEmpty ? 'Layer' : filter.layer,
            on: filter.layer.isNotEmpty,
            onPressed: (at) => _pickFilter(
              at,
              _layers(),
              'Any layer',
              (value) => _tree.filter.value = filter.copyWith(layer: value),
            ),
          ),
          _FilterChip(
            label: 'Problems',
            on: filter.problems,
            onPressed: (_) => _tree.filter.value = filter.copyWith(
              problems: !filter.problems,
            ),
          ),
          if (!filter.isEmpty)
            _FilterChip(
              label: 'Clear',
              on: false,
              onPressed: (_) {
                _search.clear();
                _tree.filter.value = TreeFilter.none;
              },
            ),
        ],
      ),
    );
  }

  /// One of [options], or [anyLabel] for no filter at all.
  Future<void> _pickFilter(
    Offset at,
    Set<String> options,
    String anyLabel,
    void Function(String value) apply,
  ) async {
    final sorted = options.toList()..sort();
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('', anyLabel),
      if (sorted.isNotEmpty) editorMenuDivider(),
      for (final option in sorted) editorMenuItem(option, option),
    ]);
    if (chosen == null) return;
    apply(chosen);
  }

  // ── Renaming ─────────────────────────────────────────────────────────

  void _startRename(jge.Entity entity) {
    _tree.renameError.value = null;
    _tree.renaming.value = entity.id;
  }

  void _cancelRename() {
    _tree.renameError.value = null;
    _tree.renaming.value = null;
  }

  void _commitRename(jge.Entity entity, String name) {
    if (widget.entities.renameEntity(entity, name)) {
      _cancelRename();
      return;
    }
    // Left open, saying why: a name silently refused is a name the author
    // thinks they changed.
    _tree.renameError.value = name.trim().isEmpty
        ? 'It needs a name'
        : 'Something else is already called that';
  }

  // ── Keys ─────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_tree.renaming.value != null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final tree = _tree.rows;
    final selected = _sceneState.selectedEntity.value;
    final index = selected == null ? -1 : tree.indexOf(selected.id);
    final alt = HardwareKeyboard.instance.isAltPressed;
    final control = HardwareKeyboard.instance.isControlPressed;

    void moveTo(int at) {
      if (at < 0 || at >= tree.length) return;
      _sceneState
        ..clearMultiSelection()
        ..selectEntity(tree.rows[at].entity);
      _tree.scrollToIndex(at);
    }

    switch (key) {
      case LogicalKeyboardKey.arrowDown:
        if (alt && selected != null) {
          widget.entities.nudgeOrder(selected, up: false);
        } else {
          moveTo(index < 0 ? 0 : index + 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (alt && selected != null) {
          widget.entities.nudgeOrder(selected, up: true);
        } else {
          moveTo(index < 0 ? tree.length - 1 : index - 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (index < 0) return KeyEventResult.handled;
        final row = tree.rows[index];
        if (row.hasChildren && !row.isExpanded) {
          _tree.expand(row.id);
        } else if (row.hasChildren) {
          moveTo(index + 1);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (index < 0) return KeyEventResult.handled;
        final row = tree.rows[index];
        if (row.hasChildren && row.isExpanded) {
          _tree.collapse(row.id);
        } else {
          // Up to the parent, which is the row above at one less depth.
          for (var i = index - 1; i >= 0; i--) {
            if (tree.rows[i].depth < row.depth) {
              moveTo(i);
              break;
            }
          }
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        moveTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        moveTo(tree.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f2:
      case LogicalKeyboardKey.enter:
        if (selected != null) _startRename(selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.delete:
        widget.entities.deleteSelection(widget.scope.history);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _sceneState.clearSelection();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD when control:
        widget.entities.duplicateSelection(
          widget.scope.history,
          gridSize: _sceneState.gridSize.value,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG when control:
        if (HardwareKeyboard.instance.isShiftPressed) {
          if (selected != null) widget.entities.ungroup(selected);
        } else {
          widget.entities.groupSelection();
        }
        return KeyEventResult.handled;
    }

    // Anything else printable jumps to the next row starting with it.
    final character = event.character;
    if (!control &&
        character != null &&
        character.length == 1 &&
        character.trim().isNotEmpty) {
      final id = _tree.jumpTo(character, now: DateTime.now());
      if (id != null) moveTo(tree.indexOf(id));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Chrome ───────────────────────────────────────────────────────────

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
    child: Row(
      children: [
        Flexible(
          child: Text(
            widget.contents == TreeContents.ui ? 'INTERFACE' : 'SCENE TREE',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const Spacer(),
        if (widget.onToggleUiMode != null)
          _HeaderButton(
            icon: widget.uiModeOn ? Icons.public_off : Icons.phone_iphone,
            tooltip: widget.uiModeOn
                ? 'Back to the world'
                : 'Edit the interface',
            bright: widget.uiModeOn,
            onPressed: () => widget.onToggleUiMode!(!widget.uiModeOn),
          ),
        if (widget.onCreateUi != null)
          Builder(
            builder: (context) => _HeaderButton(
              icon: Icons.widgets_outlined,
              tooltip: 'Create UI',
              onPressed: () => _showCreateUiMenu(context),
            ),
          ),
        _HeaderButton(
          icon: Icons.folder_open_rounded,
          tooltip: 'Group the selection',
          onPressed: widget.entities.groupSelection,
        ),
        _HeaderButton(
          icon: Icons.add_rounded,
          tooltip: 'Create an entity',
          onPressed: widget.entities.createEntity,
        ),
      ],
    ),
  );

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
    child: SizedBox(
      height: 26,
      child: TextField(
        controller: _search,
        style: const TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search name or component',
          hintStyle: const TextStyle(
            color: EditorTheme.textMuted,
            fontSize: 11,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 14,
            color: EditorTheme.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 26),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          filled: true,
          fillColor: EditorTheme.inputBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: EditorTheme.border),
          ),
        ),
        onChanged: (text) =>
            _tree.filter.value = _tree.filter.value.copyWith(text: text),
      ),
    ),
  );

  Future<void> _showCreateUiMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final at = box == null
        ? Offset.zero
        : box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final items = <PopupMenuEntry<String>>[];
    var group = '';
    for (final option in UiCreateOptions.all) {
      if (option.group != group) {
        if (items.isNotEmpty) items.add(editorMenuDivider());
        items.add(editorMenuHeading<String>(option.group));
        group = option.group;
      }
      items.add(
        editorMenuItem<String>(option.id, option.label, icon: option.icon),
      );
    }
    final chosen = await showEditorMenu<String>(context, at, items);
    if (chosen != null) widget.onCreateUi?.call(chosen);
  }

  Future<void> _showMenu(
    BuildContext context,
    jge.Entity entity,
    Offset at,
  ) async {
    if (_sceneState.selectedEntity.value?.id != entity.id &&
        !_sceneState.isInMultiSelection(entity.id)) {
      _sceneState.selectEntity(entity);
    }
    final hasChildren =
        entity.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
        false;
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('rename', 'Rename', icon: Icons.edit_outlined),
      editorMenuItem('duplicate', 'Duplicate', icon: Icons.copy_outlined),
      editorMenuItem('delete', 'Delete', icon: Icons.delete_outline),
      editorMenuDivider(),
      editorMenuItem('copy', 'Copy', icon: Icons.content_copy_outlined),
      editorMenuItem('paste', 'Paste', icon: Icons.content_paste_outlined),
      editorMenuDivider(),
      editorMenuItem('group', 'Group', icon: Icons.folder_open_rounded),
      editorMenuItem(
        'ungroup',
        'Ungroup',
        icon: Icons.folder_off_outlined,
        enabled: hasChildren,
      ),
      editorMenuDivider(),
      editorMenuItem(
        'focus',
        'Focus in the viewport',
        icon: Icons.center_focus_strong_outlined,
      ),
      editorMenuItem(
        'expand',
        'Expand everything under it',
        icon: Icons.unfold_more,
        enabled: hasChildren,
      ),
      editorMenuDivider(),
      // Hiding everything else is the way to look at one thing in a busy
      // level; it is the editor's own view and changes nothing in the
      // game.
      if (widget.scope.view.hidden.value.isEmpty)
        editorMenuItem(
          'isolate',
          'Isolate: hide everything else',
          icon: Icons.visibility_outlined,
        )
      else
        editorMenuItem(
          'showAll',
          'Show everything again',
          icon: Icons.visibility,
        ),
      // What the modules have to say about this entity — the camera's
      // "make this the live one", a game's own verbs.
      if (widget.scope.sceneTreeActions.isNotEmpty) ...[
        editorMenuDivider(),
        for (final action in widget.scope.sceneTreeActions)
          editorMenuItem(
            'module:${action.id}',
            action.label,
            icon: action.icon,
            enabled: action.isEnabled?.call(entity, widget.scope) ?? true,
          ),
        editorMenuDivider(),
      ],
      editorMenuItem('color', 'Mark with a colour…', icon: Icons.palette),
      editorMenuItem('copyName', 'Copy its name', icon: Icons.abc),
    ]);

    switch (chosen) {
      case 'rename':
        _startRename(entity);
      case 'duplicate':
        widget.entities.duplicateSelection(
          widget.scope.history,
          gridSize: _sceneState.gridSize.value,
        );
      case 'delete':
        widget.entities.deleteSelection(widget.scope.history);
      case 'copy':
        widget.entities.copyEntity(entity);
      case 'paste':
        widget.entities.pasteEntity();
      case 'group':
        widget.entities.groupSelection();
      case 'ungroup':
        widget.entities.ungroup(entity);
      case 'focus':
        widget.onFocusEntity?.call(entity);
      case 'expand':
        _tree.expandSubtree(entity.id);
      case 'isolate':
        widget.scope.view.isolate(_world, [
          for (final e in _dragSelection(entity)) e.id,
        ]);
      case 'showAll':
        widget.scope.view.showAll();
      case 'color':
        // The menu that was open has gone; this one opens where it was.
        if (!context.mounted) return;
        await _pickColor(context, entity, at);
      case 'copyName':
        await Clipboard.setData(ClipboardData(text: entity.name ?? ''));
      default:
        if (chosen == null || !chosen.startsWith('module:')) return;
        final id = chosen.substring('module:'.length);
        for (final action in widget.scope.sceneTreeActions) {
          if (action.id == id) action.run(entity, widget.scope);
        }
    }
  }
}

/// A row that can be dragged, carrying whatever it should carry.
class _Draggable extends StatelessWidget {
  const _Draggable({
    required this.entity,
    required this.selection,
    required this.child,
    this.enabled = true,
    this.onEnded,
  });

  final jge.Entity entity;
  final List<jge.Entity> selection;
  final Widget child;

  /// False for a row that has nowhere it could be dropped: then there is
  /// no label under the pointer promising a move that cannot happen.
  final bool enabled;
  final VoidCallback? onEnded;

  /// How long a row must be held before it can be dragged. Shorter than
  /// a menu's long press: this is a mouse on a desktop, not a thumb.
  static const Duration _dragHold = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return LongPressDraggable<List<jge.Entity>>(
      data: selection,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // Hold to drag. A plain `Draggable` begins after one pixel of mouse
      // movement, which made every click a possible drag: the label
      // flashed up at the pointer like a tooltip, and a click that moved
      // slightly was thrown away as a drag instead of selecting. Pressing
      // and holding says "I mean to move this" and nothing else does.
      delay: _dragHold,
      hapticFeedbackOnStart: false,
      // Every way a drag can end, so nothing it drew is left behind.
      onDragEnd: (_) => onEnded?.call(),
      onDraggableCanceled: (_, _) => onEnded?.call(),
      onDragCompleted: onEnded,
      // Only ever seen while something is actually being dragged.
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: EditorTheme.selectionBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EditorTheme.primaryActive),
          ),
          child: Text(
            selection.length > 1
                ? '${selection.length} entities'
                : entity.name ?? 'Entity #${entity.id}',
            style: const TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.bright = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool bright;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 16,
      color: bright ? EditorTheme.primaryBright : EditorTheme.primary,
      splashRadius: 16,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    ),
  );
}

/// One filter in the bar under the search box.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onPressed,
  });

  final String label;
  final bool on;
  final void Function(Offset at) onPressed;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => InkWell(
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        onPressed(
          box == null
              ? Offset.zero
              : box.localToGlobal(box.size.bottomLeft(Offset.zero)),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: on ? EditorTheme.selectionBg : EditorTheme.inputBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? EditorTheme.primaryActive : EditorTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: on ? EditorTheme.textBright : EditorTheme.textMuted,
          ),
        ),
      ),
    ),
  );
}
