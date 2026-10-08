import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/constants/editor_constants.dart';
import '../../core/entity/hierarchy_commands.dart';
import '../../core/level_map/level_map_documents.dart';
import '../../core/level_map/tile_commands.dart';
import '../../core/scope/editor_scope.dart';
import '../level_designer/state/editor_commands.dart';
import '../widgets/editor_menu.dart';
import 'scene_tree_controller.dart';
import 'scene_tree_model.dart';
import 'scene_tree_row.dart';

/// A row of the scene tree that is part of a level map: one of its layers.
///
/// Clicking it picks it — the tree's selection moves from any entity to it
/// — and makes its layer the one painted; a second click renames it. The
/// painted layer's icon stays lit after the pick has moved on.
/// The eye and the padlock are the map's own, saved and undoable, and hide
/// and lock what is on the layer too. The menu renames the layer, or
/// deletes it with what is on it.
///
/// What is placed on a layer is listed under its row, as entities; an
/// entity dropped on the row goes on that layer. A layer row itself is
/// not dragged: the map's layers are arranged in the Layers panel.
class MapItemRow extends StatefulWidget {
  const MapItemRow({
    super.key,
    required this.row,
    required this.scope,
    required this.controller,
    this.onClaim,
    this.onDropEntities,
  });

  final TreeRow row;
  final EditorScope scope;
  final SceneTreeController controller;

  /// Told when a click lands on the row, so the list around it does not
  /// take it for a click on empty space.
  final VoidCallback? onClaim;

  /// Entities dropped on a layer row: they go on that layer of the map.
  final void Function(List<jge.Entity> entities, jge.Entity map, int layerId)?
  onDropEntities;

  @override
  State<MapItemRow> createState() => _MapItemRowState();
}

class _MapItemRowState extends State<MapItemRow> {
  bool _renaming = false;
  Duration? _clickedAt;

  /// How soon a second click must follow for a double-click.
  static const Duration _doubleClick = Duration(milliseconds: 500);

  EditorScope get scope => widget.scope;
  jge.Entity get map => widget.row.entity;

  @override
  Widget build(BuildContext context) {
    final target = scope.mapDocs.resolve(map);
    final item = widget.row.item!;
    final layer = target?.data.layerById(item.layerId);
    if (target == null || layer == null) return const SizedBox.shrink();
    return _layerRow(context, target, layer);
  }

  // ── Edits ────────────────────────────────────────────────────────────────

  void _layerEdit(
    LevelMapTarget target,
    int layerId,
    String label,
    void Function(jge.MapLayerData layer) change,
  ) {
    final command = MapStructureCommand.record(
      label: label,
      docs: scope.mapDocs,
      ref: target.ref,
      change: (m) {
        final layer = m.layerById(layerId);
        if (layer != null) change(layer);
      },
    );
    if (command != null) scope.history.pushApplied(command);
  }

  /// Whether this press is the second of a double-click.
  bool _isSecondClick(PointerDownEvent event) {
    final last = _clickedAt;
    _clickedAt = event.timeStamp;
    return last != null && event.timeStamp - last < _doubleClick;
  }

  // ── A layer ──────────────────────────────────────────────────────────────

