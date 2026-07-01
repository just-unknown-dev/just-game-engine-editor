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
