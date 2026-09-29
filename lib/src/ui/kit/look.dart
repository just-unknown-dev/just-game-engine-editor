import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';

/// The editor's ambient look for what is under it: its text at the size and
/// weight the settings ask for, motion as they allow, and one style of
/// tooltip.
///
/// The overlay puts it over the chrome. A dialog or a menu opened from the
/// editor lands outside the chrome — on the app's navigator — so it puts it
/// over its own content.
class EditorLook extends StatelessWidget {
  const EditorLook({super.key, required this.child});

  final Widget child;

  /// Tooltips as the editor draws them, and as long as the settings say.
  static TooltipThemeData get tooltipTheme => TooltipThemeData(
    waitDuration: EditorMetrics.tooltipWait,
    exitDuration: EditorMetrics.tooltipLinger,
    showDuration: EditorMetrics.settings.longerTimings
        ? const Duration(seconds: 6)
        : null,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    textStyle: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
    decoration: BoxDecoration(
      color: EditorTheme.panelRaised,
      borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
      border: Border.all(color: EditorTheme.borderStrong),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Inside another: that one has done it, and doing it again would scale
    // the text twice.
    if (context.dependOnInheritedWidgetOfExactType<_Applied>() != null) {
      return child;
    }
    final s = EditorMetrics.settings;
    final outer = MediaQuery.of(context);
    // The system's own text scaling, and the editor's on top of it.
    final system = outer.textScaler.scale(11) / 11;
    return MediaQuery(
      data: outer.copyWith(
        textScaler: TextScaler.linear(system * s.textScale),
        boldText: s.boldText || outer.boldText,
        disableAnimations: s.reduceMotion || outer.disableAnimations,
      ),
      child: TooltipTheme(
        data: tooltipTheme,
        child: _Applied(child: child),
      ),
    );
  }
}

/// Marks what an [EditorLook] is over.
class _Applied extends InheritedWidget {
  const _Applied({required super.child});

  @override
  bool updateShouldNotify(_Applied oldWidget) => false;
}
