import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/scope/editor_scope.dart';
import '../../../extension/editor_contributions.dart';
import '../../level_designer/level_designer.dart';
import '../docks/compact_dock.dart';
import '../docks/shell/dock_popouts.dart';
import '../editor_overlay.dart';
import '../input_setup/input_setup_panel.dart';
import '../right_panel/right_panel.dart';
import '../settings/overlay_ui_settings.dart';
import '../shared/shared_widgets.dart';
import '../shared/snackbar.dart';
import '../shared/transform_toolbar.dart';

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
/// How much of the window the editor's chrome takes from the game.
///
/// The game is laid out inside what is left, so the world is never hidden
/// behind a panel: the canvas really is smaller, which means the camera's
/// viewport, the pointer's coordinates and everything drawn on the canvas
/// follow without being told.
///
/// Both layers work this out from the same function — the chrome, which
/// draws the panels, and the overlay, which sizes the game — so they cannot
/// drift apart.
EdgeInsets editorGameInsets({
  required Size window,
  required JustGameEditorPlugin plugin,
  required bool designing,
  required double rightPanelWidth,
}) {
  // Bottom up: the status strip, any dock panel open on it, and the
  // designer's own status bar standing on those, against the level.
  final designerBar = designing ? DesignerStatusBar.height : 0.0;
  final docks = !plugin.isStatusPanelVisible.value
      ? 0.0
      : OverlayLayout.compactDockPanelHeight +
            plugin.scope.dockController.panelHeight(
              window.height -
                  designerBar -
                  OverlayLayout.compactDockPanelHeight,
            );
  // Nothing on the left: the tool strip floats over the viewport, top
  // right, under the transform column.
  return EdgeInsets.fromLTRB(
    0,
    0,
    rightPanelWidth + (designing ? designerRightPanelWidth(window) : 0),
    designerBar + docks,
  );
}

