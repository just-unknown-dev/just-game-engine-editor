import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/level_map/level_map_documents.dart';
import '../../../core/level_map/tile_commands.dart';
import '../../inspector/field_rows.dart';
import '../../inspector/field_style.dart';
import '../../widgets/editor_scrollbar.dart';
import '../../widgets/scrubbable_number_field.dart';
import '../controls/designer_controls.dart';
import '../level_designer_session.dart';
import '../state/editor_commands.dart';

/// Makes the scene's Level Map, empty, and selects it to paint — or, when
/// the scene has one, selects that. One undo step.
void createLevelMap(LevelDesignerSession session) {
  final scope = session.scope;
  final existing = jge.LevelMaps.primaryEntity(session.world);
  if (existing != null) {
    scope.tiles.selectMap(existing);
    session.sceneState.selectEntity(existing);
    return;
  }
  final provision = scope.mapProvision;
  final made = provision.ensure(session.world)?.entity;
  provision.keep('Create Level Map');
  if (made != null) session.sceneState.selectEntity(made);
}

/// The level's layers in one list, grouped by the depth they draw at, front
/// first — Foreground, Main, Background, and any other a scene uses.
///
/// Under each depth: the Level Map's layers that draw there, and a row for
/// the entities placed there. A map layer's eye, lock and collision are
/// saved with the map; the entities' eye and lock are the editor's only —
/// hiding them must never change what the level does. Every change to the
/// map, and every move of entities to a depth, is one undo step.
class LevelLayersPanel extends StatefulWidget {
  const LevelLayersPanel({super.key, required this.session});

  final LevelDesignerSession session;

  @override
  State<LevelLayersPanel> createState() => _LevelLayersPanelState();
}

class _LevelLayersPanelState extends State<LevelLayersPanel> {
  /// The map layer whose settings are open, by id.
  int? _open;
  bool _mapSettings = false;

  LevelDesignerSession get session => widget.session;

  @override
  Widget build(BuildContext context) {
    final tiles = session.scope.tiles;
    final controller = session.controller;
    return SignalBuilder3<int, int?, int?>(
      signal1: session.scope.mapDocs.revision,
      signal2: tiles.mapEntityId,
      signal3: tiles.layerId,
      builder: (context, _, _, _, _) => SignalBuilder2<int, String?>(
        // Maps and entities come and go with the scene.
        signal1: session.sceneState.revision,
        signal2: session.scope.activeDesigner,
        builder: (context, _, _, _) =>
            SignalBuilder3<String, Set<String>, Set<String>>(
              signal1: controller.activeLayerId,
              signal2: controller.hiddenLayers,
              signal3: controller.lockedLayers,
              builder: (context, activeDepth, hidden, locked, _) =>
                  _build(context, activeDepth, hidden, locked),
            ),
      ),
    );
  }

  /// Records [change] to [target] as one undo step.
  void _edit(
    LevelMapTarget target,
    String label,
    void Function(jge.LevelMapData map) change, {
    Object? mergeKey,
  }) {
    final scope = session.scope;
    final command = MapStructureCommand.record(
      label: label,
      docs: scope.mapDocs,
      ref: target.ref,
      change: change,
      mergeKey: mergeKey,
    );
    if (command != null) scope.history.pushApplied(command);
  }

  int _orderOf(String depth) => session.scope.layers.orderOf(depth);

  /// What is on [layer] of [target]: the map's children on it.
  List<jge.Entity> _membersOf(LevelMapTarget target, jge.MapLayerData layer) =>
      [
        for (final id
            in target.entity.getComponent<jge.ChildrenComponent>()?.childIds ??
                const <jge.EntityId>[])
          if (session.world.getEntity(id) case final e?
              when e.getComponent<jge.LayerComponent>()?.mapLayer == layer.id)
            e,
      ];

  String _labelOf(String depth) {
    final label = session.scope.layers.byId(depth)?.label;
    if (label != null && label.isNotEmpty) return label;
    return depth.isEmpty ? depth : depth[0].toUpperCase() + depth.substring(1);
  }

