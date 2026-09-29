import 'package:flutter/material.dart';

import '../../../core/constants/editor_constants.dart';

/// The frame the editor's big dialogs share — the sprite editor, the
/// interface and tileset editors, the settings: the editor dimmed behind,
/// and the dialog over it with room to spare at the edges, so opening one
/// does not feel like leaving.
///
/// Below [roomyEnough] there is no room to spare and the dialog fills the
/// editor instead; so does a [filled] one.
class EditorDialogFrame extends StatelessWidget {
  const EditorDialogFrame({
    super.key,
    required this.child,
    this.filled = false,
    this.cornerRadius = 12,
    this.borderColor,
    this.onDismiss,
    this.scrimKey,
  });

  final Widget child;
  final bool filled;
  final double cornerRadius;

  /// The frame's line; the editor's faint border when null.
  final Color? borderColor;

  /// Called for a click on the dim. Null keeps the click from doing
  /// anything: closing is then the dialog's own button, which can ask about
  /// unsaved work first.
  final VoidCallback? onDismiss;

  /// Keys the dim, for a test to find.
  final Key? scrimKey;

  /// Room left around the dialog, so the editor shows at its edges.
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 40,
    vertical: 28,
  );

  /// Below this there is no room to spare for a margin: the dialog fills.
  static const Size roomyEnough = Size(1100, 640);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final asDialog =
          !filled &&
          box.maxWidth >= roomyEnough.width &&
          box.maxHeight >= roomyEnough.height;
      if (!asDialog) {
        return ColoredBox(color: EditorTheme.dialogBg, child: child);
      }
      final radius = BorderRadius.circular(cornerRadius);
      return Stack(
        children: [
          // The dim takes clicks, so nothing behind is pressed by accident.
          Positioned.fill(
            child: ModalBarrier(
              key: scrimKey,
              dismissible: onDismiss != null,
              onDismiss: onDismiss,
              color: const Color(0x99000000),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: margin,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xAA000000),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(
                        color: borderColor ?? EditorTheme.border,
                      ),
                    ),
                    child: ColoredBox(
                      color: EditorTheme.dialogBg,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
