import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../settings/overlay_ui_settings.dart';
import '../../widgets/editor_dropdown.dart';
import '../../kit/buttons.dart';
import 'transform_toolbar.dart';
import '../../../core/play/play_controller.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }

  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final precision = unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
}

/// Play-test and view controls for the editor, top-left of the viewport.
/// Editor-only — never affects the shipped game's own gameplay loop.
///
/// Three frames, left to right: **transport** (Play, Pause, Step, Stop,
/// Restart, the speed, and what the play-test is doing), **view and mode**
/// (the game camera preview and the Level Designer), and what **modules**
/// add, each parted from the next. The frames take the play state's colour, so a
/// running play-test is visible from the corner of the eye. Narrower than
/// [maxWidth], the row scrolls sideways rather than run into what is at the
/// top right.
class PlayControlsToolbar extends StatelessWidget {
  const PlayControlsToolbar({
    super.key,
    required this.plugin,
    required this.settings,
    this.maxWidth,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  /// How wide the row may be before it scrolls.
  final double? maxWidth;

  static Color get _playing => EditorTheme.success;

  /// Side of one button: a comfortable target, the height of an inspector
  /// field, growing with the text scale.
  static double buttonSize(OverlayUiSettings settings) =>
      math.max(EditorMetrics.controlMd, 16 * settings.effectiveTextScale + 12);

  /// The toolbar's height for [settings], so whatever hangs below it — the
  /// game camera preview — knows where it ends. Mirrors the layout below: a
  /// button, the frame's vertical padding, and its border.
  static double heightFor(OverlayUiSettings settings) =>
      buttonSize(settings) + EditorMetrics.space(6) + 2;

  /// The key bound to [commandId], if there is one.
  String? _key(String commandId) {
    final bound = plugin.scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  static String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final play = plugin.playController;
    return SignalConsumer(
      signals: [
        play.state,
        play.speed,
        play.elapsedSeconds,
        plugin.designer,
        plugin.sceneState.activeScene,
        plugin.showGamePreview,
        // A module button lit while its workspace is open (`isActive`) has
        // to hear the workspace open and close.
        plugin.scope.activeWorkspace,
      ],
      builder: (context, _) {
        final state = play.state.value;
        final running = state != EditorPlayState.stopped;
        final frameColour = switch (state) {
          EditorPlayState.playing => _playing,
          EditorPlayState.paused => EditorTheme.warning,
          EditorPlayState.stopped => EditorTheme.accent,
        };
        final hasScene = plugin.sceneState.hasScene;
        // With no scene open there is nothing to play or to look at: only
        // the modules' tools, which need none, stay.
        final levelTools = hasScene || running;
        final side = buttonSize(settings);

        Widget button(
          IconData icon,
          String tooltip,
          Color colour, {
          required VoidCallback? onTap,
          String? commandId,
          bool isActive = false,
        }) => Padding(
          // A gap between neighbours, so two lit buttons read as two.
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: EditorToolButton(
            icon: icon,
            tooltip: tooltip,
            shortcut: commandId == null ? null : _key(commandId),
            showShortcut: false,
            activeBar: false,
            activeColor: colour,
            isActive: isActive,
            onTap: onTap,
            width: side,
            height: side,
            iconSize: 16 * settings.effectiveTextScale,
          ),
        );

        Widget frame(List<Widget> children) => FloatingToolFrame(
          settings: settings,
          borderColor: frameColour,
          borderWidth: running ? 1.5 : 1,
          horizontalPadding: EditorMetrics.space(5),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        );

        final modules = plugin.scope.toolbarButtons;
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          spacing: EditorMetrics.space(4),
          children: [
            // ── Transport ──────────────────────────────────────────────
            if (levelTools)
              frame([
                button(
                  Icons.play_arrow_rounded,
                  state == EditorPlayState.paused ? 'Resume' : 'Play',
                  _playing,
                  commandId: 'editor.playToggle',
                  isActive: state == EditorPlayState.playing,
                  onTap: state == EditorPlayState.playing ? null : play.play,
                ),
                button(
                  Icons.pause_rounded,
                  'Pause',
                  EditorTheme.warning,
                  commandId: 'editor.pauseToggle',
                  isActive: state == EditorPlayState.paused,
                  onTap: state == EditorPlayState.playing ? play.pause : null,
                ),
                button(
                  Icons.skip_next_rounded,
                  'Step one frame',
                  EditorTheme.warning,
                  commandId: 'editor.playStep',
                  onTap: running ? play.step : null,
                ),
                button(
                  Icons.stop_rounded,
                  'Stop',
                  EditorTheme.error,
                  commandId: 'editor.playToggle',
                  onTap: running ? play.stop : null,
                ),
                button(
                  Icons.replay_rounded,
                  'Restart',
                  _playing,
                  commandId: 'editor.playRestart',
                  onTap: running ? play.restart : null,
                ),
                const SizedBox(width: 4),
                EditorDropdown<double>(
                  value: play.speed.value,
                  tooltip: 'Play speed',
                  isExpanded: false,
                  height: 24,
                  fontSize: 10,
                  options: [
                    for (final speed in PlayController.speeds)
                      EditorDropdownOption(
                        value: speed,
                        label:
                            '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
                      ),
                  ],
                  onChanged: play.setSpeed,
                ),
                if (running)
                  _StateChip(
                    state: state,
                    color: frameColour,
                    clock: _clock(play.elapsedSeconds.value),
                  ),
                const SizedBox(width: 2),
              ]),
            // ── View and mode ──────────────────────────────────────────
            // What the viewport shows and what it is for: the game camera
            // over the level, the level being built, or the interface
            // drawn over it.
            if (levelTools)
              frame([
                button(
                  Icons.camera,
                  plugin.showGamePreview.value
                      ? 'Hide the game camera preview'
                      : 'Show the game camera preview',
                  EditorTheme.primaryBright,
                  commandId: 'editor.togglePreview',
                  isActive: plugin.showGamePreview.value,
                  onTap: () => plugin.showGamePreview.value =
                      !plugin.showGamePreview.value,
                ),
                button(
                  Icons.map_outlined,
                  plugin.isLevelDesignerOpen
                      ? 'Close Level Designer'
                      : 'Open Level Designer',
                  EditorTheme.primaryBright,
                  commandId: 'editor.toggleDesigner',
                  isActive: plugin.isLevelDesignerOpen,
                  // Needs a scene: there is nothing to design into otherwise,
                  // and the session holds entity references from one.
                  onTap: hasScene ? plugin.toggleLevelDesigner : null,
                ),
              ]),
            // ── What the modules add ───────────────────────────────────
            if (modules.isNotEmpty)
              frame([
                for (int i = 0; i < modules.length; i++)
                  Row(
                    children: [
                      button(
                        modules[i].icon,
                        modules[i].tooltip,
                        EditorTheme.accent,
                        isActive:
                            modules[i].isActive?.call(plugin.scope) ?? false,
                        onTap:
                            (modules[i].isEnabled?.call(plugin.scope) ?? true)
                            ? () => modules[i].onPressed(plugin.scope)
                            : null,
                      ),
                      if (modules.length > 1 && i < modules.length - 1)
                        Container(
                          width: 1,
                          height: side * 0.6,
                          margin: EdgeInsets.symmetric(
                            horizontal: EditorMetrics.space(4),
                          ),
                          color: EditorTheme.accent,
                        ),
                    ],
                  ),
              ]),
          ],
        );
        final limit = maxWidth;
        if (limit == null) return row;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.max(limit, side * 2)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: row,
          ),
        );
      },
    );
  }
}

/// `● PLAYING 00:12` — what the play-test is doing, and for how long.
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.state,
    required this.color,
    required this.clock,
  });

  final EditorPlayState state;
  final Color color;
  final String clock;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          state == EditorPlayState.paused ? 'PAUSED' : 'PLAYING',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          clock,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
