import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../settings/overlay_ui_settings.dart';
import '../../widgets/editor_dropdown.dart';
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
/// Three groups, left to right: **transport** (Play, Pause, Step, Stop,
/// Restart, speed, and what the play-test is doing), **editing mode** (the
/// Level Designer), and **view toggles** (the game camera preview, then
/// whatever modules add). The frame takes the play state's colour, so a
/// running play-test is visible from the corner of the eye.
class PlayControlsToolbar extends StatelessWidget {
  const PlayControlsToolbar({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  static const Color _playing = Color(0xFF7DE6B1);

  /// Side of one button: a comfortable target, the height of an inspector
  /// field, growing with the text scale.
  static double buttonSize(OverlayUiSettings settings) =>
      math.max(28, 16 * settings.effectiveTextScale + 12);

  /// The toolbar's height for [settings], so whatever hangs below it — the
  /// game camera preview — knows where it ends. Mirrors the layout below: a
  /// button, the frame's vertical padding, and its border.
  static double heightFor(OverlayUiSettings settings) =>
      buttonSize(settings) + 6 * settings.compactness + 2;

  /// `Play (F5)`: the label, and the key bound to [commandId] if there is one.
  String _tip(String label, String commandId) {
    final bound = plugin.scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? label : '$label  (${bound.first.shortcut})';
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
      ],
      builder: (context, _) {
        final state = play.state.value;
        final running = state != EditorPlayState.stopped;
        final accent = switch (state) {
          EditorPlayState.playing => _playing,
          EditorPlayState.paused => EditorTheme.warning,
          EditorPlayState.stopped => settings.themeColor,
        };

        Widget button(
          IconData icon,
          String tooltip,
          Color color, {
          required VoidCallback? onTap,
          bool isActive = false,
        }) => _PlayControlButton(
          icon: icon,
          tooltip: tooltip,
          color: color,
          isActive: isActive,
          onTap: onTap,
          settings: settings,
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: EditorTheme.statusBadgeBg,
            borderRadius: BorderRadius.circular(settings.cornerRadius + 6),
            border: Border.all(color: accent, width: running ? 1.5 : 1),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 5 * settings.compactness,
            vertical: 3 * settings.compactness,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ── Transport ──────────────────────────────────────────────
              button(
                Icons.play_arrow_rounded,
                _tip(
                  state == EditorPlayState.paused ? 'Resume' : 'Play',
                  'editor.playToggle',
                ),
                _playing,
                isActive: state == EditorPlayState.playing,
                onTap: state == EditorPlayState.playing ? null : play.play,
              ),
              button(
                Icons.pause_rounded,
                _tip('Pause', 'editor.pauseToggle'),
                EditorTheme.warning,
                isActive: state == EditorPlayState.paused,
                onTap: state == EditorPlayState.playing ? play.pause : null,
              ),
              button(
                Icons.skip_next_rounded,
                _tip('Step one frame', 'editor.playStep'),
                EditorTheme.warning,
                onTap: running ? play.step : null,
              ),
              button(
                Icons.stop_rounded,
                _tip('Stop', 'editor.playToggle'),
                EditorTheme.error,
                onTap: running ? play.stop : null,
              ),
              button(
                Icons.replay_rounded,
                _tip('Restart', 'editor.playRestart'),
                _playing,
                onTap: running ? play.restart : null,
              ),
              const SizedBox(width: 4),
              EditorDropdown<double>(
                value: play.speed.value,
                tooltip: 'Play speed',
                isExpanded: false,
                height: 22,
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
                  color: accent,
                  clock: _clock(play.elapsedSeconds.value),
                ),
              const _GroupDivider(),
              // ── Editing mode ───────────────────────────────────────────
              button(
                Icons.map_outlined,
                _tip(
                  plugin.isLevelDesignerOpen
                      ? 'Close Level Designer'
                      : 'Open Level Designer',
                  'editor.toggleDesigner',
                ),
                EditorTheme.primaryBright,
                isActive: plugin.isLevelDesignerOpen,
                // Needs a scene: there is nothing to design into otherwise,
                // and the session holds entity references from one.
                onTap: plugin.sceneState.hasScene
                    ? plugin.toggleLevelDesigner
                    : null,
              ),
              const _GroupDivider(),
              // ── View toggles, then what the modules add ────────────────
              button(
                Icons.picture_in_picture_alt_outlined,
                _tip(
                  plugin.showGamePreview.value
                      ? 'Hide the game camera preview'
                      : 'Show the game camera preview',
                  'editor.togglePreview',
                ),
                EditorTheme.primaryBright,
                isActive: plugin.showGamePreview.value,
                onTap: () => plugin.showGamePreview.value =
                    !plugin.showGamePreview.value,
              ),
              for (final extra in plugin.scope.toolbarButtons)
                button(
                  extra.icon,
                  extra.tooltip,
                  settings.themeColor,
                  isActive: extra.isActive?.call(plugin.scope) ?? false,
                  onTap: (extra.isEnabled?.call(plugin.scope) ?? true)
                      ? () => extra.onPressed(plugin.scope)
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The line between two groups of controls, with more air around it than
/// there is between two buttons of one group.
class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 7),
    color: EditorTheme.border.withValues(alpha: 0.6),
  );
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

class _PlayControlButton extends StatelessWidget {
  const _PlayControlButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.isActive,
    required this.onTap,
    required this.settings,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final bool isActive;
  final VoidCallback? onTap;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final iconColor = !enabled
        ? EditorTheme.textMuted.withValues(alpha: 0.4)
        : (isActive ? color : EditorTheme.textBright);
    final side = PlayControlsToolbar.buttonSize(settings);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      // A gap between neighbours, so two active buttons read as two.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: isActive ? color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: color.withValues(alpha: 0.12),
            child: SizedBox.square(
              dimension: side,
              child: Icon(
                icon,
                size: 16 * settings.effectiveTextScale,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OverlayBadge extends StatelessWidget {
  const OverlayBadge({
    super.key,
    required this.label,
    this.accent = EditorTheme.buttonBg,
    this.settings = const OverlayUiSettings.defaults(),
  });

  final String label;
  final Color accent;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8 * settings.compactness,
          vertical: 3 * settings.compactness,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: EditorTheme.textBadge,
            fontSize: 11 * settings.effectiveTextScale,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
