import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../core/physics/physics_bodies.dart';
import '../overlay/docks/shell/built_in_docks.dart' show BuiltInDocks;
import '../../core/scope/editor_scope_services.dart';

/// Inspector editors for collision layers, made like the tag pickers: a
/// layer picked by name — or made there and then — and the layers a body
/// collides with as chips to switch on and off.
abstract final class PhysicsFieldEditors {
  static Map<String, FieldEditorBuilder> get all => {
    jge.FieldTypes.physicsLayer.id: (c) => PhysicsLayerField(ctx: c),
    jge.FieldTypes.physicsLayerMask.id: (c) => PhysicsLayerMaskField(ctx: c),
  };

  /// The colour [layer] is shown in, by the project's layers.
  static Color colorOf(EditorScope? scope, int layer) =>
      (scope?.physicsLayers.value ?? jge.PhysicsLayers.defaults).colorOf(layer);

  /// Opens the dock where layers are named and the grid is set.
  static void openDock(EditorScope? scope) =>
      scope?.dockController.open(BuiltInDocks.physics);

  // The counts per scene revision: every layer field asks on every build,
  // and each count walks every body in the scene.
  static final Expando<(int, jge.World, List<int>)> _counts = Expando(
    'physicsBodyCounts',
  );

  /// How many bodies, 2-D and 3-D, in [scope]'s scene are on each layer —
  /// counted once per change to the scene.
  static List<int> bodyCounts(EditorScope? scope) {
    if (scope == null) return List.filled(jge.PhysicsLayers.count, 0);
    final revision = scope.sceneState.revision.value;
    final world = scope.world;
    final known = _counts[scope];
    if (known != null && known.$1 == revision && identical(known.$2, world)) {
      return known.$3;
    }
    final counts = List<int>.unmodifiable([
      for (final bodies in PhysicsBodies.byLayer(world, scope.definitions))
        bodies.length,
    ]);
    _counts[scope] = (revision, world, counts);
    return counts;
  }

  /// `3 bodies`, `1 body`, or nothing.
  static String bodiesLabel(int n) =>
      n == 0 ? 'unused here' : (n == 1 ? '1 body' : '$n bodies');

  /// [label] beside [child], as every inspector row is laid out.
  static Widget labelled(String label, Widget child) => Row(
    children: [
      SizedBox(
        width: InspectorField.labelWidth,
        child: Text(label, style: InspectorField.labelStyle),
      ),
      Expanded(child: child),
    ],
  );
}

/// Rings a layer's bodies in the viewport while something points at it.
abstract final class LayerHighlight {
  static void set(EditorScope? scope, int layer, bool on) {
    if (scope == null) return;
    if (on) {
      scope.highlightedLayer.value = layer;
    } else if (scope.highlightedLayer.value == layer) {
      scope.highlightedLayer.value = null;
    }
  }
}

/// Follows the project's layers, where there is a project.
class _LayersBuilder extends StatelessWidget {
  const _LayersBuilder({required this.scope, required this.builder});

  final EditorScope? scope;
  final Widget Function(BuildContext context, jge.PhysicsLayers layers) builder;

  @override
  Widget build(BuildContext context) {
    final scope = this.scope;
    if (scope == null) return builder(context, jge.PhysicsLayers.defaults);
    return SignalBuilder<jge.PhysicsLayers>(
      signal: scope.physicsLayers.layers,
      builder: (context, layers, _) => builder(context, layers),
    );
  }
}

/// One collision layer, picked by name — each with its colour and how many
/// bodies are on it — or typed in to make a new one. The last entry opens
/// the Physics Layers dock.
class PhysicsLayerField extends StatelessWidget {
  const PhysicsLayerField({super.key, required this.ctx});

  final FieldEditorContext ctx;

  /// The picker's key for "Edit layers…".
  static const String _edit = '\u0000edit';

  /// The picker's key for a layer with no name.
  static String _unnamedKey(int layer) => '\u0000#$layer';

  @override
  Widget build(BuildContext context) => _LayersBuilder(
    scope: ctx.scope,
    builder: (context, layers) {
      final current = (ctx.value as num?)?.toInt() ?? 0;
      if (ctx.readOnly) {
        return ReadonlyRow(label: ctx.label, value: layers.labelOf(current));
      }
      final scope = ctx.scope;
      final counts = PhysicsFieldEditors.bodyCounts(scope);
      final currentKey = layers.isNamed(current)
          ? layers.nameOf(current)
          : _unnamedKey(current);
      return PhysicsFieldEditors.labelled(
        ctx.label,
        MouseRegion(
          onEnter: (_) => LayerHighlight.set(scope, current, true),
          onExit: (_) => LayerHighlight.set(scope, current, false),
          child: EditorDropdown<String>(
            value: currentKey,
            // Typing filters, and a name that is no layer yet makes one.
            searchable: scope != null,
            options: [
              for (final i in layers.named)
                EditorDropdownOption(
                  value: layers.nameOf(i),
                  label: layers.nameOf(i),
                  color: layers.colorOf(i),
                  detail: PhysicsFieldEditors.bodiesLabel(counts[i]),
                ),
              if (!layers.isNamed(current))
                EditorDropdownOption(
                  value: _unnamedKey(current),
                  label: layers.labelOf(current),
                  color: layers.colorOf(current),
                  detail: 'has no name',
                ),
              if (scope != null)
                const EditorDropdownOption(value: _edit, label: 'Edit layers…'),
            ],
            customValue: scope == null ? null : (typed) => typed,
            customLabel: scope == null
                ? null
                : (typed) =>
                      scope.physicsLayers.problemWithNew(typed) ??
                      'Create layer "$typed"',
            onChanged: (picked) {
              if (picked == _edit) {
                PhysicsFieldEditors.openDock(scope);
                return;
              }
              if (picked == currentKey) return;
              final known = layers.indexOf(picked);
              final layer = known ?? scope?.physicsLayers.create(picked.trim());
              if (layer != null && layer != current) {
                // The ring is on the layer the pointer came in over; once
                // the field shows the new one, leaving would clear that
                // instead, and the old one would stay ringed.
                LayerHighlight.set(scope, current, false);
                ctx.onChanged(layer);
              }
            },
          ),
        ),
      );
    },
  );
}

