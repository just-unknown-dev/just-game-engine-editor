import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart' show TransformComponent;
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/prefs/editor_prefs.dart';
import '../../../extension/editor_contributions.dart';
import '../input_setup/input_setup_panel.dart';
import '../settings/overlay_ui_settings.dart';
import '../settings/settings_dialog.dart';
import '../shared/snackbar.dart';
import 'dock_controller.dart';
import 'shell/built_in_docks.dart';
import 'shell/dock_panel.dart';

class CompactStatusDock extends StatefulWidget {
  const CompactStatusDock({
    super.key,
    required this.plugin,
    required this.maxDetailWidth,
    required this.maxDetailHeight,
  });

  final JustGameEditorPlugin plugin;
  final double maxDetailWidth;
  final double maxDetailHeight;

  @override
  State<CompactStatusDock> createState() => _CompactStatusDockState();
}

class _CompactStatusDockState extends State<CompactStatusDock> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _settingsAnchorKey = GlobalKey();

  // Resolved once: dispose runs after the plugin may have closed the scope,
  // and must not go back through the container.
  late final DockController _dock = widget.plugin.scope.dockController;

  /// Ticks a few times a second: the strip's numbers and the tabs' badges
  /// listen to it, so a refresh repaints those and nothing else.
  final ValueNotifier<int> _pulse = ValueNotifier(0);
  Timer? _ticker;
  List<VoidCallback> _stopWatching = const [];

  /// Where the dock state is kept between launches.
  static final SettingPref<String> _saved = SettingPref.text(
    'editor.docks',
    '',
  );

  List<DockDefinition> get _docks => BuiltInDocks.allFor(widget.plugin);

  /// Docks may grow to three quarters of what the overlay allows.
  double get _maxDockHeight =>
      (widget.maxDetailHeight * 0.75).clamp(180.0, 700.0);

  void _updateSettings(OverlayUiSettings settings) {
    final scope = widget.plugin.scope;
    scope.prefs.update(settings);
    // The accent the user picked is the theme the rest of the chrome reads.
    scope.theme.select(settings.themePreset.name);
  }

  void _toggleSettings() => _dock.toggle(DockController.settingsId);

  @override
  void initState() {
    super.initState();
    void changed() {
      if (mounted) setState(() {});
    }

    _stopWatching = [
      _dock.openId.watch(changed),
      _dock.heights.watch(changed),
      _dock.order.watch(changed),
      _dock.maximised.watch(changed),
      _dock.poppedOut.watch(changed),
    ];
    _dock.reconcile(_docks);
    _restore();
    _startTicker();
  }

  Future<void> _restore() async {
    final scope = widget.plugin.scope;
    await scope.prefs.load();
    if (!mounted) return;
    scope.theme.select(scope.prefs.settings.value.themePreset.name);
    _dock
      ..attach(
        saved: scope.prefs.get(_saved),
        store: (json) => scope.prefs.set(_saved, json),
      )
      ..reconcile(_docks);
  }

  void _startTicker() {
    final ms = widget.plugin.scope.prefs.settings.value.metricRefreshMs
        .clamp(100, 2000)
        .round();
    _ticker?.cancel();
    _ticker = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (!mounted) return;
      final debugger = widget.plugin.debuggerController;
      widget.plugin.scope.chrome.recordPerfSample(
        debugger.performance,
        debugger.memory,
      );
      _pulse.value++;
    });
  }

  double _detailLeftForKey(GlobalKey anchorKey, double detailWidth) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null ||
        anchorBox == null ||
        !stackBox.hasSize ||
        !anchorBox.hasSize) {
      return 12;
    }
    final anchorCenter = anchorBox.localToGlobal(
      anchorBox.size.center(Offset.zero),
      ancestor: stackBox,
    );
    const minLeft = 12.0;
    final maxLeft = math.max(minLeft, widget.maxDetailWidth - detailWidth - 12);
    return (anchorCenter.dx - detailWidth / 2).clamp(minLeft, maxLeft);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final stop in _stopWatching) {
      stop();
    }
    _dock.flush();
    _pulse.dispose();
    super.dispose();
  }

  DockDefinition? _definition(String? id) {
    for (final d in _docks) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final docks = _docks;
    // A module may have come or gone since the last build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dock.reconcile(docks);
    });
    final active = _definition(_dock.activeDock);
    final settingsOpen = _dock.isOpen(DockController.settingsId);
    const strip = OverlayLayout.compactDockPanelHeight;
    final detailMaxHeight = widget.maxDetailHeight - strip - 40;
    final settingsPanelHeight = detailMaxHeight.clamp(260.0, 460.0).toDouble();
    final panelHeight = _dock.panelHeight(widget.maxDetailHeight - strip);
    final totalHeight =
        strip + panelHeight + (settingsOpen ? settingsPanelHeight + 12.0 : 0.0);

    return SignalBuilder<OverlayUiSettings>(
      signal: widget.plugin.scope.prefs.settings,
      builder: (context, settings, _) {
        final animationMs = (220 / settings.animationSpeed).clamp(80, 420);
        final settingsWidth = math.min(
          420.0,
          math.max(280.0, widget.maxDetailWidth - 24),
        );
        return AnimatedContainer(
          duration: Duration(milliseconds: animationMs.round()),
          curve: Curves.easeOutCubic,
          height: totalHeight,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              key: _stackKey,
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: strip,
                  child: DockStatusStrip(
                    plugin: widget.plugin,
                    docks: docks,
                    controller: _dock,
                    settings: settings,
                    pulse: _pulse,
                    trailing: <Widget>[
                      const _MinimizedSnackChip(),
                      const SizedBox(width: 8),
                      InputSetupButton(
                        settings: settings,
                        onPressed: () {
                          final open =
                              widget.plugin.scope.chrome.inputSetupOpen;
                          open.value = !open.value;
                        },
                      ),
                      _EditorSettingsButton(
                        anchorKey: _settingsAnchorKey,
                        settings: settings,
                        isSelected: settingsOpen,
                        onPressed: _toggleSettings,
                      ),
                    ],
                  ),
                ),
                if (active != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: strip,
                    child: ListenableBuilder(
                      // The tabs' badges are live; the dock below them is
                      // built once and listens to whatever it needs itself.
                      listenable: _pulse,
                      builder: (context, _) => DockPanel(
                        scope: widget.plugin.scope,
                        docks: docks,
                        controller: _dock,
                        settings: settings,
                        height: panelHeight,
                        maxHeight: _maxDockHeight,
                      ),
                    ),
                  ),
                if (settingsOpen)
                  Positioned(
                    left: _detailLeftForKey(_settingsAnchorKey, settingsWidth),
                    bottom: strip + 12,
                    child: SizedBox(
                      width: settingsWidth,
                      child: EditorSettingsPanel(
                        initial: widget.plugin.scope.prefs.settings.value,
                        prefs: widget.plugin.scope.prefs,
                        sections: widget.plugin.scope.settingsSections,
                        onChanged: _updateSettings,
                        onClose: _toggleSettings,
                        maxHeight: settingsPanelHeight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The status bar along the editor's foot: a line of quick facts — the
/// scene, what is wrong, how fast it runs, what is selected — and one big
/// button. A click anywhere on it opens the dock panel, or shuts it; which
/// dock shows is the tabs' business, not the bar's.
class DockStatusStrip extends StatelessWidget {
  const DockStatusStrip({
    super.key,
    required this.plugin,
    required this.docks,
    required this.controller,
    required this.settings,
    required this.pulse,
    this.trailing = const [],
  });

  final JustGameEditorPlugin plugin;
  final List<DockDefinition> docks;
  final DockController controller;
  final OverlayUiSettings settings;
  final Listenable pulse;
  final List<Widget> trailing;

  static const Color _good = Color(0xFF7DE6B1);

  @override
  Widget build(BuildContext context) {
    final isOpen = controller.activeDock != null;
    return Material(
      color: EditorTheme.surfaceDarker,
      child: InkWell(
        onTap: () => controller.togglePanel(fallback: BuiltInDocks.console),
        hoverColor: settings.themeColor.withValues(alpha: 0.06),
        child: Tooltip(
          message: isOpen ? 'Hide the docks  (F2)' : 'Show the docks  (F2)',
          waitDuration: const Duration(milliseconds: 700),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: EditorTheme.textPrimary.withValues(alpha: 0.08),
                ),
              ),
            ),
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ClipRect(
                    // Only the facts listen to the pulse: a refresh repaints
                    // a line of text, not the panel above.
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        pulse,
                        plugin.sceneState.activeScene,
                        plugin.sceneState.isDirty,
                        plugin.sceneState.selectedEntity,
                        plugin.sceneState.multiSelectedIds,
                        plugin.playController.state,
                      ]),
                      builder: (context, _) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(children: _facts()),
                      ),
                    ),
                  ),
                ),
                ...trailing,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    isOpen
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 15,
                    color: EditorTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _facts() {
    final scope = plugin.scope;
    final sceneState = plugin.sceneState;
    final scene = sceneState.activeScene.value;
    final performance = plugin.debuggerController.performance;
    final play = plugin.playController.state.value;

    var errors = 0, warnings = 0;
    for (final e in plugin.logService.entries.value) {
      if (e.level == DebuggerLogLevel.error) errors++;
      if (e.level == DebuggerLogLevel.warning) warnings++;
    }
    final problems = BuiltInDocks.problemScanOf(plugin).problems.length;

    // Frame time against the 60 fps budget: fine, close, over.
    const budget = 1000 / 60;
    final frameColor = performance.lastUpdateMs > budget
        ? EditorTheme.error
        : performance.lastUpdateMs > budget * 0.75
        ? EditorTheme.warning
        : EditorTheme.textSecondary;

    final selected = sceneState.selectedEntity.value;
    final count = sceneState.multiSelectedIds.value.length;
    final at = selected?.getComponent<TransformComponent>()?.position;

    final groups = <List<Widget>>[
      [
        _Fact(
          icon: Icons.map_outlined,
          text: scene == null ? 'No scene' : scene.name,
          color: scene == null
              ? EditorTheme.textMuted
              : EditorTheme.textPrimary,
        ),
        if (scene != null && sceneState.isDirty.value)
          const _Fact(text: '● unsaved', color: EditorTheme.warning),
        if (play != EditorPlayState.stopped)
          _Fact(
            text: play == EditorPlayState.playing ? '▶ playing' : '❚❚ paused',
            color: play == EditorPlayState.playing
                ? _good
                : EditorTheme.warning,
          ),
      ],
      // A clean project has a quiet bar: these show only when non-zero.
      if (errors + warnings + problems > 0)
        [
          if (errors > 0)
            _Fact(
              icon: Icons.error_outline_rounded,
              text: '$errors',
              color: EditorTheme.error,
              tooltip: '$errors errors in the Console',
            ),
          if (warnings > 0)
            _Fact(
              icon: Icons.warning_amber_rounded,
              text: '$warnings',
              color: EditorTheme.warning,
              tooltip: '$warnings warnings in the Console',
            ),
          if (problems > 0)
            _Fact(
              icon: Icons.rule_rounded,
              text: '$problems',
              color: EditorTheme.warning,
              tooltip: '$problems problems with the scene',
            ),
        ],
      [
        _Fact(
          icon: Icons.speed_rounded,
          text:
              '${performance.currentFps} fps · '
              '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
          color: frameColor,
        ),
        _Fact(
          icon: Icons.hub_outlined,
          text: '${plugin.debuggerController.snapshot.entityCount}',
          tooltip: 'Entities',
        ),
      ],
      if (selected != null || count > 1)
        [
          _Fact(
            icon: Icons.ads_click_rounded,
            text: count > 1
                ? '$count selected'
                : selected!.name ?? 'Entity ${selected.id}',
            color: EditorTheme.textPrimary,
          ),
          if (count <= 1 && at != null)
            _Fact(
              text: '${at.x.toStringAsFixed(0)}, ${at.y.toStringAsFixed(0)}',
            ),
        ],
      // What a module has to say, as facts beside the editor's own.
      for (final d in docks)
        if (d.order >= 100)
          if ((d.readout?.value(scope) ?? d.badge?.call(scope) ?? '')
              case final value when value.isNotEmpty)
            [
              _Fact(
                icon: d.icon,
                text: '${d.readout?.label ?? d.label}  $value',
                color: d.readout?.accent,
              ),
            ],
    ];

    return [
      for (var i = 0; i < groups.length; i++) ...[
        if (i > 0)
          Container(
            width: 1,
            height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: EditorTheme.textPrimary.withValues(alpha: 0.10),
          ),
        ...groups[i],
      ],
    ];
  }
}

/// One fact on the status bar: an optional icon and a few words.
class _Fact extends StatelessWidget {
  const _Fact({required this.text, this.icon, this.color, this.tooltip});

  final String text;
  final IconData? icon;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? EditorTheme.textSecondary;
    final body = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: tone,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}

// ── Minimized snackbar chip ───────────────────────────────────────────────────

class _MinimizedSnackChip extends StatelessWidget {
  const _MinimizedSnackChip();

  @override
  Widget build(BuildContext context) {
    final controller = EditorMessenger.of(context);
    return SignalBuilder2<EditorSnackBarEntry?, bool>(
      signal1: controller.current,
      signal2: controller.isMinimized,
      builder: (context, entry, minimized, _) {
        if (entry == null || !minimized) {
          return const SizedBox.shrink();
        }
        final accent = entry.type.accentColor;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: controller.expand,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: accent.withValues(alpha: 0.28)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(entry.type.iconData, size: 11, color: accent),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        entry.title ?? entry.message,
                        style: const TextStyle(
                          fontSize: 11,
                          color: EditorTheme.textSecondary,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: controller.dismiss,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.close_rounded,
                          size: 10,
                          color: EditorTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditorSettingsButton extends StatelessWidget {
  const _EditorSettingsButton({
    required this.anchorKey,
    required this.settings,
    required this.isSelected,
    required this.onPressed,
  });

  final GlobalKey anchorKey;
  final OverlayUiSettings settings;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: anchorKey,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'Editor settings',
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(settings.cornerRadius),
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    color: settings.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(settings.cornerRadius),
                    border: Border.all(
                      color: settings.themeColor.withValues(alpha: 0.28),
                    ),
                  )
                : null,
            padding: EdgeInsets.symmetric(
              horizontal: 6 * settings.compactness,
              vertical: 3 * settings.compactness,
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 14 * settings.effectiveTextScale,
              color: settings.themeColor,
            ),
          ),
        ),
      ),
    );
  }
}
