import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/scope/editor_scope.dart';
import '../../../extension/editor_contributions.dart';
import '../../level_designer/level_designer.dart';
import '../docks/compact_dock.dart';
import '../docks/shell/dock_popouts.dart';
import '../editor_overlay.dart';
import '../right_panel/right_panel.dart';
import '../settings/overlay_ui_settings.dart';
import '../settings/settings_dialog.dart';
import '../shared/dialog_frame.dart';
import '../shared/shared_widgets.dart';
import '../shared/snackbar.dart';
import '../shared/transform_toolbar.dart';
import '../shared/quick_snap_bar.dart';

/// Chrome shown when the full editor is closed but the compact status dock
/// is pinned open: the dock over the game, and the settings gear standing on
/// it at the right, with any messages above the gear. Sized against [MediaQuery]'s screen size since it paints
/// in the root [Overlay] rather than inline with [JustGameEditorOverlay],
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
          // One column, so the gear and the messages above it ride up with
          // the dock panel.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 8, bottom: 8),
                  child: EditorSnackBarLayer(),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 16),
                  child: SignalBuilder<OverlayUiSettings>(
                    signal: plugin.scope.prefs.settings,
                    builder: (context, settings, _) => SettingsGearButton(
                      scope: plugin.scope,
                      settings: settings,
                    ),
                  ),
                ),
              ),
              CompactStatusDock(plugin: plugin, maxDetailHeight: size.height),
            ],
          ),
        ),
        Positioned.fill(child: EditorSettingsHost(scope: plugin.scope)),
      ],
    );
  }
}

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
  // right, under the transform column. The designer's panel is a tab of
  // the right panel, so it takes no width of its own.
  return EdgeInsets.fromLTRB(0, 0, rightPanelWidth, designerBar + docks);
}

/// Chrome shown while the full editor is open: the right panel, the docks
/// along the foot of the canvas column, the controls floating over the
/// viewport's corners — play top left, transform top right, the settings
/// gear bottom right with messages above it, the designer's minimap bottom
/// left — and the dialogs over it all.
/// See [CompactChrome] for the sizing assumption.
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
        // No scene, no level tools: the start card has the viewport.
        plugin.sceneState.activeScene,
        // The docks take room from the designer: its panels stop where the
        // dock panel starts, and the level's view is inset by it.
        plugin.scope.dockController.openId,
        plugin.scope.dockController.heights,
        plugin.scope.dockController.maximised,
      ],
      builder: (context, _) {
        final panelWidth = plugin.scope.chrome.rightPanelWidth.value;

        final designer = plugin.designer.value;
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
          // The settings gear is in the other corner: the minimap has
          // its own.
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
        // Clear of the minimap, bottom left, while designing; of the canvas's
        // edge otherwise. The gear is at the other corner.
        plugin.gamePreviewBottomReserve = designer != null
            ? MinimapLayout.margin * 2 + MinimapLayout.size.height
            : controlsAt.dy;
        // What stands in the bottom right corner: the gear, snapping at hand
        // on it while editing, and above them the messages; the transform
        // column and tool strip stop short of them.
        final gearMargin = designer != null ? MinimapLayout.margin : 16.0;
        final quickSnap =
            !plugin.playController.isRunning && plugin.sceneState.hasScene;
        final aboveGear =
            gameInsets.bottom +
            gearMargin +
            SettingsGearButton.heightFor(settings) +
            (quickSnap ? QuickSnapBar.heightFor(settings) + 8 : 0) +
            8;
        // The same frame as the toolbar above it: radius, border, padding.
        plugin.gamePreviewStyle = GamePreviewStyle(
          cornerRadius: EditorMetrics.radiusLg,
          borderColor: EditorTheme.accent,
          padding: EditorMetrics.space(5),
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

            // The Level Designer's panel is the right panel's Level tab;
            // here, only its status bar, along the foot of the level.
            if (designer != null) ...[
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
                  maxDetailHeight: size.height - designerBar,
                ),
              ),
            Positioned(
              left: controlsAt.dx,
              top: controlsAt.dy,
              child: PlayControlsToolbar(
                plugin: plugin,
                settings: settings,
                // Up to the transform column at the top right, and no
                // further: past that, the row scrolls.
                maxWidth:
                    size.width -
                    gameInsets.right -
                    controlsAt.dx -
                    ToolPalette.width -
                    (designer != null ? MinimapLayout.margin : 16) -
                    12,
              ),
            ),
            // The settings, bottom right, under the transform column: the
            // corner the minimap leaves free while designing. Snapping
            // stands on the gear while editing — not in a play-test.
            Positioned(
              right: gameInsets.right + gearMargin,
              bottom: gameInsets.bottom + gearMargin,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (quickSnap) ...[
                    QuickSnapBar(scope: plugin.scope, settings: settings),
                    // The gap between the frames of the column above.
                    const SizedBox(height: 8),
                  ],
                  SettingsGearButton(scope: plugin.scope, settings: settings),
                ],
              ),
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
              bottom: aboveGear,
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
                        cornerRadius: EditorMetrics.radiusLg,
                        borderColor: EditorTheme.accent,
                        workspace: WorkspaceContext(
                          scope: plugin.scope,
                          path: open.path,
                          onClose: plugin.scope.closeWorkspace,
                          reloadAssets: plugin.reloadAsset,
                          fullScreen: plugin.scope.workspaceFullScreen,
                          onToggleFullScreen:
                              plugin.scope.toggleWorkspaceFullScreen,
                          setCloseGuard: (guard) => plugin.scope
                              .setWorkspaceCloseGuard(guard, of: open),
                        ),
                      ),
              ),
            ),
            // Over everything, the settings, while they are open.
            Positioned.fill(child: EditorSettingsHost(scope: plugin.scope)),
            // Messages last, so a dialog never hides one: in the canvas's
            // own corner, standing on the gear, clear of the panels and of
            // whatever the foot of the window holds.
            Positioned(
              bottom: aboveGear,
              right: gameInsets.right + 8,
              child: const EditorSnackBarLayer(),
            ),
          ],
        );
      },
    );
  }
}