/// The designer's own panel, beside the editor's.
double designerRightPanelWidth(Size window) =>
    math.min(260.0, window.width / 3);

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
        // The docks take room from the designer: its panels stop where the
        // dock panel starts, and the level's view is inset by it.
        plugin.scope.dockController.openId,
        plugin.scope.dockController.heights,
        plugin.scope.dockController.maximised,
      ],
      builder: (context, _) {
        final panelWidth = plugin.scope.chrome.rightPanelWidth.value;
        final leftWidth = math.max(0.0, size.width - panelWidth);

        final designer = plugin.designer.value;
        final designerPanelWidth = designerRightPanelWidth(size);
        final gameInsets = editorGameInsets(
          window: size,
          plugin: plugin,
          designing: designer != null,
          rightPanelWidth: panelWidth,
        );
        // What the docks occupy at the foot of the window: the strip when it
        // is showing, and the open panel above it. The designer's status
        // bar stands on them, so the status strip is always the bottom line.
        final showDocks = plugin.isStatusPanelVisible.value;
        final designerBar = designer == null ? 0.0 : DesignerStatusBar.height;
        final docksHeight = !showDocks
            ? 0.0
            : OverlayLayout.compactDockPanelHeight +
                  plugin.scope.dockController.panelHeight(
                    size.height -
                        designerBar -
                        OverlayLayout.compactDockPanelHeight,
                  );
        designer?.controller
          // The canvas is laid out inside the free space now, so all of it
          // is visible: rulers, the minimap and anything else drawn in
          // screen space have the whole of it.
          ?..viewportInsets = EdgeInsets.zero
          // The play controls sit top-left now; nothing is under the minimap.
          ..minimapBottomReserve = 0;

        // Top-left of the viewport: clear of the tool strip and the rulers
        // while designing, otherwise just inside the corner. The game camera
        // preview hangs below the controls, so the plugin — which paints it on
        // the canvas — is told where that is.
        final controlsAt = designer != null
            ? const Offset(
                RulersOverlay.thickness + MinimapLayout.margin,
                RulersOverlay.thickness + MinimapLayout.margin,
              )
            : const Offset(16, 16);
        plugin.gamePreviewOrigin =
            controlsAt +
            Offset(0, PlayControlsToolbar.heightFor(settings) + 8) -
            Offset(gameInsets.left, gameInsets.top);
        // The same frame as the toolbar above it: radius, border, padding.
        plugin.gamePreviewStyle = GamePreviewStyle(
          cornerRadius: settings.cornerRadius + 6,
          borderColor: settings.themeColor,
          padding: 5 * settings.compactness,
        );

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
                bottom: DesignerStatusBar.height + docksHeight,
                right: panelWidth,
                child: LevelDesignerWorkspace(
                  session: designer,
                  gridSize: plugin.gridSize.value,
                  onGridSizeChanged: plugin.setGridSize,
                  onClose: plugin.closeLevelDesigner,
                  rightPanelWidth: designerPanelWidth,
                ),
              ),
              // On the docks, against the level it reports on.
              Positioned(
                left: 0,
                right: panelWidth,
                bottom: docksHeight,
                child: DesignerStatusBar(
                  session: designer,
                  gridSize: plugin.gridSize.value,
                  onGridSizeChanged: plugin.setGridSize,
                ),
              ),
            ],
            // The interface editor is a workspace now — a dialog over the
            // editor, like the sprite editor — so nothing of it is mounted
            // here over the viewport.
            // The docks are there while designing too — at the foot of the
            // window, under the designer's own status bar — so assets, the
            // console and the timeline are at hand exactly when a level is
            // being built.
            if (showDocks)
              Positioned(
                left: 0,
                right: panelWidth,
                bottom: 0,
                child: CompactStatusDock(
                  plugin: plugin,
                  maxDetailWidth: leftWidth,
                  maxDetailHeight: size.height - designerBar,
                ),
              ),
            Positioned(
              left: controlsAt.dx,
              top: controlsAt.dy,
              child: PlayControlsToolbar(plugin: plugin, settings: settings),
            ),
            // All, Move, Scale, Rotate: the play controls' mirror, at the
            // top right of the level — clear of the designer's panel and,
            // at the top, of its ruler — and the designer's tool strip
            // hanging below, as tall as the level lets it be.
            Positioned(
              right:
                  gameInsets.right +
                  (designer != null ? MinimapLayout.margin : 16),
              top: controlsAt.dy,
              bottom: gameInsets.bottom + 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TransformToolbar(plugin: plugin, settings: settings),
                  if (designer != null) ...[
                    const SizedBox(height: 8),
                    Flexible(
                      child: FloatingToolFrame(
                        settings: settings,
                        child: ToolPalette(session: designer),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Above whatever the foot of the window holds.
            Positioned(
              bottom: gameInsets.bottom + 8,
              right: panelWidth + 8,
              child: const EditorSnackBarLayer(),
            ),
            // Docks popped out of the panel float over the editor.
            Positioned.fill(child: DockPopouts(plugin: plugin)),
            // A module's workspace, over the level and its panels; the
            // scene stays loaded underneath.
            Positioned.fill(
              child: SignalBuilder<OpenWorkspace?>(
                signal: plugin.scope.activeWorkspace,
                builder: (context, open, _) => open == null
                    ? const SizedBox.shrink()
                    : WorkspaceHost(
                        open: open,
                        cornerRadius: settings.cornerRadius + 6,
                        borderColor: settings.themeColor,
                        workspace: WorkspaceContext(
                          scope: plugin.scope,
                          path: open.path,
                          onClose: plugin.scope.closeWorkspace,
                          reloadAssets: plugin.reloadAsset,
                          fullScreen: plugin.scope.workspaceFullScreen,
                          onToggleFullScreen:
                              plugin.scope.toggleWorkspaceFullScreen,
                        ),
                      ),
              ),
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

/// Shows an open workspace the way its definition asks: as a dialog over the
/// editor — the level dimmed but still there behind it, so opening a tool
/// does not feel like leaving — or filling the editor outright.
class WorkspaceHost extends StatelessWidget {
  const WorkspaceHost({
    super.key,
    required this.open,
    required this.workspace,
    this.cornerRadius = 12,
    this.borderColor = EditorTheme.border,
  });

  final OpenWorkspace open;
  final WorkspaceContext workspace;
  final double cornerRadius;
  final Color borderColor;

  /// The dim over the editor behind a dialog.
  static const Key scrimKey = Key('workspaceScrim');

  /// Room left around a dialog, so the editor shows at its edges.
  static const EdgeInsets dialogMargin = EdgeInsets.symmetric(
    horizontal: 40,
    vertical: 28,
  );

  /// Below this there is no room to spare for a margin: the dialog fills.
  static const Size roomyEnough = Size(1100, 640);

  @override
  Widget build(BuildContext context) {
    final body = KeyedSubtree(
      key: ValueKey('${open.definition.id}:${open.path}'),
      child: open.definition.build(context, workspace),
    );
    final fullScreen = workspace.fullScreen;
    if (fullScreen == null) return _present(body, false);
    // One subtree either way, so switching keeps the workspace's state.
    return ValueListenableBuilder<bool>(
      valueListenable: fullScreen,
      builder: (context, filled, _) => _present(body, filled),
    );
  }

  Widget _present(Widget body, bool filled) {
    return LayoutBuilder(
      builder: (context, box) {
        final asDialog =
            !filled &&
            open.definition.presentation == WorkspacePresentation.dialog &&
            box.maxWidth >= roomyEnough.width &&
            box.maxHeight >= roomyEnough.height;
        if (!asDialog) {
          return ColoredBox(color: EditorTheme.dialogBg, child: body);
        }
        return Stack(
          children: [
            // The scrim takes clicks, so nothing behind is pressed by
            // accident — and does nothing with them: closing is the
            // workspace's own button, which can ask about unsaved work.
            const Positioned.fill(
              child: ModalBarrier(
                key: scrimKey,
                dismissible: false,
                color: Color(0x99000000),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: dialogMargin,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(cornerRadius),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xAA000000),
                        blurRadius: 32,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(cornerRadius),
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(cornerRadius),
                        border: Border.all(color: borderColor),
                      ),
                      child: ColoredBox(
                        color: EditorTheme.dialogBg,
                        child: body,
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
}
