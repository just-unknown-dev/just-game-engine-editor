import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../../core/physics/layer_refactor.dart';
import '../../../../core/physics/physics_bodies.dart';
import '../../../dialogs/scene_actions_dialogs.dart' show promptSceneName;
import '../../../inspector/physics_field_editors.dart' show LayerHighlight;

/// The project's collision layers — every one in use, what it looks like,
/// what is on it — and the grid of which collide.
///
/// Made like the Tags dock: a layer is made, recoloured, described and
/// renamed here, its bodies selected, and deleted everywhere with a preview
/// — what was on it moves to another layer first. Every change is saved to
/// the project's layer file at once and reaches a running play-test.
class PhysicsLayersDock extends StatefulWidget {
  const PhysicsLayersDock({super.key, required this.scope});

  final EditorScope scope;

  @override
  State<PhysicsLayersDock> createState() => _PhysicsLayersDockState();
}

class _PhysicsLayersDockState extends State<PhysicsLayersDock> {
  String _query = '';

  EditorScope get scope => widget.scope;

  /// The layer whose row or grid line the pointer is over: its bodies ring
  /// in the level. One that goes from under the pointer — deleted, the
  /// dock shut — hears no exit, so the ring is taken off here.
  int? _hovered;

  void _hover(int layer, bool on) {
    if (on) {
      _hovered = layer;
    } else if (_hovered == layer) {
      _hovered = null;
    }
    LayerHighlight.set(scope, layer, on);
  }