  Widget _layerRow(
    BuildContext context,
    LevelMapTarget target,
    jge.MapLayerData layer,
  ) {
    final tiles = scope.tiles;
    final painted =
        tiles.mapEntityId.value == map.id && tiles.layerId.value == layer.id;
    final count = [
      for (final id
          in map.getComponent<jge.ChildrenComponent>()?.childIds ??
              const <jge.EntityId>[])
        if (scope.world
                .getEntity(id)
                ?.getComponent<jge.LayerComponent>()
                ?.mapLayer ==
            layer.id)
          id,
    ].length;
    final row = _frame(
      // Selected only while it is the tree's pick. Being painted is not
      // being selected: there always is a painted layer, and drawing it as
      // the selection left a row nothing could deselect.
      selected:
          painted && widget.controller.pickedLayer.value == (map.id, layer.id),
      lit: painted,
      onPressed: (event) {
        if (_isSecondClick(event)) {
          setState(() => _renaming = true);
          return;
        }
        // One selection in the tree: picking a layer lets go of the
        // entities. The layer being painted does not follow the entity
        // selection being emptied.
        scope.sceneState.clearSelection();
        tiles
          ..selectMap(map)
          ..layerId.value = layer.id;
        widget.controller.pickedLayer.value = (map.id, layer.id);
      },
      onMenu: (at) => _layerMenu(context, target, layer, at),
      expander: widget.row.hasChildren
          ? () => widget.controller.toggleLayer(map.id, layer.id)
          : null,
      icon: Icons.layers_outlined,
      name: layer.name,
      detail: count == 0 ? '' : '$count entit${count == 1 ? 'y' : 'ies'}',
      onRename: (name) => _layerEdit(
        target,
        layer.id,
        'Rename map layer',
        (l) => l.name = name,
      ),
      trailing: [
        SceneTreeRowButton(
          icon: layer.visible
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          tooltip: layer.visible ? 'Hide map layer' : 'Show map layer',
          faded: layer.visible,
          onPressed: () => _layerEdit(
            target,
            layer.id,
            layer.visible ? 'Hide map layer' : 'Show map layer',
            (l) => l.visible = !l.visible,
          ),
        ),
        SceneTreeRowButton(
          icon: layer.locked ? Icons.lock_outline : Icons.lock_open_outlined,
          tooltip: layer.locked ? 'Unlock map layer' : 'Lock map layer',
          faded: !layer.locked,
          onPressed: () => _layerEdit(
            target,
            layer.id,
            layer.locked ? 'Unlock map layer' : 'Lock map layer',
            (l) => l.locked = !l.locked,
          ),
        ),
      ],
    );
    final drop = widget.onDropEntities;
    if (drop == null || target.isReadOnly) return row;
    // Dropped here: onto this layer of the map — but never the map itself,
    // nor anything the map is under.
    return DragTarget<List<jge.Entity>>(
      onWillAcceptWithDetails: (details) =>
          details.data.isNotEmpty &&
          !details.data.any(
            (e) => isSelfOrDescendant(map, e, world: scope.world),
          ),
      onAcceptWithDetails: (details) => drop(details.data, map, layer.id),
      builder: (context, candidates, _) => candidates.isEmpty
          ? row
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: EditorTheme.primaryBright),
              ),
              child: row,
            ),
    );
  }

  Future<void> _layerMenu(
    BuildContext context,
    LevelMapTarget target,
    jge.MapLayerData layer,
    Offset at,
  ) async {
    final chosen = await showEditorMenu<String>(context, at, [
      editorMenuItem('rename', 'Rename', icon: Icons.edit_outlined),
      editorMenuItem(
        'delete',
        'Delete the layer, and what is on it',
        icon: Icons.delete_outline,
      ),
    ]);
    switch (chosen) {
      case 'rename':
        setState(() => _renaming = true);
      case 'delete':
        _deleteLayer(target, layer);
    }
  }

  /// [layer], and what is on it, gone — one step.
  void _deleteLayer(LevelMapTarget target, jge.MapLayerData layer) {
    const label = 'Delete map layer';
    final world = scope.world;
    final members = [
      for (final id
          in map.getComponent<jge.ChildrenComponent>()?.childIds ??
              const <jge.EntityId>[])
        if (world.getEntity(id) case final e?
            when e.getComponent<jge.LayerComponent>()?.mapLayer == layer.id)
          e,
    ];
    final delete = members.isEmpty
        ? null
        : (DeleteEntitiesCommand(
            label: label,
            world: world,
            sceneState: scope.sceneState,
            entities: members,
            codec: scope.codec,
          )..redo());
    final structure = MapStructureCommand.record(
      label: label,
      docs: scope.mapDocs,
      ref: target.ref,
      change: (m) => m.layers.removeWhere((l) => l.id == layer.id),
    );
    final steps = [?delete, ?structure];
    if (steps.isEmpty) return;
    scope.history.pushApplied(
      steps.length == 1
          ? steps.single
          : CompositeCommand(label: label, commands: steps),
    );
  }

  Widget _frame({
    required bool selected,
    bool lit = false,
    required void Function(PointerDownEvent event) onPressed,
    required void Function(Offset globalPosition) onMenu,
    required IconData icon,
    required String name,
    required void Function(String name) onRename,
    required List<Widget> trailing,
    String detail = '',
    VoidCallback? expander,
  }) {
    final row = widget.row;
    // As an entity row's content is placed: past the column of ticks.
    final indent = 4 + row.depth * 12.0;
    return Listener(
      onPointerDown: (event) {
        widget.onClaim?.call();
        if (event.buttons & kPrimaryButton == 0 || _renaming) return;
        onPressed(event);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) => onMenu(details.globalPosition),
        child: Container(
          height: kSceneTreeRowTileHeight,
          color: selected ? EditorTheme.selectionBg : Colors.transparent,
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              SizedBox(width: kSceneTreeRowTileHeight),
              SizedBox(width: indent),
              if (expander != null)
                Semantics(
                  button: true,
                  label: row.isExpanded ? 'Collapse' : 'Expand',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: expander,
                    child: SizedBox(
                      width: kSceneTreeRowTileHeight,
                      height: kSceneTreeRowTileHeight,
                      child: Icon(
                        row.isExpanded
                            ? Icons.expand_more_rounded
                            : Icons.chevron_right_rounded,
                        size: 14,
                        color: EditorTheme.primary,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(width: kSceneTreeRowTileHeight),
              const SizedBox(width: 2),
              Icon(
                icon,
                size: 13,
                color: selected || lit
                    ? EditorTheme.primaryBright
                    : EditorTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _renaming
                    ? _RenameField(
                        initial: name,
                        onDone: (text) {
                          setState(() => _renaming = false);
                          final trimmed = text?.trim();
                          if (trimmed != null &&
                              trimmed.isNotEmpty &&
                              trimmed != name) {
                            onRename(trimmed);
                          }
                        },
                      )
                    : Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: !row.isMatch
                                    ? EditorTheme.textMuted
                                    : selected
                                    ? EditorTheme.textBright
                                    : EditorTheme.textSecondary,
                              ),
                            ),
                          ),
                          if (detail.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                detail,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: EditorTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Typing a new name in place: Enter keeps it, Escape or a click away
/// without a change leaves the old one.
class _RenameField extends StatefulWidget {
  const _RenameField({required this.initial, required this.onDone});

  final String initial;

  /// The new name, or null to keep the old one.
  final void Function(String? text) onDone;

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial)
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.initial.length,
        );
  bool _done = false;

  /// Leaving the field — Tab, as well as a click elsewhere — keeps the
  /// name, as Enter does.
  late final FocusNode _focus = FocusNode()
    ..addListener(() {
      if (!_focus.hasFocus) _finish(_text.text);
    });

  void _finish(String? text) {
    if (_done) return;
    _done = true;
    widget.onDone(text);
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
    },
    child: TextField(
      controller: _text,
      focusNode: _focus,
      autofocus: true,
      style: TextStyle(fontSize: 11, color: EditorTheme.textPrimary),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      onSubmitted: _finish,
      onTapOutside: (_) => _finish(_text.text),
    ),
  );
}
