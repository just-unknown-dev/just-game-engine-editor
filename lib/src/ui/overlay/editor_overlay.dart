import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_signals/just_signals.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/plugin/editor_plugin.dart';
import '../../core/scope/editor_scope.dart';
import '../../core/theme/theme_controller.dart';
import 'chrome/editor_chrome.dart';
import 'settings/overlay_ui_settings.dart';
import 'shared/snackbar.dart';

// ─ Frame-safe overlay settings watcher ────────────────────────────────────

/// Wrapper that applies overlay settings on the next frame, avoiding
/// FlutterError 'Build scheduled during frame'.
///
/// This defers [plugin.applyOverlaySettings] to post-frame via SchedulerBinding,
/// ensuring it runs outside of build/layout/paint phases.
class OverlayUiSettingsWatcher extends StatefulWidget {
  const OverlayUiSettingsWatcher({
    super.key,
    required this.plugin,
    required this.settings,
    required this.child,
  });

  final JustGameEditorPlugin plugin;
  final OverlayUiSettings settings;
  final Widget child;

  @override
  State<OverlayUiSettingsWatcher> createState() =>
      _OverlayUiSettingsWatcherState();
}

class _OverlayUiSettingsWatcherState extends State<OverlayUiSettingsWatcher> {
  @override
  void didUpdateWidget(OverlayUiSettingsWatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _scheduleSettingsApplication();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleSettingsApplication();
  }

  void _scheduleSettingsApplication() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.plugin.applyOverlaySettings(
          showGrid: widget.settings.showGrid,
          gridSnappingEnabled: widget.settings.gridSnappingEnabled,
          gridSize: widget.settings.gridSize,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Public overlay host ───────────────────────────────────────────────────────

/// Wraps the game surface with the runtime editor UI.
///
/// When [plugin.isVisible.value] is false the widget keeps the game interactive.
/// If [plugin.isStatusPanelVisible.value] is true, the compact dock can still be
/// shown independently. When visible it switches to a split layout: game
/// canvas on the left, editor panel on the right.
///
/// The dock/panel/badge/snackbar "chrome" is projected into the ambient
/// [Overlay] via [OverlayPortal] rather than painted inline. Apps typically
/// stack pause/game-over dialogs above this widget (see just_zombies'
/// GameScreen); painting chrome inline would put it underneath those
/// dialogs. Routing it through the Overlay makes the editor — a developer
/// tool, not game UI — always render on top, regardless of sibling order
/// elsewhere in the app. Only the game canvas itself stays in its normal
/// tree position, since gameplay must still render beneath the app's own
/// HUD/dialogs as before.
class JustGameEditorOverlay extends StatefulWidget {
  const JustGameEditorOverlay({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<JustGameEditorOverlay> createState() => JustGameEditorOverlayState();
}

class JustGameEditorOverlayState extends State<JustGameEditorOverlay> {
  final OverlayPortalController _chromeController = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) _chromeController.show();
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return widget.gameChild;

    final plugin = widget.plugin;
    final gameChild = widget.gameChild;

    // Everything under here can reach the scope, portal children included.
    return EditorScopeProvider(
      scope: plugin.scope,
      child: EditorThemeScope(
        controller: plugin.scope.theme,
        child: EditorMessenger(
          child: FocusScope(
            node: plugin.gameFocusScopeNode,
            child: Focus(
              // Not autofocus: this wrapper has no onKeyEvent of its own, and
              // claiming focus here at mount races (and wins over) gameChild's
              // own internal autofocus Focus node — silently swallowing all
              // keyboard input into a no-op handler with no way to recover it
              // short of clicking directly on the game canvas. Editor <-> game
              // focus routing on F1 is already handled explicitly via
              // editorFocusNode/gameFocusScopeNode.requestFocus() in
              // JustGameEditorPlugin._onHardwareKey, so this wrapper doesn't
              // need to grab focus itself — leave it to gameChild by default.
              canRequestFocus: true,
              child: OverlayPortal(
                controller: _chromeController,
                overlayChildBuilder: (context) {
                  return SignalBuilder2<bool, bool>(
                    signal1: plugin.isVisible,
                    signal2: plugin.isStatusPanelVisible,
                    builder: (context, _, _, _) {
                      if (!plugin.isVisible.value) {
                        if (!plugin.isStatusPanelVisible.value) {
                          return const SizedBox.shrink();
                        }
                        return CompactChrome(plugin: plugin);
                      }

                      return SignalBuilder<OverlayUiSettings>(
                        signal: widget.plugin.scope.prefs.settings,
                        builder: (context, settings, _) => FullEditorChrome(
                          plugin: plugin,
                          settings: settings,
                        ),
                      );
                    },
                  );
                },
                child: SignalBuilder2<bool, bool>(
                  signal1: plugin.isVisible,
                  signal2: plugin.isStatusPanelVisible,
                  builder: (context, _, _, _) {
                    if (!plugin.isVisible.value) {
                      return AbsorbPointer(absorbing: false, child: gameChild);
                    }

                    return SignalBuilder<OverlayUiSettings>(
                      signal: widget.plugin.scope.prefs.settings,
                      builder: (context, settings, _) {
                        return OverlayUiSettingsWatcher(
                          plugin: plugin,
                          settings: settings,
                          child: SignalBuilder<double>(
                            signal: widget.plugin.scope.chrome.rightPanelWidth,
                            builder: (context, rightPanelWidth, _) {
                              return Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: GameCanvasArea(
                                            plugin: plugin,
                                            gameChild: gameChild,
                                          ),
                                        ),
                                        SizedBox(
                                          height: OverlayLayout
                                              .compactDockPanelHeight,
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: rightPanelWidth),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Canvas ─────────────────────────────────────────────────────────────────

class GameCanvasArea extends StatefulWidget {
  const GameCanvasArea({
    super.key,
    required this.plugin,
    required this.gameChild,
  });

  final JustGameEditorPlugin plugin;
  final Widget gameChild;

  @override
  State<GameCanvasArea> createState() => _GameCanvasAreaState();
}

class _GameCanvasAreaState extends State<GameCanvasArea> {
  Size? _lastCanvasSize;

  void _scheduleCanvasSizeUpdate(Size size) {
    if (_lastCanvasSize == size) return;
    _lastCanvasSize = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.plugin.viewport.updateCanvasSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _scheduleCanvasSizeUpdate(size);

        return Listener(
          onPointerDown: widget.plugin.viewport.onPointerDown,
          onPointerMove: widget.plugin.viewport.onPointerMove,
          onPointerUp: widget.plugin.viewport.onPointerUp,
          onPointerCancel: widget.plugin.viewport.onPointerCancel,
          onPointerSignal: widget.plugin.viewport.onPointerScroll,
          child: AbsorbPointer(absorbing: true, child: widget.gameChild),
        );
      },
    );
  }
}