  @override
  void dispose() {
    if (_hovered case final layer?) LayerHighlight.set(scope, layer, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SignalBuilder<jge.PhysicsLayers>(
    signal: scope.physicsLayers.layers,
    // The counts follow the scene: a body moved to a layer shows at once.
    builder: (context, layers, _) => SignalBuilder<int>(
      signal: scope.sceneState.revision,
      builder: (context, _, _) => _body(context, layers),
    ),
  );

  /// The bodies, 2-D and 3-D, an author placed on each layer — not the
  /// level map's.
  List<List<jge.Entity>> _bodies() =>
      PhysicsBodies.byLayer(scope.world, scope.definitions);

  Widget _body(BuildContext context, jge.PhysicsLayers layers) {
    final store = scope.physicsLayers;
    if (_hovered case final layer?
        when layer != 0 && !layers.named.contains(layer)) {
      _hovered = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => LayerHighlight.set(scope, layer, false),
      );
    }
    final bodies = _bodies();
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final i in layers.named)
        if (q.isEmpty ||
            layers.nameOf(i).toLowerCase().contains(q) ||
            layers.descriptionOf(i).toLowerCase().contains(q))
          i,
    ];
    final inUse = layers.named.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              EditorSearchField(
                hint: 'Filter layers',
                width: 180,
                onChanged: (text) => setState(() => _query = text),
              ),
              const SizedBox(width: 8),
              EditorButton(
                label: 'New layer',
                icon: Icons.add_rounded,
                onPressed: layers.firstFree == null
                    ? null
                    : () => _create(context),
              ),
              const SizedBox(width: 10),
              Text(
                '$inUse of ${jge.PhysicsLayers.count} in use',
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
              ),
              const Spacer(),
              if (store.error case final error?) ...[
                Flexible(
                  child: Tooltip(
                    message: error,
                    child: Text(
                      error,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.error,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
                // A file left as it is because it could not be read: read
                // again once it is fixed.
                if (store.isUnreadable)
                  EditorIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Read the layer file again',
                    onTap: () => setState(store.load),
                  ),
              ] else if (!store.hasFile)
                Flexible(
                  child: Tooltip(
                    message: store.path,
                    child: Text(
                      'No layer file yet — the first change writes it.',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: inUse < 2 && q.isEmpty
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row(context, layers, 0, bodies[0]),
                          Expanded(
                            child: EditorEmptyState(
                              icon: Icons.layers_outlined,
                              title: 'Everything is on Default',
                              hint:
                                  'Make a layer for each kind of thing that '
                                  'collides differently — the player, '
                                  'enemies, pickups, bullets — then tick '
                                  'which pairs collide in the grid.',
                              actionLabel: 'New layer',
                              onAction: () => _create(context),
                            ),
                          ),
                        ],
                      )
                    : shown.isEmpty
                    ? const EditorEmptyState(
                        icon: Icons.layers_outlined,
                        title: 'No layer matches',
                        hint: 'Layers are found by name and description.',
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) =>
                            _row(context, layers, shown[i], bodies[shown[i]]),
                      ),
              ),
              VerticalDivider(width: 1, color: EditorTheme.border),
              Expanded(
                flex: 2,
                child: _GridPanel(
                  layers: layers,
                  onChanged: store.setCollision,
                  // One write of the file and one change, for every pair:
                  // from the layers as they are now, not as last built.
                  onAllCollide: () {
                    var next = store.value;
                    final named = next.named.toList();
                    for (var i = 0; i < named.length; i++) {
                      for (var j = i; j < named.length; j++) {
                        if (!next.collides(named[i], named[j])) {
                          next = next.withCollision(named[i], named[j], true);
                        }
                      }
                    }
                    if (!identical(next, store.value)) store.set(next);
                  },
                  onHover: _hover,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    jge.PhysicsLayers layers,
    int layer,
    List<jge.Entity> on,
  ) {
    final name = layers.nameOf(layer);
    final description = layers.descriptionOf(layer);
    final color = layers.colorOf(layer);
    return MouseRegion(
      onEnter: (_) => _hover(layer, true),
      onExit: (_) => _hover(layer, false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: EditorTheme.border.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            Tooltip(
              message: 'Change the colour',
              child: InkWell(
                onTapDown: (d) => _pickColour(context, d.globalPosition, layer),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 22,
              child: Tooltip(
                message:
                    'Layer $layer: what bodies on it save. A rename changes '
                    'nothing else.',
                child: Text(
                  '$layer',
                  style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: InkWell(
                onTap: () => _rename(context, layer),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: EditorTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                on.isEmpty
                    ? 'on nothing here'
                    : '${on.length} ${on.length == 1 ? 'body' : 'bodies'} here',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: EditorTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _describe(context, layer),
                child: Text(
                  description.isNotEmpty ? description : 'Add a description…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: description.isNotEmpty
                        ? EditorTheme.textSecondary
                        : EditorTheme.textMuted,
                    fontSize: 11,
                    fontStyle: description.isNotEmpty
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                ),
              ),
            ),
            EditorIconButton(
              icon: Icons.select_all_rounded,
              tooltip: 'Select everything on "$name"',
              onTap: on.isEmpty ? null : () => _select(on),
            ),
            EditorIconButton(
              icon: Icons.drive_file_rename_outline_rounded,
              tooltip: 'Rename',
              onTap: () => _rename(context, layer),
            ),
            EditorIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: layer == 0
                  ? 'The default layer: everything is on it until moved, '
                        'so it cannot be deleted'
                  : 'Delete, moving what is on it',
              onTap: layer == 0 ? null : () => _delete(context, layer),
            ),
          ],
        ),
      ),
    );
  }

  void _select(List<jge.Entity> entities) {
    final selectable = [
      for (final e in entities)
        if (scope.sceneState.canSelect(e)) e,
    ];
    if (selectable.isEmpty) return;
    scope.sceneState.selectRange(selectable, anchor: selectable.first);
  }

  Future<void> _create(BuildContext context) async {
    final name = await promptSceneName(
      context,
      title: 'New layer',
      actionLabel: 'Create',
      hint: 'e.g. Enemies',
      validate: (text) => scope.physicsLayers.problemWithNew(text),
    );
    if (name == null) return;
    scope.physicsLayers.create(name);
  }

  Future<void> _rename(BuildContext context, int layer) async {
    final store = scope.physicsLayers;
    final name = await promptSceneName(
      context,
      title: 'Rename "${store.value.nameOf(layer)}"',
      actionLabel: 'Rename',
      initialValue: store.value.nameOf(layer),
      hint: 'Bodies keep the layer: only its name changes',
      validate: (text) => store.problemWithRename(layer, text),
    );
    if (name == null) return;
    store.rename(layer, name);
  }

  Future<void> _describe(BuildContext context, int layer) async {
    final store = scope.physicsLayers;
    final text = await promptSceneName(
      context,
      title: 'Describe "${store.value.nameOf(layer)}"',
      actionLabel: 'Save',
      initialValue: store.value.descriptionOf(layer),
      hint: 'What goes on it, and what it should hit',
      validate: (_) => null,
    );
    if (text == null) return;
    store.describe(layer, text);
  }

  Future<void> _pickColour(BuildContext context, Offset at, int layer) async {
    final layers = scope.physicsLayers.value;
    final current = layers.colorOf(layer);
    final palette = [
      for (var i = 0; i < jge.PhysicsLayers.count; i++)
        jge.PhysicsLayers.defaultColorOf(i),
    ];
    final chosen = await showEditorMenu<Color>(context, at, [
      for (final c in palette)
        editorMenuItem(
          c,
          c == current ? 'Current' : '',
          icon: Icons.circle,
          iconColor: c,
        ),
    ]);
    if (chosen == null) return;
    scope.physicsLayers.recolor(
      layer,
      chosen == jge.PhysicsLayers.defaultColorOf(layer) ? null : chosen,
    );
  }

  Future<void> _delete(BuildContext context, int layer) async {
    final refactor = LayerRefactor(scope);
    final found = refactor.plan(layer);
    final moveTo = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) =>
          _DeleteLayerDialog(layers: scope.physicsLayers.value, plan: found),
    );
    if (moveTo == null) return;
    await refactor.apply(found.movingTo(moveTo));
  }
}