/// Shows an open workspace the way its definition asks: as a dialog over the
/// editor — the level dimmed but still there behind it, so opening a tool
/// does not feel like leaving — or filling the editor outright.
class WorkspaceHost extends StatelessWidget {
  const WorkspaceHost({
    super.key,
    required this.open,
    required this.workspace,
    this.cornerRadius = 12,
    this.borderColor,
  });

  final OpenWorkspace open;
  final WorkspaceContext workspace;
  final double cornerRadius;

  /// The frame's line; the editor's faint border when null.
  final Color? borderColor;

  /// The dim over the editor behind a dialog.
  static const Key scrimKey = Key('workspaceScrim');

  /// Room left around a dialog, so the editor shows at its edges.
  static const EdgeInsets dialogMargin = EditorDialogFrame.margin;

  /// Below this there is no room to spare for a margin: the dialog fills.
  static const Size roomyEnough = EditorDialogFrame.roomyEnough;

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

  // The dim does nothing with a click: closing is the workspace's own
  // button, which can ask about unsaved work.
  Widget _present(Widget body, bool filled) => EditorDialogFrame(
    filled:
        filled || open.definition.presentation != WorkspacePresentation.dialog,
    cornerRadius: cornerRadius,
    borderColor: borderColor,
    scrimKey: scrimKey,
    child: body,
  );
}

/// The chrome while a play-test runs with the editor stepped aside, as the
/// settings ask: the game has the window, with the play controls in a small
/// bar at the top — Pause brings the editor back, Stop ends the test — and
/// any messages at the corner.
class PlayTestChrome extends StatelessWidget {
  const PlayTestChrome({
    super.key,
    required this.plugin,
    required this.settings,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        top: 8,
        left: 0,
        right: 0,
        child: Center(
          child: PlayControlsToolbar(
            plugin: plugin,
            settings: settings,
            maxWidth: 560,
          ),
        ),
      ),
      const Positioned(bottom: 8, right: 8, child: EditorSnackBarLayer()),
    ],
  );
}
