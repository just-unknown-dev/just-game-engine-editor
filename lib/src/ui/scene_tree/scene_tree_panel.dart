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
import '../../core/theme/editor_metrics.dart';
import '../kit/kit.dart';
import '../../core/entity/entity_ops.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/state/editor_scene_state.dart';
import '../overlay/docks/extra/extra_docks.dart';
import '../../core/entity/hierarchy_commands.dart';
import '../inspector/field_style.dart';
import '../widgets/editor_menu.dart';
import 'map_item_row.dart';
import 'scene_tree_controller.dart';
import 'scene_tree_model.dart';
import 'scene_tree_row.dart';
import '../widgets/editor_scrollbar.dart';

class SceneTreePanel extends StatefulWidget {
  const SceneTreePanel({
    super.key,
    required this.scope,
    required this.entities,
    this.controller,
    this.authored,
    this.onFocusEntity,
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
  /// Whether the tree has the keyboard, so the selected row can say the
  /// arrows are about to act on it.
  bool _hasKeys = false;

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
    // An entity selected, anywhere, takes the tree's selection off a map
    // layer row.
    _tree.pickedLayer.value = null;
    _tree.reveal(selected.id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        _searchField(),
        SignalConsumer(
          signals: [_sceneState.selectable],
          builder: (context, _) => _reachNote(),
        ),
        // Its own builder: the chips say what is being filtered by and
        // what this scene can be filtered *on*, so they follow both the
        // filter and the scene.
        SignalConsumer(
          signals: [
            _tree.filter,
            _sceneState.revision,
            _sceneState.activeScene,
          ],
          builder: (context, _) => _filterChips(_tree.filter.value),
        ),
        Expanded(
          child: SignalConsumer(
            signals: [
              _sceneState.activeScene,
              _sceneState.selectedEntity,
              _sceneState.multiSelectedIds,
              _sceneState.revision,
              _sceneState.selectable,
              widget.scope.view.pinned,
              widget.scope.mapDocs.revision,
              widget.scope.tiles.layerId,
              widget.scope.tiles.mapEntityId,
              _tree.expanded,
              _tree.expandedLayers,
              _tree.pickedLayer,
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
      // A level map's layers and shapes, under it.
      mapOf: (entity) => entity.hasComponent<jge.LevelMapComponent>()
          ? widget.scope.mapDocs.resolve(entity)?.data
          : null,
      expandedLayers: _tree.expandedLayers.value,
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
      final filtered = !_tree.filter.value.isEmpty;
      return EditorEmptyState(
        icon: filtered
            ? Icons.filter_alt_off_outlined
            : Icons.category_outlined,
        title: filtered ? 'Nothing matches' : 'Nothing in the scene yet',
        hint: filtered
            ? 'Clear the search or the filters to see everything again.'
            : 'Make the first entity here, or drag an image in from Assets.',
        actionLabel: filtered ? 'Clear' : 'Create an entity',
        actionIcon: filtered ? Icons.clear_rounded : Icons.add_rounded,
        onAction: filtered
            ? () {
                _search.clear();
                _tree.filter.value = TreeFilter.none;
              }
            : widget.entities.createEntity,
      );
    }

    return EditorKeyClaim(
      claims: _claims,
      child: Focus(
        focusNode: _keys,
        onFocusChange: (has) => setState(() => _hasKeys = has),
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
            if ((event.position - _emptyPressedAt).distance > kTouchSlop) {
              return;
            }
            _keys.requestFocus();
            if (_tree.renaming.value != null) return;
            _tree.pickedLayer.value = null;
            _sceneState.clearSelection();
          },
          child: _rowList(tree),
        ),
      ),
    );
  }

  Widget _rowList(SceneTree tree) {
    return DragTarget<List<jge.Entity>>(
      // Dropped past the last row: out of everything, to the top level —
      // but not while the Level Designer keeps to its Level Map: the top
      // level is outside it.
      onWillAcceptWithDetails: (_) => _reaches(null),
      onAcceptWithDetails: (details) {
        if (_dragOver != null) return;
        widget.entities.reparentAll(details.data, null);
      },
      builder: (context, candidates, _) => Stack(
        children: [
          Positioned.fill(
            child: EditorScrollbar(
              controller: _tree.scroll,
              builder: (_, _) => ListView.builder(
                key: _listKey,
                controller: _tree.scroll,
                padding: EdgeInsets.zero,
                itemCount: tree.length,
                itemExtent: kSceneTreeRowTileHeight,
                itemBuilder: (context, index) => _row(tree, index),
              ),
            ),
          ),
          // A drag let go of below the last row moves to the top level.
          // It always did; nothing said so, and nothing showed it was
          // about to happen.
          if (candidates.isNotEmpty && _dragOver == null)
            Positioned(
              left: 0,
              right: 0,
              top: tree.length * kSceneTreeRowTileHeight,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.topCenter,
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: EditorTheme.dragOverBg,
                    border: Border.all(color: EditorTheme.primaryBright),
                  ),
                  child: Text(
                    'Move to the top level',
                    style: TextStyle(
                      color: EditorTheme.primaryBright,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(SceneTree tree, int index) {
    final row = tree.rows[index];
    if (row.isMapItem) {
      return MapItemRow(
        key: ValueKey(('mapItem', row.id, row.item)),
        row: row,
        scope: widget.scope,
        controller: _tree,
        onClaim: () => _rowTookIt = true,
        onDropEntities: (dragged, map, layerId) {
          widget.entities.reparentAll(dragged, map, mapLayer: layerId);
          _tree.expandLayer(map.id, layerId);
        },
      );
    }
    final entity = row.entity;
    final selected = _sceneState.selectedEntity.value?.id == entity.id;
    final reachable = _sceneState.canSelect(entity);

    SceneTreeRowTile tileFor(DropZone? zone) => SceneTreeRowTile(
      row: row,
      isDisabled: !reachable,
      isSelected: selected,
      isMultiSelected: _sceneState.isInMultiSelection(entity.id),
      icon: widget.scope.iconFor(entity),
      color: _tree.colorOf(entity.id),
      hasKeyboardFocus: _hasKeys,
      onToggleEnabled: () => widget.scope.history.push(
        SetEnabledCommand(
          sceneState: _sceneState,
          entity: entity,
          enabled: !entity.isActive,
        ),
      ),
      onPickColor: (at) => _pickColor(context, entity, at),
      onControlDown: () => _controlDown = true,
      onToggleHidden: widget.onToggleHidden == null
          ? null
          : () => widget.onToggleHidden!(entity),
      onShowMenu: (at) => _showMenu(context, entity, at),
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
      isPinned: widget.scope.view.isPinned(entity.id),
      onTogglePinned: () => widget.scope.view.togglePinned(entity.id),
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
      enabled: reachable,
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
          // A press on the tick, the mark, the eye, the padlock or the
          // menu is about that control. The row hears it too, being
          // above them, and used to select the entity on the way past.
          if (_controlDown) {
            _controlDown = false;
            _pressedOn = null;
            _rowTookIt = true;
            return;
          }
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
          onSecondaryTapUp: reachable
              ? (details) => _showMenu(context, entity, details.globalPosition)
              : null,
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

  /// Set by a row's own control as the pointer goes down on it.
  bool _controlDown = false;

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
    // Out of reach: not selected, renamed or focused. Nor is the click
    // one on empty space — the selection stays as it was.
    if (!_sceneState.canSelect(entity)) return;
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
  /// Whether this row could take [dragged] at all, wherever on it the
  /// pointer happens to be.
  bool _canAccept(List<jge.Entity> dragged, jge.Entity onto) =>
      !dragged.any((e) => e.id == onto.id) && _sceneState.canSelect(onto);

  /// What a drop at [zone] on [onto] actually means.
  ///
  /// Beside something whose parent is out of reach would take what is
  /// dropped out of reach too — beside the Level Map, while designing, is
  /// the top level, outside it — so there the edges mean into it.
  DropZone _zoneFor(jge.Entity onto, DropZone zone) {
    if (zone != DropZone.onto && !_reaches(_parentOf(onto))) {
      return DropZone.onto;
    }
    return zone;
  }

  jge.Entity? _parentOf(jge.Entity entity) {
    final id = entity.getComponent<jge.ParentComponent>()?.parentId;
    return id == null ? null : _world.getEntity(id);
  }

  /// Whether what is put under [parent] — or at the top level, for none —
  /// is still within reach.
  bool _reaches(jge.Entity? parent) => parent == null
      ? _sceneState.selectable.value == null
      : _sceneState.canSelect(parent);

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
    // Beside something on a map layer is on that layer too.
    final mapLayer = parent?.hasComponent<jge.LevelMapComponent>() ?? false
        ? onto.getComponent<jge.LayerComponent>()?.mapLayer
        : null;
    var at = siblings.indexOf(onto.id);
    if (at < 0) {
      widget.entities.reparentAll(dragged, parent, mapLayer: mapLayer);
      return;
    }
    if (zone == DropZone.below) at++;
    // Anything already above the line leaves a gap behind it when it
    // moves, so the line itself shifts up by that many.
    final above = dragged.where((e) {
      final index = siblings.indexOf(e.id);
      return index >= 0 && index < at;
    }).length;
    widget.entities.reparentAll(
      dragged,
      parent,
      index: at - above,
      mapLayer: mapLayer,
    );
  }

  /// The swatches, and the way back to no mark at all.
  Future<void> _pickColor(
    BuildContext context,
    jge.Entity entity,
    Offset at,
  ) async {
    final chosen = await showEditorMenu<int>(context, at, [
      for (var i = 0; i < SceneTreeController.swatches.length; i++)
        editorMenuItem(
          i,
          _colorNames[i],
          icon: Icons.square_rounded,
          iconColor: SceneTreeController.swatches[i],
        ),
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

  /// `12 entities`, or what is picked when more than one thing is.
  ///
  /// Counted from the world rather than from the rows, which are a frame
  /// behind at this point in the build — except under a filter, where
  /// what is shown is the interesting number.
  String _countLabel() {
    final picked = _sceneState.multiSelectedIds.value.length;
    if (picked > 1) return '$picked selected';
    final count = _tree.filter.value.isEmpty
        ? _world.entities.where((e) => e.isAlive).length
        : _tree.rows.length;
    return count == 1 ? '1 entity' : '$count entities';
  }

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

  Set<String> _tags() => _world.tagsInUse;

  Set<String> _layers() => {
    for (final entity in _world.entities)
      if (entity.isAlive)
        if (entity.getComponent<jge.LayerComponent>()?.layerId case final id?)
          if (id.isNotEmpty) id,
  };

  Widget _filterChips(TreeFilter filter) {
    // Only what this scene can answer: a Tag chip over a scene with no
    // tags opens an empty menu and takes a row up saying nothing.
    final tags = _tags();
    final layers = _layers();
    final problemCount = ProblemScan.of(widget.scope).problems.length;
    final chips = <Widget>[
      _FilterChip(
        label: filter.componentType.isEmpty
            ? 'Component'
            : filter.componentType,
        on: filter.componentType.isNotEmpty,
        count: filter.componentType.isEmpty ? _componentTypes().length : null,
        onPressed: (at) => _pickFilter(
          at,
          _componentTypes(),
          'Any component',
          (value) => _tree.filter.value = filter.copyWith(componentType: value),
        ),
      ),
      if (tags.isNotEmpty || filter.wantedTags.isNotEmpty)
        _FilterChip(
          label: switch (filter.wantedTags.toList()) {
            [] => 'Tag',
            [final only] => '#$only',
            [final first, ...final rest] => '#$first +${rest.length}',
          },
          on: filter.wantedTags.isNotEmpty,
          count: filter.wantedTags.isEmpty ? tags.length : null,
          onPressed: (at) => _pickTags(at, tags, filter),
        ),
      if (layers.isNotEmpty || filter.layer.isNotEmpty)
        _FilterChip(
          label: filter.layer.isEmpty ? 'Layer' : filter.layer,
          on: filter.layer.isNotEmpty,
          count: filter.layer.isEmpty ? layers.length : null,
          onPressed: (at) => _pickFilter(
            at,
            layers,
            'Any layer',
            (value) => _tree.filter.value = filter.copyWith(layer: value),
          ),
        ),
      if (problemCount > 0 || filter.problems)
        _FilterChip(
          label: 'Problems',
          on: filter.problems,
          count: problemCount,
          isMenu: false,
          onPressed: (_) =>
              _tree.filter.value = filter.copyWith(problems: !filter.problems),
        ),
      if (!filter.isEmpty)
        _FilterChip(
          label: 'Clear',
          on: false,
          isMenu: false,
          onPressed: (_) {
            _search.clear();
            _tree.filter.value = TreeFilter.none;
          },
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Wrap(spacing: 4, runSpacing: 4, children: chips),
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

  /// Tags to narrow the tree to — any of several, each ticked on or off.
  Future<void> _pickTags(
    Offset at,
    Set<String> inScene,
    TreeFilter filter,
  ) async {
    final wanted = filter.wantedTags;
    final sorted = {...inScene, ...wanted}.toList()..sort();
    final tags = widget.scope.tags;
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('', 'Any tag', iconSlot: true),
      if (sorted.isNotEmpty) editorMenuDivider(),
      for (final tag in sorted)
        editorMenuItem(
          tag,
          tag,
          icon: wanted.contains(tag) ? Icons.check_rounded : Icons.circle,
          iconColor: wanted.contains(tag) ? null : tags.colorOf(tag),
        ),
    ]);
    if (chosen == null) return;
    _tree.filter.value = filter.copyWith(
      tag: '',
      tags: chosen.isEmpty
          ? const {}
          : wanted.contains(chosen)
          ? (wanted..remove(chosen))
          : {...wanted, chosen},
    );
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

  static final Set<LogicalKeyboardKey> _treeKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.escape,
  };

  /// The keys [_onKey] acts on, kept from the editor's shortcuts while the
  /// tree has the focus: the editor hears every key first, so Ctrl+D would
  /// otherwise duplicate twice, F2 open the docks as well as rename, and the
  /// arrows nudge the selection in the level as well as walk the tree.
  /// Ctrl+S and the rest still reach the editor.
  static bool _claims(KeyEvent event) {
    if (HardwareKeyboard.instance.isControlPressed) {
      return event.logicalKey == LogicalKeyboardKey.keyD ||
          event.logicalKey == LogicalKeyboardKey.keyG;
    }
    if (_treeKeys.contains(event.logicalKey)) return true;
    // A letter jumps to the next row starting with it.
    final character = event.character;
    return character != null &&
        character.length == 1 &&
        character.trim().isNotEmpty;
  }

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
      // Past a level map's layer rows and what is out of reach: the
      // keys walk the entities that can be selected.
      final step = at > index ? 1 : -1;
      while (at >= 0 &&
          at < tree.length &&
          (tree.rows[at].isMapItem ||
              !_sceneState.canSelect(tree.rows[at].entity))) {
        at += step;
      }
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
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
    child: Row(
      children: [
        // The title gives way first: the buttons and the count are the
        // parts worth keeping whole in a narrow panel.
        Expanded(
          child: Text(
            'SCENE TREE',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        // What is in the scene, or what is picked out of it — the
        // question the tree is most often asked, and it had no answer.
        const SizedBox(width: 4),
        // Its own builder, or it says what was true when the panel was
        // last rebuilt for some other reason. Flexible so that a narrow
        // panel shortens it instead of overflowing the row.
        Flexible(
          flex: 0,
          child: SignalConsumer(
            signals: [
              _sceneState.revision,
              _sceneState.multiSelectedIds,
              _sceneState.activeScene,
              _tree.filter,
            ],
            builder: (context, _) => Text(
              _countLabel(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 9),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Making a thing and gathering things are different jobs; they
        // used to sit in one undifferentiated cluster.
        Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          color: EditorTheme.border,
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
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
    child: SizedBox(
      height: InspectorField.height,
      child: TextField(
        controller: _search,
        style: TextStyle(
          color: EditorTheme.textPrimary,
          fontSize: InspectorField.fontSize,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search name or component',
          hintStyle: TextStyle(
            color: EditorTheme.textMuted,
            fontSize: InspectorField.fontSize,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 14,
            color: EditorTheme.textMuted,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 28),
          contentPadding: InspectorField.padding,
          filled: true,
          fillColor: InspectorField.fill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: EditorTheme.border),
          ),
        ),
        onChanged: (text) =>
            _tree.filter.value = _tree.filter.value.copyWith(text: text),
      ),
    ),
  );

  /// Why most of the tree has gone faint: the Level Designer is open and
  /// only its Level Map can be worked on. Nothing when all of it can.
  Widget _reachNote() {
    if (_sceneState.selectable.value == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Row(
        children: [
          Icon(Icons.grid_on_rounded, size: 12, color: EditorTheme.textMuted),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Level Designer open: only the Level Map can be edited',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    );
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
      if (widget.isLocked != null && widget.onToggleLocked != null)
        editorMenuItem(
          'pickLock',
          widget.isLocked!(entity)
              ? 'Let it be picked again'
              : 'Lock against picking',
          icon: widget.isLocked!(entity)
              ? Icons.lock_open_outlined
              : Icons.lock_outline,
        ),
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
      case 'pickLock':
        for (final e in _dragSelection(entity)) {
          widget.onToggleLocked?.call(e);
        }
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
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }
}

/// A button in the tree's header: the kit's, in the accent.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => EditorIconButton(
    icon: icon,
    tooltip: tooltip,
    color: EditorTheme.primary,
    iconSize: 16,
    onTap: onPressed,
  );
}

/// One filter in the bar under the search box.
///
/// A toggle, not a field: no fill of its own until it is on, so it does
/// not read as another input two rows under the search box.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.on,
    required this.onPressed,
    this.count,
    this.isMenu = true,
  });

  final String label;
  final bool on;
  final void Function(Offset at) onPressed;

  /// How many things there are to pick from, or how many problems there
  /// are — shown so the chip says whether it is worth opening.
  final int? count;

  /// Menus carry a chevron; a plain toggle does not.
  final bool isMenu;

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
      borderRadius: BorderRadius.circular(EditorMetrics.radiusPill),
      child: Container(
        constraints: BoxConstraints(minHeight: EditorMetrics.minTarget),
        padding: const EdgeInsets.fromLTRB(9, 2, 5, 2),
        decoration: BoxDecoration(
          color: on
              ? EditorTheme.primaryBright.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(EditorMetrics.radiusPill),
          border: Border.all(
            color: on
                ? EditorTheme.primaryBright.withValues(alpha: 0.6)
                : EditorTheme.borderStrong.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: on ? EditorTheme.textBright : EditorTheme.textSecondary,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(fontSize: 9, color: EditorTheme.textMuted),
              ),
            ],
            SizedBox(width: isMenu ? 0 : 4),
            if (isMenu)
              Icon(
                Icons.arrow_drop_down,
                size: 13,
                color: EditorTheme.textMuted,
              ),
          ],
        ),
      ),
    ),
  );
}
