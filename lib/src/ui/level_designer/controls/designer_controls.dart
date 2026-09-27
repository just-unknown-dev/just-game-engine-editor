import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/scope/editor_scope.dart';
import '../state/level_designer_controller.dart';
import '../state/map_placement.dart';
import '../tools/level_tool.dart';

// The small controls of the designer's status bar — the tool's options at
// its left and the designer's own after them — shared so both look and
// behave alike, and so a module's tool can build its options from the same
// pieces.

/// An on/off control: an icon, and a label when it has one.
class DesignerToggle extends StatelessWidget {
  const DesignerToggle({
    super.key,
    required this.icon,
    required this.isOn,
    required this.tooltip,
    required this.onTap,
    this.label,
  });

  final IconData icon;

  /// Shown beside the icon; null for an icon-only toggle, whose name is then
  /// in the tooltip.
  final String? label;
  final bool isOn;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 13,
                color: isOn ? EditorTheme.primaryBright : EditorTheme.textMuted,
              ),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isOn
                        ? EditorTheme.textBright
                        : EditorTheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A [DesignerToggle] for a boolean signal.
class SignalToggle extends StatelessWidget {
  const SignalToggle({
    super.key,
    required this.signal,
    required this.icon,
    required this.tooltip,
    this.label,
  });

  final Signal<bool> signal;
  final IconData icon;
  final String? label;
  final String tooltip;

  @override
  Widget build(BuildContext context) => SignalBuilder<bool>(
    signal: signal,
    builder: (context, on, _) => DesignerToggle(
      icon: icon,
      label: label,
      isOn: on,
      tooltip: tooltip,
      onTap: () => signal.value = !on,
    ),
  );
}

/// One of the choices of a [ChoicePicker].
class ToolChoice<T> {
  const ToolChoice({
    required this.value,
    required this.icon,
    required this.label,
    this.tooltip,
  });

  final T value;
  final IconData icon;
  final String label;

  /// Defaults to [label].
  final String? tooltip;
}

/// A row of toggles of which exactly one is on: the value of [signal].
class ChoicePicker<T> extends StatelessWidget {
  const ChoicePicker({super.key, required this.signal, required this.options});

  final Signal<T> signal;
  final List<ToolChoice<T>> options;

  @override
  Widget build(BuildContext context) => SignalBuilder<T>(
    signal: signal,
    builder: (context, value, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          DesignerToggle(
            icon: option.icon,
            label: option.label,
            isOn: value == option.value,
            tooltip: option.tooltip ?? option.label,
            onTap: () => signal.value = option.value,
          ),
      ],
    ),
  );
}

/// The width of a brush, in cells: 1, 3 or 5.
class BrushSizePicker extends StatelessWidget {
  const BrushSizePicker({
    super.key,
    required this.signal,
    this.noun = 'brush',
    this.sizes = const [1, 3, 5],
  });

  final Signal<int> signal;

  /// What the tooltips call it: 'brush', 'eraser'.
  final String noun;
  final List<int> sizes;

  @override
  Widget build(BuildContext context) => SignalBuilder<int>(
    signal: signal,
    builder: (context, size, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in sizes)
          DesignerToggle(
            icon: Icons.grid_on,
            label: '$option',
            isOn: size == option,
            tooltip: '$option × $option $noun  ([ and ])',
            onTap: () => signal.value = option,
          ),
      ],
    ),
  );
}

/// The thin upright line between two sets of options.
class OptionsDivider extends StatelessWidget {
  const OptionsDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 8),
    color: EditorTheme.textMuted.withValues(alpha: 0.25),
  );
}

/// A short caption before a set of options, e.g. "Size".
class OptionsLabel extends StatelessWidget {
  const OptionsLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, right: 4),
    child: Text(
      text,
      style: const TextStyle(color: EditorTheme.textMuted, fontSize: 10),
    ),
  );
}

/// The prefab the Draw and Paint tools place, in its colour; the PREFABS
/// section picks another.
class ActivePrefabChip extends StatelessWidget {
  const ActivePrefabChip({super.key, required this.controller});

