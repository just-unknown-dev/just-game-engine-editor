import 'package:flutter/material.dart';

import 'focus.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';

/// `Label  (Ctrl+S)`: a tooltip with the key that does the same, when there
/// is one.
String tooltipWithShortcut(String tooltip, String? shortcut) =>
    shortcut == null || shortcut.isEmpty ? tooltip : '$tooltip  ($shortcut)';

/// A small square icon button — the editor's one.
///
/// [color] tints the icon — a red Delete is red — and lights the button
/// while [isActive]; [activeColor] lights it without tinting the icon at
/// rest. A null [onTap] greys it out: that is how a button says it has
/// nothing to do. Never smaller than [EditorMetrics.minTarget].
class EditorIconButton extends StatelessWidget {
  const EditorIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.color,
    this.activeColor,
    this.size,
    this.iconSize,
    this.shortcut,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? color;
  final Color? activeColor;

  /// The button's side; [EditorMetrics.controlSm] when null.
  final double? size;
  final double? iconSize;

  /// The key that does the same, added to the tooltip.
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final lit = activeColor ?? color ?? EditorTheme.primaryBright;
    final side = size ?? EditorMetrics.controlSm;
    return Tooltip(
      message: tooltipWithShortcut(tooltip, shortcut),
      child: Semantics(
        button: true,
        enabled: onTap != null,
        toggled: isActive ? true : null,
        child: FocusOutline(
          child: Material(
            color: isActive ? lit.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(EditorMetrics.radiusSm + 1),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              hoverColor: lit.withValues(alpha: 0.10),
              child: SizedBox.square(
                dimension: side,
                child: Icon(
                  icon,
                  size: iconSize ?? (side * 0.58).clamp(12.0, 18.0),
                  color: onTap == null
                      ? EditorTheme.textMuted.withValues(alpha: 0.4)
                      : isActive
                      ? lit
                      : color ?? EditorTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A toolbar's tool: bigger than an icon button, with the key that picks it
/// in its corner — because the keys are what anyone doing this repeatedly
/// will use; the buttons are for finding them. The tool in hand is filled
/// and has a bar down its left edge.
class EditorToolButton extends StatefulWidget {
  const EditorToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.activeColor,
    this.shortcut,
    this.showShortcut = true,
    this.cornerLabel,
    this.width,
    this.height,
    this.iconSize,
    this.activeBar = true,
    this.glyph,
    this.onSecondaryTap,
  });

  final IconData icon;
  final String tooltip;

  /// Null greys it out.
  final VoidCallback? onTap;
  final bool isActive;

  /// What the tool in hand is lit with; the accent when null.
  final Color? activeColor;

  /// The key that picks it: in the tooltip, and in the corner.
  final String? shortcut;

  /// Whether the key shows in the corner as well as in the tooltip.
  final bool showShortcut;

  /// What the corner shows instead of [shortcut] — for a caller whose
  /// tooltip already names the key.
  final String? cornerLabel;

  /// The button's size; [EditorMetrics.controlMd] square when null.
  final double? width;
  final double? height;
  final double? iconSize;

  /// The bar down the left edge of the tool in hand.
  final bool activeBar;

  /// Draws the button's picture instead of [icon], in the colour and at
  /// the size the icon would have — for a sign Material has no icon for.
  final Widget Function(Color colour, double size)? glyph;

  /// A right-click: more of what the button does — its options.
  final VoidCallback? onSecondaryTap;

  @override
  State<EditorToolButton> createState() => _EditorToolButtonState();
}

class _EditorToolButtonState extends State<EditorToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final active = widget.isActive;
    final lit = widget.activeColor ?? EditorTheme.primaryBright;
    final side = EditorMetrics.controlMd;
    final iconColor = !enabled
        ? EditorTheme.textMuted.withValues(alpha: 0.4)
        : active
        ? lit
        : _hover
        ? EditorTheme.textPrimary
        : EditorTheme.textSecondary;
    final shortcut = widget.shortcut;
    final corner =
        widget.cornerLabel ?? (widget.showShortcut ? shortcut : null);
    return Tooltip(
      message: tooltipWithShortcut(widget.tooltip, shortcut),
      child: Semantics(
        button: true,
        enabled: enabled,
        selected: active,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: FocusOutline(
            radius: EditorMetrics.radiusSm + 2,
            child: FocusableActionDetector(
              enabled: enabled,
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onTap?.call();
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onSecondaryTap: widget.onSecondaryTap,
                child: AnimatedContainer(
                  duration: EditorMetrics.motionFast,
                  width: widget.width ?? side,
                  height: widget.height ?? side,
                  decoration: BoxDecoration(
                    color: active
                        ? lit.withValues(alpha: 0.18)
                        : _hover && enabled
                        ? EditorTheme.hoverBg
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      EditorMetrics.radiusSm + 2,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (active && widget.activeBar)
                        Positioned(
                          left: 0,
                          top: 5,
                          bottom: 5,
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(
                              color: lit,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      Center(
                        child:
                            widget.glyph?.call(
                              iconColor,
                              widget.iconSize ?? 17,
                            ) ??
                            Icon(
                              widget.icon,
                              size: widget.iconSize ?? 17,
                              color: iconColor,
                            ),
                      ),
                      if (corner != null)
                        Positioned(
                          right: 3,
                          bottom: 1,
                          child: Text(
                            corner,
                            style: TextStyle(
                              color: active
                                  ? EditorTheme.primaryMutedLight
                                  : EditorTheme.textMuted,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a text button is for.
enum EditorButtonKind {
  /// The one thing to do here: filled with the accent.
  primary,

  /// Another thing to do: outlined.
  secondary,

  /// Something that loses work: red.
  danger,

  /// Text only, for Cancel and the like.
  ghost,
}

/// A button with words on it, in the editor's colours whatever the ambient
/// Material theme is.
class EditorButton extends StatelessWidget {
  const EditorButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = EditorButtonKind.secondary,
    this.icon,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EditorButtonKind kind;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color? bg, Color? side) = switch (kind) {
      EditorButtonKind.primary => (
        EditorTheme.textBright,
        EditorTheme.primaryActive,
        null,
      ),
      EditorButtonKind.secondary => (
        EditorTheme.primaryBright,
        EditorTheme.buttonBg,
        EditorTheme.borderStrong,
      ),
      EditorButtonKind.danger => (EditorTheme.error, null, EditorTheme.error),
      EditorButtonKind.ghost => (EditorTheme.textSecondary, null, null),
    };
    final style = TextButton.styleFrom(
      foregroundColor: fg,
      backgroundColor: bg,
      disabledForegroundColor: EditorTheme.textMuted.withValues(alpha: 0.5),
      minimumSize: Size(0, EditorMetrics.fieldHeight),
      padding: EdgeInsets.symmetric(horizontal: EditorMetrics.gapXl),
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorMetrics.radiusSm + 1),
        side: side == null
            ? BorderSide.none
            : BorderSide(color: side.withValues(alpha: 0.7)),
      ),
    );
    final text = Text(label);
    return FocusOutline(
      child: icon == null
          ? TextButton(
              onPressed: onPressed,
              autofocus: autofocus,
              style: style,
              child: text,
            )
          : TextButton.icon(
              onPressed: onPressed,
              autofocus: autofocus,
              style: style,
              icon: Icon(icon, size: 14),
              label: text,
            ),
    );
  }
}
