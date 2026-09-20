import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../level_designer/level_designer.dart';
import '../docks/compact_dock.dart';
import '../editor_overlay.dart';
import '../input_setup/input_setup_panel.dart';
import '../right_panel/right_panel.dart';
import '../settings/overlay_ui_settings.dart';
import '../shared/shared_widgets.dart';
import '../shared/snackbar.dart';

/// Chrome shown when the full editor is closed but the compact status dock
/// is pinned open. Sized against [MediaQuery]'s screen size since it now
/// paints in the root [Overlay] rather than inline with [JustGameEditorOverlay],
/// which — for this package's expected full-bleed usage — matches the size
/// the dock would have received locally.
class CompactChrome extends StatelessWidget {
  const CompactChrome({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: CompactStatusDock(
            plugin: plugin,
            maxDetailWidth: size.width,
            maxDetailHeight: size.height,
          ),
        ),
        const Positioned(
          bottom: OverlayLayout.compactDockPanelHeight + 8,
          right: 8,
          child: EditorSnackBarLayer(),
        ),
        Positioned.fill(
          child: SignalBuilder<bool>(
            signal: plugin.scope.chrome.inputSetupOpen,
            builder: (context, open, _) => open
                ? InputSetupOverlay(
                    plugin: plugin,
                    onClose: () =>
                        plugin.scope.chrome.inputSetupOpen.value = false,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Chrome shown while the full editor is open: right inspector panel, the
/// compact dock confined to the canvas column, the status badge, and
/// snackbars. See [CompactChrome] for the sizing assumption.
class FullEditorChrome extends StatelessWidget {
  const FullEditorChrome({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return SignalConsumer(
      signals: [
        plugin.scope.chrome.rightPanelWidth,
        plugin.designer,
        plugin.gridSize,
        plugin.isStatusPanelVisible,
      ],
      builder: (context, _) {
        final panelWidth = plugin.scope.chrome.rightPanelWidth.value;
        final leftWidth = math.max(0.0, size.width - panelWidth);

        final designer = plugin.designer.value;
        final designerPanelWidth = math.min(260.0, leftWidth / 3);
        designer?.controller
          ?..viewportInsets = EdgeInsets.fromLTRB(
            ToolPalette.width,
            0,
            panelWidth + designerPanelWidth,
            DesignerStatusBar.height,
          )
          // The play controls sit top-left now; nothing is under the minimap.
          ..minimapBottomReserve = 0;

        // Top-left of the viewport: clear of the tool strip and the rulers
        // while designing, otherwise just inside the corner. The game camera
        // preview hangs below the controls, so the plugin — which paints it on
        // the canvas — is told where that is.
        final controlsAt = designer != null
            ? const Offset(
                ToolPalette.width +
                    RulersOverlay.thickness +
                    MinimapLayout.margin,
                RulersOverlay.thickness + MinimapLayout.margin,
              )
            : const Offset(16, 16);
        plugin.gamePreviewOrigin =
            controlsAt + Offset(0, PlayControlsToolbar.heightFor(settings) + 8);

        return Stack(
          children: <Widget>[
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: panelWidth,
              child: EditorRightPanel(plugin: plugin, settings: settings),
            ),

            // The Level Designer's chrome sits to the left of the existing
            // right panel rather than replacing it: the scene tree and
            // inspector are as useful while designing a level as at any other
            // time, and taking them away to make room would be a downgrade.
            if (designer != null) ...[
              Positioned(
                top: 0,
                left: 0,
                bottom: DesignerStatusBar.height,
                right: panelWidth,
                child: LevelDesignerWorkspace(
                  session: designer,
                  gridSize: plugin.gridSize.value,
                  onGridSizeChanged: plugin.setGridSize,
                  onClose: plugin.closeLevelDesigner,
                  rightPanelWidth: designerPanelWidth,
                ),
              ),
              Positioned(
                left: 0,
                right: panelWidth,
                bottom: 0,
                child: DesignerStatusBar(
                  session: designer,
                  gridSize: plugin.gridSize.value,
                  onGridSizeChanged: plugin.setGridSize,
                ),
              ),
            ],
            if (plugin.isStatusPanelVisible.value && designer == null)
              Positioned(
                left: 0,
                right: panelWidth,
                bottom: 0,
                child: CompactStatusDock(
                  plugin: plugin,
                  maxDetailWidth: leftWidth,
                  maxDetailHeight: size.height,
                ),
              ),
            Positioned(
              left: controlsAt.dx,
              top: controlsAt.dy,
              child: PlayControlsToolbar(plugin: plugin, settings: settings),
            ),
            Positioned(
              bottom: OverlayLayout.compactDockPanelHeight + 8,
              right: panelWidth + 8,
              child: const EditorSnackBarLayer(),
            ),
            Positioned.fill(
              child: SignalBuilder<bool>(
                signal: plugin.scope.chrome.inputSetupOpen,
                builder: (context, open, _) => open
                    ? InputSetupOverlay(
                        plugin: plugin,
                        onClose: () =>
                            plugin.scope.chrome.inputSetupOpen.value = false,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Enums & data classes ──────────────────────────────────────────────────────