/// The layers a body collides with, as one chip per named layer to switch
/// on and off.
///
/// Until one is switched, they show what the project's grid says for the
/// body's layer (`collidesWith` is null). Switching one gives the body its
/// own list; switching it back to what the grid says goes back to the grid.
/// A chip warns when the body lists a layer whose grid row does not list
/// the body's layer: a contact needs both, so those two never touch.
class PhysicsLayerMaskField extends StatelessWidget {
  const PhysicsLayerMaskField({super.key, required this.ctx});

  final FieldEditorContext ctx;

  /// The layer of the body the field belongs to, for what the grid says:
  /// its component's own layer field, whichever body it is.
  int get _ownLayer {
    final component = ctx.component;
    final definition = ctx.scope?.definitions.definitionFor(component);
    for (final f in definition?.fields ?? const <jge.SchemaField>[]) {
      if (f.kind == jge.FieldTypes.physicsLayer) {
        return (f.read(component) as num?)?.toInt() ?? 0;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) => _LayersBuilder(
    scope: ctx.scope,
    builder: (context, layers) => _build(context, layers),
  );

  Widget _build(BuildContext context, jge.PhysicsLayers layers) {
    final scope = ctx.scope;
    final own = _ownLayer;
    final grid = layers.maskOf(own);
    final custom = (ctx.value as num?)?.toInt();
    final mask = custom ?? grid;
    final named = layers.named.toList();
    final editable = !ctx.readOnly;

    void toggle(int layer) {
      final next = (mask ^ (1 << layer)) & jge.PhysicsLayers.all;
      // Back to what the grid says: follow the grid again.
      ctx.onChanged(next == grid ? null : next);
    }

    final chips = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final i in named)
          _LayerToggleChip(
            label: layers.nameOf(i),
            color: layers.colorOf(i),
            on: (mask >> i) & 1 == 1,
            // Listed here, but its own row leaves this body's layer out.
            oneSided: (mask >> i) & 1 == 1 && !layers.collides(i, own),
            oneSidedTip:
                '${layers.nameOf(i)} does not collide with '
                '${layers.labelOf(own)} in the Physics Layers grid, so these '
                'never touch. Tick the pair there to make them.',
            onTap: editable ? () => toggle(i) : null,
            onHover: (inside) => LayerHighlight.set(scope, i, inside),
          ),
      ],
    );

    final status = custom == null
        ? (
            named.length < 2
                ? 'Everything collides — name layers to choose what does'
                : 'As the grid says for ${layers.labelOf(own)}',
            named.length < 2 ? 'Physics Layers' : 'Edit grid',
            () => PhysicsFieldEditors.openDock(scope),
          )
        : ('Its own list', 'Use the grid', () => ctx.onChanged(null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: InspectorField.labelWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(ctx.label, style: InspectorField.labelStyle),
              ),
            ),
            Expanded(child: chips),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: InspectorField.labelWidth),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                custom == null ? Icons.grid_on_rounded : Icons.tune_rounded,
                size: 11,
                color: EditorTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                status.$1,
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
              ),
              if (scope != null && (custom == null || editable)) ...[
                Text(
                  '  ·  ',
                  style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
                ),
                InkWell(
                  onTap: status.$3,
                  child: Text(
                    status.$2,
                    style: TextStyle(
                      color: EditorTheme.primaryMutedLight,
                      fontSize: 10,
                      decoration: TextDecoration.underline,
                      decorationColor: EditorTheme.primaryMutedLight,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A layer that is on (filled, in its colour) or off (an outline), switched
/// by a click.
class _LayerToggleChip extends StatelessWidget {
  const _LayerToggleChip({
    required this.label,
    required this.color,
    required this.on,
    required this.onTap,
    this.oneSided = false,
    this.oneSidedTip = '',
    this.onHover,
  });

  final String label;
  final Color color;
  final bool on;
  final bool oneSided;
  final String oneSidedTip;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: on ? color.withValues(alpha: 0.7) : EditorTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: on ? color : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.2),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: on ? EditorTheme.textPrimary : EditorTheme.textMuted,
              fontSize: 11,
              decoration: on ? null : TextDecoration.lineThrough,
              decorationColor: EditorTheme.textMuted,
            ),
          ),
          if (oneSided) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.warning_amber_rounded,
              size: 12,
              color: EditorTheme.warning,
            ),
          ],
        ],
      ),
    );
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: onHover == null ? null : (_) => onHover!(true),
      onExit: onHover == null ? null : (_) => onHover!(false),
      child: Tooltip(
        message: oneSided
            ? oneSidedTip
            : on
            ? 'Collides with $label${onTap == null ? '' : ' — click to stop'}'
            : 'Passes through $label${onTap == null ? '' : ' — click to collide'}',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(onTap: onTap, child: chip),
      ),
    );
  }
}
