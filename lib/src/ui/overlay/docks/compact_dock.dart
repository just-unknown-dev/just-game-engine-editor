import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart' show TransformComponent;
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../../core/plugin/editor_plugin.dart';
import 'dock_controller.dart';
import 'shell/built_in_docks.dart';
import 'shell/dock_panel.dart';
import '../../../core/scope/editor_scope_services.dart';

class CompactStatusDock extends StatefulWidget {
  const CompactStatusDock({
    super.key,
    required this.plugin,
    required this.maxDetailHeight,
  });

  final JustGameEditorPlugin plugin;
  final double maxDetailHeight;

  @override
  State<CompactStatusDock> createState() => _CompactStatusDockState();
}

class _CompactStatusDockState extends State<CompactStatusDock> {
  // Resolved once: dispose runs after the plugin may have closed the scope,
  // and must not go back through the container.
  late final DockController _dock = widget.plugin.scope.dockController;

  /// Ticks a few times a second: the strip's numbers and the tabs' badges
  /// listen to it, so a refresh repaints those and nothing else.
  final ValueNotifier<int> _pulse = ValueNotifier(0);
  Timer? _ticker;
  int? _tickerMs;
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
      // A new refresh rate applies now, not at the next launch.
      widget.plugin.scope.prefs.settings.watch(_startTicker),
    ];
    _dock.reconcile(_docks);
    _restore();
    _startTicker();
  }

  Future<void> _restore() async {
    final scope = widget.plugin.scope;
    await scope.prefs.load();
    if (!mounted) return;
    _dock
      ..attach(
        saved: scope.prefs.get(_saved),
        store: (json) => scope.prefs.set(_saved, json),
      )
      ..reconcile(_docks);
  }

  void _startTicker() {
    final ms = OverlayUiSettings.metricRefreshRange
        .clamp(widget.plugin.scope.prefs.settings.value.metricRefreshMs)
        .round();
    if (ms == _tickerMs && _ticker != null) return;
    _tickerMs = ms;
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
    final strip = OverlayLayout.compactDockPanelHeight;
    final panelHeight = _dock.panelHeight(widget.maxDetailHeight - strip);
    final totalHeight = strip + panelHeight;

    return SignalBuilder<OverlayUiSettings>(
      signal: widget.plugin.scope.prefs.settings,
      builder: (context, settings, _) {
        return AnimatedContainer(
          duration: EditorMetrics.motionMedium,
          curve: Curves.easeOutCubic,
          height: totalHeight,
          child: Material(
            color: Colors.transparent,
            child: Stack(
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
                    trailing: const <Widget>[MinimizedSnacksChip()],
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
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The status bar along the editor's foot: a line of quick facts — the
/// scene, what is wrong, how fast it runs, what is selected.
///
/// A fact that has somewhere to go is a button to it: the error count opens
/// the Console on its errors, the frame rate the Profiler, the selection
/// puts the level on it. A click anywhere else opens the dock panel, or
/// shuts it; which dock shows is the tabs' business, not the bar's.
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

  static Color get _good => EditorTheme.success;

  @override
  Widget build(BuildContext context) {
    final isOpen = controller.activeDock != null;
    return Material(
      color: EditorTheme.surfaceDarker,
      child: InkWell(
        onTap: () => controller.togglePanel(fallback: BuiltInDocks.console),
        hoverColor: EditorTheme.accent.withValues(alpha: 0.06),
        child: Tooltip(
          message: isOpen ? 'Hide the docks  (F2)' : 'Show the docks  (F2)',
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

    // Frame time against the budget at the target rate: fine, close, over.
    final budget = plugin.scope.prefs.settings.value.frameBudgetMs;
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
          _Fact(text: '● unsaved', color: EditorTheme.warning),
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
              tooltip: '$errors errors: show them in the Console',
              onTap: () => controller.open(
                BuiltInDocks.console,
                args: const {BuiltInDocks.levelArg: 'error'},
              ),
            ),
          if (warnings > 0)
            _Fact(
              icon: Icons.warning_amber_rounded,
              text: '$warnings',
              color: EditorTheme.warning,
              tooltip: '$warnings warnings: show them in the Console',
              onTap: () => controller.open(
                BuiltInDocks.console,
                args: const {BuiltInDocks.levelArg: 'warning'},
              ),
            ),
          if (problems > 0)
            _Fact(
              icon: Icons.rule_rounded,
              text: '$problems',
              color: EditorTheme.warning,
              tooltip: '$problems problems with the scene: show them',
              onTap: () => controller.open(BuiltInDocks.problems),
            ),
        ],
      [
        _Fact(
          icon: Icons.speed_rounded,
          text:
              '${performance.currentFps} fps · '
              '${performance.lastUpdateMs.toStringAsFixed(1)} ms',
          color: frameColor,
          tooltip: 'Frame rate and time: open the Profiler',
          onTap: () => controller.open(BuiltInDocks.profiler),
        ),
        _Fact(
          icon: Icons.hub_outlined,
          text: '${plugin.debuggerController.snapshot.entityCount}',
          tooltip: 'Entities: open World',
          onTap: () => controller.open(BuiltInDocks.world),
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
            tooltip: selected == null ? null : 'Show it in the level',
            onTap: selected == null ? null : () => plugin.focusOn(selected),
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
                tooltip: 'Open ${d.label}',
                onTap: () => controller.open(
                  d.id,
                  args: d.readout?.openArgs ?? const {},
                ),
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

/// One fact on the status bar: an optional icon and a few words — and,
/// with [onTap], a button to where it came from.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.text,
    this.icon,
    this.color,
    this.tooltip,
    this.onTap,
  });

  final String text;
  final IconData? icon;
  final Color? color;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? EditorTheme.textSecondary;
    Widget body = Padding(
      padding: EdgeInsets.only(right: 8, left: onTap == null ? 0 : 4),
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
    final tap = onTap;
    if (tap != null) {
      // Its own click: the strip's — show or hide the docks — is for the
      // rest of the bar.
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(4),
          hoverColor: tone.withValues(alpha: 0.12),
          child: SizedBox(
            height: OverlayLayout.compactDockPanelHeight - 4,
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      );
    }
    return tooltip == null ? body : Tooltip(message: tooltip!, child: body);
  }
}
