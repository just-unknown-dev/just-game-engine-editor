import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';

/// An accent ring around [child] while something in it has the keyboard.
///
/// Shown while the keyboard is being used, as focus highlights are — and
/// always, however the focus got there, with the Always-visible focus
/// setting.
class FocusOutline extends StatefulWidget {
  const FocusOutline({super.key, required this.child, this.radius});

  final Widget child;

  /// The ring's corners; the small radius when null.
  final double? radius;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final show =
        _focused &&
        (EditorMetrics.alwaysShowFocus ||
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional);
    return Focus(
      // Only listens: what takes the keyboard is inside.
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: show
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(
                  widget.radius ?? EditorMetrics.radiusSm + 1,
                ),
                border: Border.all(color: EditorTheme.primaryBright, width: 2),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
  }
}
