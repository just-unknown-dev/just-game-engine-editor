import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../../core/constants/editor_constants.dart';
import '../../../../core/plugin/editor_plugin.dart';
import '../../../../extension/editor_contributions.dart';
import '../../settings/overlay_ui_settings.dart';
import '../dock_controller.dart';
import 'built_in_docks.dart';
import 'dock_panel.dart';

/// Docks that were popped out of the panel, each in a small window of its
/// own floating over the editor: drag it by its title, close it to put the
/// dock back. Nothing behind is blocked — the point is to see two at once.
class DockPopouts extends StatefulWidget {
  const DockPopouts({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  State<DockPopouts> createState() => _DockPopoutsState();
}

class _DockPopoutsState extends State<DockPopouts> {
  /// Where each window's top-left corner is, once it has been moved.
  final Map<String, Offset> _positions = {};
  final Map<String, Size> _sizes = {};

  static const Size _defaultSize = Size(720, 340);
  static const Size _minSize = Size(360, 200);

  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final controller = plugin.scope.dockController;
    return SignalBuilder<Set<String>>(
      signal: controller.poppedOut,
      builder: (context, popped, _) {
        if (popped.isEmpty) return const SizedBox.shrink();
        final docks = {for (final d in BuiltInDocks.allFor(plugin)) d.id: d};
        return SignalBuilder<OverlayUiSettings>(
          signal: plugin.scope.prefs.settings,
          builder: (context, settings, _) => LayoutBuilder(
            builder: (context, box) {
              var n = 0;
              return Stack(
                children: [
                  for (final id in popped)
                    if (docks[id] case final dock?)
                      _window(
                        dock,
                        controller,
                        settings,
                        box.biggest,
                        index: n++,
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _window(
    DockDefinition dock,
    DockController controller,
    OverlayUiSettings settings,
    Size area, {
    required int index,
  }) {
    final size = _sizes[dock.id] ?? _defaultSize;
    final width = size.width.clamp(_minSize.width, area.width).toDouble();
    final height = size.height.clamp(_minSize.height, area.height).toDouble();
    // New windows cascade from the top-left, clear of the play toolbar.
    final wanted =
        _positions[dock.id] ?? Offset(80.0 + index * 28, 96.0 + index * 28);
    final at = Offset(
      wanted.dx.clamp(0.0, (area.width - width).clamp(0.0, area.width)),
      wanted.dy.clamp(0.0, (area.height - 40).clamp(0.0, area.height)),
    );
    final accent = settings.themeColor;
    final radius = settings.cornerRadius + 4;

    return Positioned(
      left: at.dx,
      top: at.dy,
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: EditorTheme.dialogBg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: accent.withValues(alpha: 0.6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0xAA000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) =>
                      setState(() => _positions[dock.id] = at + d.delta),
                  child: Container(
                    height: 28,
                    color: EditorTheme.surfaceDarker,
                    padding: const EdgeInsets.only(left: 10, right: 4),
                    child: Row(
                      children: [
                        Icon(dock.icon, size: 13, color: accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dock.label,
                            style: TextStyle(
                              color: EditorTheme.textPrimary,
                              fontSize: 11 * settings.effectiveTextScale,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        DockHeaderButton(
                          icon: Icons.vertical_align_bottom_rounded,
                          tooltip: 'Put it back in the panel',
                          accent: accent,
                          onTap: () => controller.popIn(dock.id),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: dock.build(
                          context,
                          DockContext(
                            scope: widget.plugin.scope,
                            height: height - 28,
                            onResize: (_) {},
                            onClose: () => controller.popIn(dock.id),
                            memory: controller.memoryOf(dock.id),
                          ),
                        ),
                      ),
                      // The corner resizes the window.
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeUpLeftDownRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (d) => setState(
                              () => _sizes[dock.id] = Size(
                                width + d.delta.dx,
                                height + d.delta.dy,
                              ),
                            ),
                            child: const SizedBox.square(
                              dimension: 14,
                              child: Icon(
                                Icons.south_east_rounded,
                                size: 10,
                                color: EditorTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