  final LevelDesignerController controller;

  @override
  Widget build(BuildContext context) => SignalBuilder<String?>(
    signal: controller.activePrefabId,
    builder: (context, _, _) {
      final prefab = controller.activePrefab;
      return Tooltip(
        message: 'What is placed: pick another in PREFABS',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (prefab?.color ?? EditorTheme.textMuted).withValues(
              alpha: 0.14,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                prefab?.icon ?? Icons.block,
                size: 13,
                color: prefab?.color ?? EditorTheme.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                prefab?.name ?? 'No prefab',
                style: const TextStyle(
                  fontSize: 11,
                  color: EditorTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Where what the Draw and Paint tools make goes: under the Level Map, on
/// which of its layers — or a new one, or a new map.
class PlacementChip extends StatelessWidget {
  const PlacementChip({super.key, required this.options});

  final ToolOptionsContext options;

  @override
  Widget build(BuildContext context) {
    final controller = options.controller;
    final scope = options.scope;
    return SignalBuilder3<String?, String, int>(
      signal1: controller.activePrefabId,
      signal2: controller.activeLayerId,
      signal3: scope.mapDocs.revision,
      builder: (context, _, depth, _, _) => SignalBuilder<int?>(
        signal: scope.tiles.layerId,
        builder: (context, _, _) {
          final prefab = controller.activePrefab;
          final text = prefab == null
              ? ''
              : '→ ${MapPlacement.describe(scope, options.world, prefab.depth ?? depth)}';
          return Tooltip(
            message:
                'What is placed goes under the level\'s map, on the layer '
                'at the depth being placed at',
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                color: EditorTheme.textMuted,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The map layer being painted, and a menu to paint another.
class MapLayerPicker extends StatelessWidget {
  const MapLayerPicker({super.key, required this.scope, required this.world});

  final EditorScope scope;
  final jge.World world;

  @override
  Widget build(BuildContext context) {
    final tiles = scope.tiles;
    return SignalBuilder2<int?, int?>(
      signal1: tiles.mapEntityId,
      signal2: tiles.layerId,
      builder: (context, _, layerId, _) {
        // Looks without choosing one: a picker only shows.
        final target = tiles.peek(world);
        final layers = target?.data.layers ?? const <jge.MapLayerData>[];
        final layer =
            target?.data.layerById(layerId ?? -1) ??
            (layers.isEmpty ? null : layers.last);
        final text = target == null
            ? 'No map'
            : layer == null
            ? 'No layers'
            : layer.name;
        return PopupMenuButton<int>(
          tooltip: 'The layer being painted',
          enabled: layers.isNotEmpty,
          color: EditorTheme.menuBg,
          // At the foot of the window: over the button, kept on screen.
          position: PopupMenuPosition.over,
          onSelected: (id) => tiles.layerId.value = id,
          itemBuilder: (context) => [
            // Top layer first, as the layers panel lists them.
            for (final l in layers.reversed)
              PopupMenuItem(
                value: l.id,
                height: 28,
                child: Row(
                  children: [
                    Icon(
                      l.locked
                          ? Icons.lock_outline
                          : l.visible
                          ? Icons.layers_outlined
                          : Icons.visibility_off_outlined,
                      size: 13,
                      color: EditorTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: l.id == layer?.id
                            ? EditorTheme.textPrimary
                            : EditorTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.layers,
                  size: 13,
                  color: EditorTheme.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: EditorTheme.textSecondary,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: EditorTheme.textSecondary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A line of muted text, and perhaps a button, in an empty tile panel.
class TilePanelMessage extends StatelessWidget {
  const TilePanelMessage({super.key, required this.text, this.action});

  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 11, color: EditorTheme.textMuted),
        ),
        if (action != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: action!.$2,
            icon: const Icon(Icons.grid_on, size: 14),
            label: Text(action!.$1, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ],
    ),
  );
}
