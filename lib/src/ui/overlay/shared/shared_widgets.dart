import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../settings/overlay_ui_settings.dart';

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

/// Play/Pause/Stop controls for the editor's in-scene play-test feature.
/// Editor-only — never affects the shipped game's own gameplay loop.
class PlayControlsToolbar extends StatelessWidget {
  const PlayControlsToolbar({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  /// The toolbar's height for [settings], so the minimap can leave room for
  /// it. Mirrors the layout below: a button is its icon plus 4px padding each
  /// side, the divider is 18px, and the frame adds its padding and border.
  static double heightFor(OverlayUiSettings settings) =>
      math.max(16 * settings.effectiveTextScale + 8, 18) +
      8 * settings.compactness +
      2;

  @override
  Widget build(BuildContext context) {
    return SignalConsumer(
      signals: [
        plugin.playController.state,
        plugin.designer,
        plugin.sceneState.activeScene,
        plugin.showGamePreview,
      ],
      builder: (context, _) {
        final state = plugin.playController.state.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: EditorTheme.statusBadgeBg,
            borderRadius: BorderRadius.circular(settings.cornerRadius + 6),
            border: Border.all(color: settings.themeColor, width: 1),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 6 * settings.compactness,
              vertical: 4 * settings.compactness,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _PlayControlButton(
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'Play',
                  color: const Color(0xFF7DE6B1),
                  isActive: state == EditorPlayState.playing,
                  onTap: plugin.playController.play,
                  settings: settings,
                ),
                _PlayControlButton(
                  icon: Icons.pause_rounded,
                  tooltip: 'Pause',
                  color: EditorTheme.warning,
                  isActive: state == EditorPlayState.paused,
                  onTap: state == EditorPlayState.playing
                      ? plugin.playController.pause
                      : null,
                  settings: settings,
                ),
                _PlayControlButton(
                  icon: Icons.stop_rounded,
                  tooltip: 'Stop',
                  color: EditorTheme.error,
                  isActive: false,
                  onTap: state == EditorPlayState.stopped
                      ? null
                      : plugin.playController.stop,
                  settings: settings,
                ),
                // Separated from the transport controls: this switches editing
                // mode rather than driving playback.
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: EditorTheme.border,
                ),
                _PlayControlButton(
                  icon: Icons.map_outlined,
                  tooltip: plugin.isLevelDesignerOpen
                      ? 'Close Level Designer'
                      : 'Open Level Designer',
                  color: EditorTheme.primaryBright,
                  isActive: plugin.isLevelDesignerOpen,
                  // Needs a scene: there is nothing to design into otherwise,
                  // and the session holds entity references from one.
                  onTap: plugin.sceneState.hasScene
                      ? plugin.toggleLevelDesigner
                      : null,
                  settings: settings,
                ),
                _PlayControlButton(
                  icon: Icons.picture_in_picture_alt_outlined,
                  tooltip: plugin.showGamePreview.value
                      ? 'Hide the game camera preview'
                      : 'Show the game camera preview',
                  color: EditorTheme.primaryBright,
                  isActive: plugin.showGamePreview.value,
                  onTap: () => plugin.showGamePreview.value =
                      !plugin.showGamePreview.value,
                  settings: settings,
                ),
                // What the modules add, after the built-ins.
                for (final button in plugin.scope.toolbarButtons)
                  _PlayControlButton(
                    icon: button.icon,
                    tooltip: button.tooltip,
                    color: settings.themeColor,
                    isActive: button.isActive?.call(plugin.scope) ?? false,
                    onTap: (button.isEnabled?.call(plugin.scope) ?? true)
                        ? () => button.onPressed(plugin.scope)
                        : null,
                    settings: settings,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
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

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: isActive
              ? BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Icon(
            icon,
            size: 16 * settings.effectiveTextScale,
            color: iconColor,
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
