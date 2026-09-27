import 'package:flutter/material.dart';

import '../../core/constants/editor_constants.dart';

/// Builds a scrollable around [controller].
typedef ScrollableBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// A scroll bar that is always there when a list holds more than it shows.
///
/// On the desktop Flutter shows a list's bar only while it scrolls or the
/// pointer is over it, so a long list looks as if it ends at the foot of its
/// panel. This one keeps its thumb showing, and switches the default one
/// off beneath it so there are never two.
///
/// [builder] gets the controller to give its scrollable; pass [controller]
/// to use one of your own, otherwise one is made and disposed here.
class EditorScrollbar extends StatefulWidget {
  const EditorScrollbar({
    super.key,
    required this.builder,
    this.controller,
    this.axis = Axis.vertical,
  });

  final ScrollableBuilder builder;
  final ScrollController? controller;

  /// Which way the scrollable scrolls.
  final Axis axis;

  /// How thick the bar is drawn.
  static const double thickness = 6;

  /// The theme the editor's bars are drawn with: quiet until touched.
  static ScrollbarThemeData get theme => ScrollbarThemeData(
    thickness: const WidgetStatePropertyAll(thickness),
    radius: const Radius.circular(3),
    thumbColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)
          ? EditorTheme.textSecondary.withValues(alpha: 0.7)
          : EditorTheme.textMuted.withValues(alpha: 0.45),
    ),
    crossAxisMargin: 1,
    mainAxisMargin: 2,
  );

  @override
  State<EditorScrollbar> createState() => _EditorScrollbarState();
}

class _EditorScrollbarState extends State<EditorScrollbar> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ScrollbarTheme(
      data: EditorScrollbar.theme,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        notificationPredicate: (n) =>
            n.depth == 0 && n.metrics.axis == widget.axis,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: widget.builder(context, controller),
        ),
      ),
    );
  }
}

/// Scroll bars on both edges of something that scrolls both ways: a
/// vertical scrollable holding a horizontal one, as [builder] makes them.
class EditorScrollbar2D extends StatefulWidget {
  const EditorScrollbar2D({super.key, required this.builder});

  /// Builds `SingleChildScrollView(controller: vertical, child:
  /// SingleChildScrollView(controller: horizontal, scrollDirection:
  /// Axis.horizontal, ...))`.
  final Widget Function(
    BuildContext context,
    ScrollController vertical,
    ScrollController horizontal,
  )
  builder;

  @override
  State<EditorScrollbar2D> createState() => _EditorScrollbar2DState();
}

class _EditorScrollbar2DState extends State<EditorScrollbar2D> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollbarTheme(
    data: EditorScrollbar.theme,
    child: Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      notificationPredicate: (n) =>
          n.depth == 0 && n.metrics.axis == Axis.vertical,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        // The horizontal scrollable sits inside the vertical one.
        notificationPredicate: (n) =>
            n.depth == 1 && n.metrics.axis == Axis.horizontal,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: widget.builder(context, _vertical, _horizontal),
        ),
      ),
    ),
  );
}
