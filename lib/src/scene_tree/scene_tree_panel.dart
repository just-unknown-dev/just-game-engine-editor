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

import 'package:just_editor_core/host.dart';
import '../entities/entity_ops.dart';
import 'map_item_row.dart';
import 'scene_tree_controller.dart';
import '../level_map/scope_level_maps.dart';
import '../problems/problem_scan.dart';

part 'scene_tree_rows.dart';
part 'scene_tree_drag_drop.dart';
part 'scene_tree_filter.dart';
part 'scene_tree_keys.dart';

/// The scene tree: every entity of the scene as a row, to select,
/// rename, drag into another and filter.
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

  /// Whether the tree has the keyboard, so the selected row can say the
  /// arrows are about to act on it.
  bool _hasKeys = false;

  /// The row a drag is over, and where on it. Only meaningful while a
  /// drag is over the list: a drag let go of outside the list leaves no
  /// `onLeave` behind it, and the line it drew used to stay on screen
  /// afterwards, where it read as an underline on a perfectly ordinary row.
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
  late final EditorHistory _history = widget.scope.history;

  jge.World get _world => widget.scope.world;

  @override
  void initState() {
    super.initState();
    // The tree follows the selection, wherever it was made.
    _sceneState.selectedEntity.addListener(_onSelectionChanged);
    _sceneState.revision.addListener(_onRevision);
    // An undo step pushed, undone or redone: what the rows show may have
    // changed, and it is looked at once.
    _history.revision.addListener(_checkShape);
    // What the first build shows, so the first move is not taken for a
    // change of shape.
    _shapeSeen = _shapeOf();
    _entitiesSeen = _world.queryVersion(const []);
  }

  @override
  void dispose() {
    _sceneState.selectedEntity.removeListener(_onSelectionChanged);
    _sceneState.revision.removeListener(_onRevision);
    _history.revision.removeListener(_checkShape);
    _shapeCooling?.cancel();
    _chipsCooling?.cancel();
    _problemsLater?.cancel();
    _rowsLater?.cancel();
    _chipsTick.dispose();
    _rowsTick.dispose();
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

  // ── Keeping the filter chips current, cheaply ────────────────────────

  /// Bumped when the chips should be gathered again. Gathering walks every
  /// component in the scene, and a gizmo drag bumps the scene's revision
  /// on every move: so the first change after a still moment is answered
  /// at once, and the rest at most every [_chipsEvery] while they keep
  /// coming.
  final Signal<int> _chipsTick = Signal(0, debugLabel: 'treeChips');

  /// Running while the chips were gathered less than [_chipsEvery] ago.
  Timer? _chipsCooling;

  /// Whether the scene changed while [_chipsCooling] ran.
  bool _chipsOwed = false;

  /// How many problems the scene has, for the Problems chip; null to count
  /// again. Counting runs every check there is, so it waits until the
  /// scene has been still for [_problemsQuiet].
  int? _problemCount;
  EditorScene? _problemsScene;
  Timer? _problemsLater;

  static const Duration _chipsEvery = Duration(milliseconds: 500);
  // A little longer than the problem scan waits between scans of a scene
  // being edited, so what is read once it is still is a fresh scan.
  static Duration get _problemsQuiet =>
      ProblemScan.editEvery + const Duration(milliseconds: 100);

  // ── Building the rows only when what they show changed ────────────────

  /// Bumped when the rows should be built again: at once when what they
  /// show changes — which entities there are, their names, nesting, Enabled
  /// flags, kinds, layers and tags, the roots' order — and once more when
  /// the scene has been still for [_problemsQuiet], for what a row shows
  /// from the values (a problem's mark). A gizmo drag bumps the scene's
  /// revision on every move and changes none of that, so the rows are not
  /// built again while it lasts.
  final Signal<int> _rowsTick = Signal(0, debugLabel: 'treeRows');
  int? _shapeSeen;
  Timer? _rowsLater;

  /// Working the shape out walks every entity, and a gizmo drag bumps the
  /// scene's revision on every move without changing it: so it is worked
  /// out at once after a still moment, after an undo step and when
  /// entities came or went ([_entitiesSeen]), and otherwise at most every
  /// [_shapeEvery] while revisions keep coming.
  Timer? _shapeCooling;
  bool _shapeOwed = false;
  int? _entitiesSeen;

  static const Duration _shapeEvery = Duration(milliseconds: 250);

  void _onRevision() {
    _followRows();
    _problemsLater?.cancel();
    _problemsLater = Timer(_problemsQuiet, () {
      _problemsLater = null;
      if (!mounted) return;
      // The scan due once the scene is still runs here, between frames:
      // the rows and the chips built after only read it.
      ProblemScan.of(widget.scope).problems;
      _problemCount = null;
      _gatherChips();
    });
  }

  /// The chips gathered again soon: at once after a still moment, then at
  /// most every [_chipsEvery].
  void _chipsSoon() {
    if (_chipsCooling != null) {
      _chipsOwed = true;
      return;
    }
    _gatherChips();
  }

  void _onSelectionChanged() {
    final selected = _sceneState.selectedEntity.value;
    // A rename armed by a click on the row selected then is for that row
    // only: the selection gone elsewhere — clicked, or from the viewport —
    // takes it back.
    if (selected?.id != _renamePendingFor) _cancelPendingRename();
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
          signals: [_tree.filter, _chipsTick, _sceneState.activeScene],
          builder: (context, _) => _filterChips(_tree.filter.value),
        ),
        Expanded(
          child: SignalConsumer(
            signals: [
              _sceneState.activeScene,
              _sceneState.selectedEntity,
              _sceneState.multiSelectedIds,
              _rowsTick,
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
          ? ProblemScan.of(widget.scope).entitiesWithProblems.toSet()
          : const {},
    );
    _tree.rows = tree;

    // What is on each layer of a map, counted once for all its layer rows.
    final onLayers = <jge.EntityId, Map<int, int>>{};
    Map<int, int> countsOn(jge.Entity map) => onLayers.putIfAbsent(map.id, () {
      final counts = <int, int>{};
      for (final id
          in map.getComponent<jge.ChildrenComponent>()?.childIds ??
              const <jge.EntityId>[]) {
        final layer = _world
            .getEntity(id)
            ?.getComponent<jge.LayerComponent>()
            ?.mapLayer;
        if (layer != null) counts[layer] = (counts[layer] ?? 0) + 1;
      }
      return counts;
    });

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
          child: _rowList(tree, countsOn),
        ),
      ),
    );
  }

  Widget _row(
    SceneTree tree,
    int index,
    Map<int, int> Function(jge.Entity map) countsOn,
  ) {
    final row = tree.rows[index];
    if (row.isMapItem) {
      return MapItemRow(
        key: ValueKey(('mapItem', row.id, row.item)),
        row: row,
        memberCount: countsOn(row.entity)[row.item!.layerId] ?? 0,
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

  /// A rename waiting to see whether a second click is coming, and whose.
  Timer? _renameAfterDoubleClick;
  jge.EntityId? _renamePendingFor;

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
  /// Ctrl+S and the rest still reach the editor. Ctrl is Cmd on macOS,
  /// where Backspace deletes as Delete does.
  static bool _claims(KeyEvent event) {
    if (EditorKeys.primaryPressed) {
      return event.logicalKey == LogicalKeyboardKey.keyD ||
          event.logicalKey == LogicalKeyboardKey.keyG;
    }
    if (_treeKeys.contains(event.logicalKey) ||
        EditorKeys.isDeleteKey(event.logicalKey)) {
      return true;
    }
    // A letter jumps to the next row starting with it.
    final character = event.character;
    return character != null &&
        character.length == 1 &&
        character.trim().isNotEmpty;
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
              _rowsTick,
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
        // A group only: ungrouping destroys the entity that holds them.
        enabled: widget.entities.isGroup(entity),
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
