/// A row per setting, as the settings dialog lays them out. The controls in
/// them are the editor's kit, given the accent being picked so the dialog
/// previews it.
library;

import 'package:flutter/material.dart';

import '../../../core/constants/editor_constants.dart';
import '../../kit/kit.dart';

/// One setting: what it is and a line on what it does, its control on the
/// right, and a way back to the default once it has moved from it.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    required this.hint,
    required this.control,
    required this.accent,
    this.isModified = false,
    this.onReset,
  });

  final String label;
  final String hint;
  final Widget control;
  final Color accent;
  final bool isModified;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final controlWidth = (box.maxWidth * 0.45).clamp(160.0, 320.0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: EditorTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isModified) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Changed from the default',
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: TextStyle(
                      color: EditorTheme.textMuted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: controlWidth,
              child: Align(alignment: Alignment.centerRight, child: control),
            ),
            const SizedBox(width: 6),
            // Always the same room, so the controls line up whether or not
            // a row has moved from its default.
            SizedBox.square(
              dimension: 26,
              child: isModified && onReset != null
                  ? EditorIconButton(
                      icon: Icons.restart_alt_rounded,
                      tooltip: 'Back to the default',
                      activeColor: accent,
                      onTap: onReset,
                    )
                  : null,
            ),
          ],
        ),
      );
    },
  );
}