  Map<String, int> _entityCounts() {
    final counts = <String, int>{};
    for (final entity in session.world.query([jge.LayerComponent])) {
      if (!entity.isActive) continue;
      final layer = entity.getComponent<jge.LayerComponent>()!;
      // What is on a map layer is counted with it, not with the depth.
      if (layer.mapLayer != null) continue;
      counts[layer.layerId] = (counts[layer.layerId] ?? 0) + 1;
    }
    return counts;
  }

  Widget _build(
    BuildContext context,
    String activeDepth,
    Set<String> hidden,
    Set<String> locked,
  ) {
    final tiles = session.scope.tiles;
    final target = tiles.peek(session.world);
    final active = target == null ? null : tiles.peekLayer(target);
    final counts = _entityCounts();
    final mapLayers = target?.data.layers ?? const <jge.MapLayerData>[];
    // Registered depths, and any the scene uses without declaring, so a
    // level authored elsewhere still shows all of its layers. Front first.
    final depths = <String>{
      ...session.scope.layers.all.map((l) => l.id),
      ...counts.keys,
      for (final l in mapLayers) l.sortLayerId,
    }.toList()..sort((a, b) => _orderOf(b).compareTo(_orderOf(a)));
    final editable = target == null || !target.isReadOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(target, active),
        if (_mapSettings && target != null) _settings(target),
        if (target?.isReadOnly ?? false)
          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Text(
              'A Tiled map: shown as it is, not edited here.',
              style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
            ),
          ),
        Expanded(
          child: EditorScrollbar(
            builder: (_, scroll) => ListView(
              controller: scroll,
              padding: const EdgeInsets.only(bottom: 4),
              children: [
                for (final depth in depths) ...[
                  _DepthHeader(
                    label: _labelOf(depth),
                    description: session.scope.layers.byId(depth)?.description,
                    isActive: depth == activeDepth,
                    onSelect: () => _selectDepth(depth),
                    onAdd: editable ? () => _addLayer(target, depth) : null,
                  ),
                  // Top first, as they draw.
                  for (final layer in mapLayers.reversed)
                    if (layer.sortLayerId == depth) ...[
                      _MapLayerRow(
                        layer: layer,
                        count: _membersOf(target!, layer).length,
                        isActive: layer.id == active?.id,
                        isOpen: layer.id == _open,
                        editable: editable,
                        onSelect: () => _selectLayer(layer),
                        onMoveSelection: () =>
                            _moveSelectionOnto(target, layer),
                        onToggleOpen: () => setState(
                          () => _open = _open == layer.id ? null : layer.id,
                        ),
                        onToggleVisible: () => _edit(
                          target,
                          layer.visible ? 'Hide map layer' : 'Show map layer',
                          (_) => layer.visible = !layer.visible,
                        ),
                        onToggleLocked: () => _edit(
                          target,
                          layer.locked ? 'Unlock map layer' : 'Lock map layer',
                          (_) => layer.locked = !layer.locked,
                        ),
                        onToggleCollides: () => _edit(
                          target,
                          layer.collides
                              ? 'Tiles stop colliding'
                              : 'Tiles collide',
                          (_) => layer.collides = !layer.collides,
                        ),
                      ),
                      if (layer.id == _open) _layerSettings(target, layer),
                    ],
                  _EntitiesRow(
                    count: counts[depth] ?? 0,
                    isHidden: hidden.contains(depth),
                    isLocked: locked.contains(depth),
                    onToggleHidden: () {
                      final nowHidden = !hidden.contains(depth);
                      session.controller.setLayerHidden(
                        depth,
                        hidden: nowHidden,
                      );
                      _applyVisibility(depth, visible: !nowHidden);
                    },
                    onToggleLocked: () => session.controller.setLayerLocked(
                      depth,
                      locked: !locked.contains(depth),
                    ),
                    onMoveSelection: () => _moveSelectionTo(depth),
                  ),
                ],
                if (target == null)
                  TilePanelMessage(
                    text:
                        'No Level Map yet: it is made when you first paint '
                        'tiles, or drop a tileset.',
                    action: ('Create Level Map', () => createLevelMap(session)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Choosing ─────────────────────────────────────────────────────────────

  void _selectDepth(String depth) =>
      session.controller.activeLayerId.value = depth;

  /// [layer] is painted from now on, and what is placed goes to its depth.
  void _selectLayer(jge.MapLayerData layer) {
    session.scope.tiles.layerId.value = layer.id;
    session.controller.activeLayerId.value = layer.sortLayerId;
  }

  // ── The toolbar ──────────────────────────────────────────────────────────

  Widget _toolbar(LevelMapTarget? target, jge.MapLayerData? active) {
    final layers = target?.data.layers ?? const <jge.MapLayerData>[];
    final index = active == null ? -1 : layers.indexOf(active);
    final editable = target != null && !target.isReadOnly && active != null;

    final scope = session.scope;

    /// A copy of the layer — tiles, and what is on it.
    void duplicate() {
      const label = 'Duplicate map layer';
      jge.MapLayerData? made;
      final structure = MapStructureCommand.record(
        label: label,
        docs: scope.mapDocs,
        ref: target!.ref,
        change: (map) {
          final json = active!.toJson()
            ..['id'] = map.nextLayerId++
            ..['name'] = '${active.name} copy';
          made = jge.MapLayerData.fromJson(json);
          map.layers.insert(index + 1, made!);
        },
      );
      if (structure == null || made == null) return;
      final members = _membersOf(target, active!);
      if (members.isEmpty) {
        scope.history.pushApplied(structure);
      } else {
        final create = CreateEntitiesCommand(
          label: label,
          world: session.world,
          sceneState: session.sceneState,
          specs: [for (final e in members) _copyOnto(e, made!.id)],
        )..redo();
        scope.history.pushApplied(
          CompositeCommand(label: label, commands: [structure, create]),
        );
      }
      _selectLayer(made!);
    }

    /// The layer, and what is on it, gone — one step.
    void remove() {
      const label = 'Delete map layer';
      final members = _membersOf(target!, active!);
      final delete = members.isEmpty
          ? null
          : (DeleteEntitiesCommand(
              label: label,
              world: session.world,
              sceneState: session.sceneState,
              entities: members,
              codec: scope.codec,
            )..redo());
      final structure = MapStructureCommand.record(
        label: label,
        docs: scope.mapDocs,
        ref: target.ref,
        change: (map) => map.layers.remove(active),
      );
      final steps = [?delete, ?structure];
      if (steps.isEmpty) return;
      scope.history.pushApplied(
        steps.length == 1
            ? steps.single
            : CompositeCommand(label: label, commands: steps),
      );
    }

    void shift(int by) {
      final to = index + by;
      if (to < 0 || to >= layers.length) return;
      _edit(target!, by > 0 ? 'Raise map layer' : 'Lower map layer', (map) {
        map.layers
          ..removeAt(index)
          ..insert(to, active!);
      });
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Icon(Icons.grid_on, size: 13, color: EditorTheme.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              target == null
                  ? 'No Level Map'
                  : (target.entity.name ?? jge.LevelMaps.primaryName),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
            ),
          ),
          _Icon(
            icon: Icons.tune,
            tooltip: 'Map settings: grid and tile size',
            isOn: _mapSettings,
            onTap: target == null
                ? null
                : () => setState(() => _mapSettings = !_mapSettings),
          ),
          _Icon(
            icon: Icons.copy_all_outlined,
            tooltip: 'Duplicate the map layer: its tiles, and what is on it',
            onTap: editable ? duplicate : null,
          ),
          _Icon(
            icon: Icons.arrow_upward,
            tooltip: 'Raise: draw in front of the map layer above',
            onTap: editable && index < layers.length - 1
                ? () => shift(1)
                : null,
          ),
          _Icon(
            icon: Icons.arrow_downward,
            tooltip: 'Lower: draw behind the map layer below',
            onTap: editable && index > 0 ? () => shift(-1) : null,
          ),
          _Icon(
            icon: Icons.delete_outline,
            tooltip: 'Delete the map layer, and what is on it',
            onTap: editable ? remove : null,
          ),
        ],
      ),
    );
  }

  /// A new map layer at [depth], in front of the others there — the scene's
  /// Level Map made for it when there is none. One undo step.
  void _addLayer(LevelMapTarget? target, String depth) {
    final order = session.scope.layers.byId(depth)?.order ?? _orderOf(depth);
    String nameIn(jge.LevelMapData map) {
      final base = _labelOf(depth);
      final taken = {for (final l in map.layers) l.name};
      if (!taken.contains(base)) return base;
      var n = 2;
      while (taken.contains('$base $n')) {
        n++;
      }
      return '$base $n';
    }

    void place(jge.MapLayerData layer) => layer
      ..sortLayerId = depth
      ..sortLayer = order;

    if (target == null) {
      // The new map's own layer is the one asked for.
      final provision = session.scope.mapProvision;
      final made = provision.ensure(session.world);
      final layer = made?.data.layers.firstOrNull;
      if (layer != null && depth != 'main') {
        place(layer);
        layer.name = nameIn(made!.data);
      }
      provision.keep('Add map layer');
      if (layer != null) _selectLayer(layer);
      return;
    }
    jge.MapLayerData? made;
    _edit(target, 'Add map layer', (map) {
      // In front of the depth's other layers.
      final last = map.layers.lastIndexWhere((l) => l.sortLayerId == depth);
      made = map.addLayer(
        name: nameIn(map),
        index: last < 0 ? map.layers.length : last + 1,
      );
      place(made!);
    });
    if (made != null) _selectLayer(made!);
  }

  // ── Entities ─────────────────────────────────────────────────────────────

  /// Hides or shows every renderable at [depth].
  ///
  /// Writes `renderable.visible` rather than deactivating the entity: an
  /// inactive entity stops being simulated, which would change what the level
  /// does rather than just what the editor shows.
  void _applyVisibility(String depth, {required bool visible}) {
    for (final entity in session.world.query([jge.LayerComponent])) {
      final layer = entity.getComponent<jge.LayerComponent>()!;
      if (layer.layerId != depth || layer.mapLayer != null) continue;
      layer.visible = visible;
      entity.getComponent<jge.RenderableComponent>()?.renderable.visible =
          visible;
    }
    session.sceneState.refresh();
  }

  List<jge.Entity> _selection() {
    final state = session.sceneState;
    return state.multiSelectedIds.value.isEmpty
        ? <jge.Entity>[
            if (state.selectedEntity.value != null) state.selectedEntity.value!,
          ]
        : state.multiSelectedIds.value
              .map(session.world.getEntity)
              .whereType<jge.Entity>()
              .toList();
  }

  void _moveSelectionTo(String depth) {
    final all = _selection();
    // What is on a map layer draws with it: moved between the map's layers,
    // not to a depth.
    final targets = [
      for (final e in all)
        if (e.getComponent<jge.LayerComponent>()?.mapLayer == null) e,
    ];
    if (targets.isEmpty) {
      session.controller.setStatus(
        all.isEmpty
            ? 'Select what to move there first'
            : 'On a map layer: move it to another map layer instead',
      );
      return;
    }
    session.ops.moveToLayer(targets, depth);
  }

  /// The selection onto [layer] of [target]'s map: under the map, drawn and
  /// hidden with the layer. One undo step.
  void _moveSelectionOnto(LevelMapTarget target, jge.MapLayerData layer) {
    final map = target.entity;
    final targets = [
      for (final e in _selection())
        if (e.id != map.id && !e.hasComponent<jge.GeneratedEntityComponent>())
          e,
    ];
    if (targets.isEmpty) {
      session.controller.setStatus('Select what to move there first');
      return;
    }
    session.scope.entities.reparentAll(targets, map, mapLayer: layer.id);
    session.controller.setStatus(
      'Moved ${targets.length == 1 ? targets.single.name ?? 'it' : '${targets.length} entities'} '
      'onto ${layer.name}',
    );
  }

  /// A copy of [entity] for the layer [layerId], under the same map, with a
  /// name of its own.
  EntitySpec _copyOnto(jge.Entity entity, int layerId) {
    final spec = EntitySpec.of(
      entity,
      session.scope.codec,
      world: session.world,
    );
    final components = [
      for (final c in spec.decode())
        if (c is! jge.ParentComponent && c is! jge.ChildrenComponent) c,
    ];
    for (final c in components.whereType<jge.LayerComponent>()) {
      c.mapLayer = layerId;
    }
    final base = (entity.name ?? 'entity').replaceFirst(RegExp(r'_\d+$'), '');
    return EntitySpec(
      name: session.uniqueName(base),
      componentsJson: [
        for (final c in components) ?session.scope.codec.encode(c),
      ],
      codec: session.scope.codec,
      parentName: spec.parentName,
    );
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Widget _settings(LevelMapTarget target) {
    final m = target.data;
    final staggers =
        m.orientation == jge.MapOrientation.staggered ||
        m.orientation == jge.MapOrientation.hexagonal;
    const whole = NumberScrubConfig(integer: true, fractionDigits: 0, min: 1);
    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownEditorRow(
          label: 'Grid',
          value: m.orientation.name,
          options: [for (final o in jge.MapOrientation.values) o.name],
          onChanged: (v) => _edit(
            target,
            'Map orientation',
            (map) => map.orientation = jge.MapOrientation.fromName(v),
          ),
        ),
        ScrubFieldRow(
          label: 'Tile W',
          value: m.tileWidth.toDouble(),
          scrubConfig: whole,
          onChanged: (v) => _edit(
            target,
            'Tile width',
            (map) => map.tileWidth = v.round().clamp(1, 4096),
            mergeKey: ('tileWidth', target.ref),
          ),
        ),
        ScrubFieldRow(
          label: 'Tile H',
          value: m.tileHeight.toDouble(),
          scrubConfig: whole,
          onChanged: (v) => _edit(
            target,
            'Tile height',
            (map) => map.tileHeight = v.round().clamp(1, 4096),
            mergeKey: ('tileHeight', target.ref),
          ),
        ),
        if (staggers) ...[
          DropdownEditorRow(
            label: 'Stagger',
            value: m.staggerAxis.name,
            options: [for (final a in jge.TileStaggerAxis.values) a.name],
            onChanged: (v) => _edit(
              target,
              'Stagger axis',
              (map) => map.staggerAxis = jge.TileStaggerAxis.fromName(v),
            ),
          ),
          DropdownEditorRow(
            label: 'Index',
            value: m.staggerIndex.name,
            options: [for (final i in jge.TileStaggerIndex.values) i.name],
            onChanged: (v) => _edit(
              target,
              'Stagger index',
              (map) => map.staggerIndex = jge.TileStaggerIndex.fromName(v),
            ),
          ),
        ],
        if (m.orientation == jge.MapOrientation.hexagonal)
          ScrubFieldRow(
            label: 'Hex side',
            value: m.hexSideLength.toDouble(),
            scrubConfig: const NumberScrubConfig(
              integer: true,
              fractionDigits: 0,
              min: 0,
            ),
            onChanged: (v) => _edit(
              target,
              'Hex side length',
              (map) => map.hexSideLength = v.round().clamp(0, 4096),
              mergeKey: ('hexSide', target.ref),
            ),
          ),
      ],
    );
    if (target.isReadOnly) {
      body = IgnorePointer(child: Opacity(opacity: 0.5, child: body));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: EditorTheme.border)),
      ),
      child: body,
    );
  }

  Widget _layerSettings(LevelMapTarget target, jge.MapLayerData layer) {
    Object key(String field) => (field, target.ref, layer.id);
    const fine = NumberScrubConfig(step: 0.05, fractionDigits: 2);
    const pixels = NumberScrubConfig(step: 1, fractionDigits: 0);
    final sortIds = {
      for (final l in session.scope.layers.all) l.id,
      layer.sortLayerId,
    }.toList();
    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextEditorRow(
          label: 'Name',
          initialValue: layer.name,
          onSubmitted: (v) {
            final name = v.trim();
            if (name.isEmpty || name == layer.name) return;
            _edit(target, 'Rename map layer', (_) => layer.name = name);
          },
        ),
        ScrubFieldRow(
          label: 'Opacity',
          value: layer.opacity,
          scrubConfig: const NumberScrubConfig(
            step: 0.05,
            fractionDigits: 2,
            min: 0,
            max: 1,
          ),
          onChanged: (v) => _edit(
            target,
            'Layer opacity',
            (_) => layer.opacity = v.clamp(0.0, 1.0),
            mergeKey: key('opacity'),
          ),
        ),
        _TintRow(
          tint: layer.tint,
          onChanged: (argb) => _edit(
            target,
            'Layer tint',
            (_) => layer.tint = argb,
            mergeKey: key('tint'),
          ),
        ),
        DropdownEditorRow(
          label: 'Draws in',
          value: layer.sortLayerId,
          options: sortIds,
          onChanged: (v) => _edit(target, 'Layer depth', (_) {
            layer.sortLayerId = v;
            final preset = session.scope.layers.byId(v);
            if (preset != null) layer.sortLayer = preset.order;
          }),
        ),
        ScrubFieldRow(
          label: 'Z order',
          value: layer.zOrder.toDouble(),
          scrubConfig: const NumberScrubConfig(
            integer: true,
            fractionDigits: 0,
          ),
          onChanged: (v) => _edit(
            target,
            'Layer z order',
            (_) => layer.zOrder = v.round(),
            mergeKey: key('zOrder'),
          ),
        ),
        ScrubFieldRow(
          label: 'Parallax X',
          value: layer.parallaxX,
          scrubConfig: fine,
          onChanged: (v) => _edit(
            target,
            'Layer parallax',
            (_) => layer.parallaxX = v,
            mergeKey: key('parallaxX'),
          ),
        ),
        ScrubFieldRow(
          label: 'Parallax Y',
          value: layer.parallaxY,
          scrubConfig: fine,
          onChanged: (v) => _edit(
            target,
            'Layer parallax',
            (_) => layer.parallaxY = v,
            mergeKey: key('parallaxY'),
          ),
        ),
        ScrubFieldRow(
          label: 'Offset X',
          value: layer.offsetX,
          scrubConfig: pixels,
          onChanged: (v) => _edit(
            target,
            'Layer offset',
            (_) => layer.offsetX = v,
            mergeKey: key('offsetX'),
          ),
        ),
        ScrubFieldRow(
          label: 'Offset Y',
          value: layer.offsetY,
          scrubConfig: pixels,
          onChanged: (v) => _edit(
            target,
            'Layer offset',
            (_) => layer.offsetY = v,
            mergeKey: key('offsetY'),
          ),
        ),
        TextEditorRow(
          label: 'Class',
          initialValue: layer.className,
          onSubmitted: (v) {
            if (v.trim() == layer.className) return;
            _edit(target, 'Layer class', (_) => layer.className = v.trim());
          },
        ),
      ],
    );
    if (target.isReadOnly) {
      body = IgnorePointer(child: Opacity(opacity: 0.5, child: body));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      color: EditorTheme.surfaceDark,
      child: body,
    );
  }
}