/// What deleting a layer will change, and where what is on it goes.
class _DeleteLayerDialog extends StatefulWidget {
  const _DeleteLayerDialog({required this.layers, required this.plan});

  final jge.PhysicsLayers layers;
  final LayerChangePlan plan;

  @override
  State<_DeleteLayerDialog> createState() => _DeleteLayerDialogState();
}

class _DeleteLayerDialogState extends State<_DeleteLayerDialog> {
  int _moveTo = 0;

  @override
  Widget build(BuildContext context) {
    final layers = widget.layers;
    final plan = widget.plan;
    final name = layers.nameOf(plan.layer);
    Widget group(
      String heading,
      List<LayerUse> uses, {
      String? note,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$heading — ${uses.length}',
            style: TextStyle(
              color: EditorTheme.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (note != null)
            Text(
              note,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
            ),
          for (final use in uses.take(8))
            Text(
              '  ${use.owner}: ${use.where}',
              style: TextStyle(color: EditorTheme.textSecondary, fontSize: 11),
            ),
          if (uses.length > 8)
            Text(
              '  …and ${uses.length - 8} more',
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
            ),
        ],
      ),
    );

    return EditorAlert(
      title: 'Delete "$name"',
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (plan.all.isEmpty)
                Text(
                  'Nothing in the project is on it: only the layer goes. Its '
                  'number is free for the next layer, colliding with '
                  'everything.',
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 12,
                  ),
                )
              else ...[
                Row(
                  children: [
                    Text(
                      'Move what is on it to',
                      style: TextStyle(
                        color: EditorTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 170,
                      child: EditorDropdown<int>(
                        value: _moveTo,
                        options: [
                          for (final i in layers.named)
                            if (i != plan.layer)
                              EditorDropdownOption(
                                value: i,
                                label: layers.nameOf(i),
                                color: layers.colorOf(i),
                              ),
                        ],
                        onChanged: (i) => setState(() => _moveTo = i),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (plan.openUses.isNotEmpty)
                  group(
                    'The open scene (${plan.openScene})',
                    plan.openUses,
                    note:
                        'Changed now, as one step you can undo; saved when '
                        'you save the scene.',
                  ),
                for (final e in plan.scenes.entries)
                  group(
                    'Scene ${e.key}',
                    e.value,
                    note: 'Rewritten on disk, after a backup.',
                  ),
                for (final e in plan.prefabs.entries)
                  group(
                    'Prefab ${e.key}',
                    e.value,
                    note:
                        'Rewritten on disk, after a backup; every instance '
                        'follows it.',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        EditorButton(
          label: 'Cancel',
          kind: EditorButtonKind.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        EditorButton(
          label: 'Delete',
          kind: EditorButtonKind.danger,
          onPressed: () => Navigator.of(context).pop(_moveTo),
        ),
      ],
    );
  }
}

/// Which named layers collide: a triangle of boxes, each pair once.
class _GridPanel extends StatelessWidget {
  const _GridPanel({
    required this.layers,
    required this.onChanged,
    required this.onAllCollide,
    required this.onHover,
  });

  final jge.PhysicsLayers layers;
  final void Function(int a, int b, bool collide) onChanged;

  /// Every pair collides again.
  final VoidCallback onAllCollide;
  final void Function(int layer, bool on) onHover;

  static const double _cell = 22;
  static const double _labelWidth = 110;

  @override
  Widget build(BuildContext context) {
    final named = layers.named.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Row(
            children: [
              Text(
                'WHAT COLLIDES',
                style: TextStyle(
                  color: EditorTheme.primaryMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              EditorIconButton(
                icon: Icons.grid_on_rounded,
                tooltip: 'Make every pair collide again',
                onTap: onAllCollide,
              ),
            ],
          ),
        ),
        Expanded(
          child: named.length < 2
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    'With one layer, everything collides. Make a second to '
                    'choose which pairs do.',
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(child: _grid(named)),
                ),
        ),
      ],
    );
  }

  Widget _grid(List<int> named) {
    final columns = named.reversed.toList();
    Widget name(int i, {bool vertical = false}) {
      final text = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: layers.colorOf(i),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              layers.nameOf(i),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
      return MouseRegion(
        onEnter: (_) => onHover(i, true),
        onExit: (_) => onHover(i, false),
        child: vertical ? RotatedBox(quarterTurns: 3, child: text) : text,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Column names, read upwards.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: _labelWidth),
            for (final c in columns)
              SizedBox(
                width: _cell,
                height: 90,
                child: name(c, vertical: true),
              ),
          ],
        ),
        for (var r = 0; r < named.length; r++)
          Row(
            children: [
              SizedBox(width: _labelWidth, child: name(named[r])),
              // Each pair once: row r against the columns down to itself.
              for (var c = 0; c < columns.length - r; c++)
                _Cell(
                  value: layers.collides(named[r], columns[c]),
                  pair: named[r] == columns[c]
                      ? '${layers.nameOf(named[r])} with itself'
                      : '${layers.nameOf(named[r])} and '
                            '${layers.nameOf(columns[c])}',
                  onChanged: (v) => onChanged(named[r], columns[c], v),
                ),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.pair,
    required this.onChanged,
  });

  final bool value;
  final String pair;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$pair: ${value ? 'collide' : 'pass through each other'}',
    waitDuration: const Duration(milliseconds: 400),
    child: InkWell(
      onTap: () => onChanged(!value),
      child: SizedBox(
        width: _GridPanel._cell,
        height: _GridPanel._cell,
        child: Icon(
          value
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
          size: 16,
          color: value ? EditorTheme.primaryMutedLight : EditorTheme.textMuted,
        ),
      ),
    ),
  );
}
