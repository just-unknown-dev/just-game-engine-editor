part of 'editor_overlay.dart';

String _formatBytes(int bytes) {
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

class _EditorStatusBadge extends StatelessWidget {
  const _EditorStatusBadge({required this.settings});

  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EditorTheme.statusBadgeBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius + 6),
        border: Border.all(color: settings.themeColor, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * settings.compactness,
          vertical: 8 * settings.compactness,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.visibility_rounded,
              size: 14 * settings.effectiveTextScale,
              color: EditorTheme.textBright,
            ),
            const SizedBox(width: 6),
            Text(
              'EDITOR: OPEN',
              style: TextStyle(
                fontSize: 11 * settings.effectiveTextScale,
                fontWeight: FontWeight.w700,
                color: EditorTheme.textBright,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play/Pause/Stop controls for the editor's in-scene play-test feature.
/// Editor-only — never affects the shipped game's own gameplay loop.
class _PlayControlsToolbar extends StatelessWidget {
  const _PlayControlsToolbar({required this.plugin, required this.settings});

  final JustGameEditorPlugin plugin;
  final _OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: plugin,
      builder: (context, _) {
        final state = plugin.playState;
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
                  onTap: plugin.play,
                  settings: settings,
                ),
                _PlayControlButton(
                  icon: Icons.pause_rounded,
                  tooltip: 'Pause',
                  color: EditorTheme.warning,
                  isActive: state == EditorPlayState.paused,
                  onTap: state == EditorPlayState.playing ? plugin.pause : null,
                  settings: settings,
                ),
                _PlayControlButton(
                  icon: Icons.stop_rounded,
                  tooltip: 'Stop',
                  color: EditorTheme.error,
                  isActive: false,
                  onTap: state == EditorPlayState.stopped ? null : plugin.stop,
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
  final _OverlayUiSettings settings;

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

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.accent = EditorTheme.buttonBg,
    this.settings = const _OverlayUiSettings.defaults(),
  });

  final String label;
  final Color accent;
  final _OverlayUiSettings settings;

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