/// A depth's caption: click to place new things at it; + adds a map layer
/// there.
class _DepthHeader extends StatelessWidget {
  const _DepthHeader({
    required this.label,
    required this.isActive,
    required this.onSelect,
    required this.onAdd,
    this.description,
  });

  final String label;
  final String? description;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => Material(
    color: isActive
        ? EditorTheme.primaryMuted.withValues(alpha: 0.35)
        : EditorTheme.surfaceDark,
    child: InkWell(
      onTap: onSelect,
      child: Tooltip(
        message: description == null
            ? 'Place new things at $label'
            : '$description. Click to place new things here',
        child: Container(
          height: 24,
          padding: const EdgeInsets.only(left: 8, right: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 3,
                color: isActive
                    ? EditorTheme.primaryBright
                    : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isActive
                        ? EditorTheme.textBright
                        : EditorTheme.textMuted,
                  ),
                ),
              ),
              _Icon(
                icon: Icons.add,
                tooltip: 'Add a map layer at $label',
                onTap: onAdd,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MapLayerRow extends StatelessWidget {
  const _MapLayerRow({
    required this.layer,
    required this.count,
    required this.isActive,
    required this.isOpen,
    required this.editable,
    required this.onSelect,
    required this.onMoveSelection,
    required this.onToggleOpen,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onToggleCollides,
  });

  final jge.MapLayerData layer;

  /// How many entities are on it.
  final int count;
  final bool isActive;
  final bool isOpen;
  final bool editable;
  final VoidCallback onSelect;
  final VoidCallback onMoveSelection;
  final VoidCallback onToggleOpen;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final VoidCallback onToggleCollides;

  @override
  Widget build(BuildContext context) => Material(
    color: isActive ? EditorTheme.selectionBg : Colors.transparent,
    child: InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 4, top: 1, bottom: 1),
        child: Row(
          children: [
            _Icon(
              icon: layer.visible ? Icons.visibility : Icons.visibility_off,
              tooltip: layer.visible ? 'Hide map layer' : 'Show map layer',
              isOn: layer.visible,
              onTap: editable ? onToggleVisible : null,
            ),
            _Icon(
              icon: layer.locked ? Icons.lock : Icons.lock_open,
              tooltip: layer.locked
                  ? 'Unlock map layer: let the tools paint it'
                  : 'Lock map layer: keep the tools off it',
              isOn: layer.locked,
              onTap: editable ? onToggleLocked : null,
            ),
            _Icon(
              icon: Icons.border_outer,
              tooltip: layer.collides
                  ? 'Tiles on this layer collide. Click to make them '
                        'decoration'
                  : 'Tiles on this layer are decoration. Click to make them '
                        'collide',
              isOn: layer.collides,
              onTap: editable ? onToggleCollides : null,
            ),
            const SizedBox(width: 4),
            Icon(Icons.grid_on, size: 12, color: EditorTheme.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                layer.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? EditorTheme.textBright
                      : EditorTheme.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (count > 0)
              Tooltip(
                message: '$count entit${count == 1 ? 'y' : 'ies'} on it',
                child: Text(
                  '$count',
                  style: TextStyle(fontSize: 10, color: EditorTheme.textMuted),
                ),
              ),
            if (editable)
              _Icon(
                icon: Icons.move_down,
                tooltip: 'Move the selection onto this map layer',
                onTap: onMoveSelection,
              ),
            _Icon(
              icon: isOpen ? Icons.expand_less : Icons.expand_more,
              tooltip: isOpen ? 'Hide layer settings' : 'Layer settings',
              onTap: onToggleOpen,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The entities placed at a depth, as one row: how many, and the editor's
/// own eye and lock for them.
class _EntitiesRow extends StatelessWidget {
  const _EntitiesRow({
    required this.count,
    required this.isHidden,
    required this.isLocked,
    required this.onToggleHidden,
    required this.onToggleLocked,
    required this.onMoveSelection,
  });

  final int count;
  final bool isHidden;
  final bool isLocked;
  final VoidCallback onToggleHidden;
  final VoidCallback onToggleLocked;
  final VoidCallback onMoveSelection;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 4, top: 1, bottom: 1),
    child: Row(
      children: [
        _Icon(
          icon: isHidden ? Icons.visibility_off : Icons.visibility,
          tooltip: isHidden
              ? 'Show the entities at this depth'
              : 'Hide the entities at this depth (editor only)',
          isOn: !isHidden,
          onTap: onToggleHidden,
        ),
        _Icon(
          icon: isLocked ? Icons.lock : Icons.lock_open,
          tooltip: isLocked
              ? 'Unlock the entities at this depth'
              : 'Lock the entities at this depth (editor only)',
          isOn: isLocked,
          onTap: onToggleLocked,
        ),
        const SizedBox(width: 26),
        Icon(Icons.category_outlined, size: 12, color: EditorTheme.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            count == 1 ? '1 entity' : '$count entities',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: EditorTheme.textSecondary),
          ),
        ),
        _Icon(
          icon: Icons.move_down,
          tooltip: 'Move the selection to this depth',
          onTap: onMoveSelection,
        ),
      ],
    ),
  );
}

/// A layer's tint: a swatch, and a button to take it off.
class _TintRow extends StatelessWidget {
  const _TintRow({required this.tint, required this.onChanged});

  final int? tint;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: InspectorField.labelWidth,
          child: Text(
            'Tint',
            style: TextStyle(fontSize: 11, color: EditorTheme.textSecondary),
          ),
        ),
        Expanded(
          child: MiniColorField(
            color: Color(tint ?? 0xFFFFFFFF),
            inherited: tint == null,
            onChanged: (c) {
              final argb = c.toARGB32();
              onChanged(argb == 0xFFFFFFFF ? null : argb);
            },
          ),
        ),
        if (tint != null)
          _Icon(
            icon: Icons.close,
            tooltip: 'No tint',
            onTap: () => onChanged(null),
          ),
      ],
    ),
  );
}

class _Icon extends StatelessWidget {
  const _Icon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isOn = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isOn;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(
          icon,
          size: 14,
          color: onTap == null
              ? EditorTheme.textMuted.withValues(alpha: 0.4)
              : isOn
              ? EditorTheme.textSecondary
              : EditorTheme.textMuted,
        ),
      ),
    ),
  );
}
