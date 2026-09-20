import 'package:flutter/material.dart';

import '../../../core/constants/editor_constants.dart';
import '../settings/overlay_ui_settings.dart';

/// A draggable horizontal handle for resizing panels.
///
/// [onDrag] receives the vertical delta on each drag update — negative when
/// the user drags upward (expanding the panel below). Callers are responsible
/// for clamping the resulting size.
class PanelResizeHandle extends StatelessWidget {
  const PanelResizeHandle({super.key, required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onDrag(details.delta.dy),
        child: Container(
          height: 12,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class DetailStatTile extends StatelessWidget {
  const DetailStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.settings,
  });

  final String label;
  final String value;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: EditorTheme.surfaceBg,
        borderRadius: BorderRadius.circular(settings.cornerRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            spacing: 8,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11 * settings.effectiveTextScale,
                  color: EditorTheme.textMuted,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12 * settings.effectiveTextScale,
                  fontWeight: FontWeight.w700,
                  color: EditorTheme.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
