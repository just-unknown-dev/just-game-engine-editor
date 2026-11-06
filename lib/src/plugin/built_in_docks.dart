import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_signals/just_signals.dart';

import 'just_game_editor_plugin.dart';
import 'engine_debugger.dart';
import 'package:just_editor_core/host.dart';
import '../assets/assets_dock.dart';
import '../docks/console_dock.dart';
import '../docks/profiler/frame_capture.dart';
import '../docks/profiler/profiler_dock.dart';
import '../docks/detail_cards.dart';
import '../timeline/timeline_dock.dart';
import '../timeline/timeline_session.dart';
import '../physics/physics_layers_dock.dart';
import '../tags/tags_dock.dart';
import '../docks/world_dock.dart';
import '../docks/dock_ids.dart';
import '../docks/animator_dock.dart';
import '../docks/history_dock.dart';
import '../docks/search_dock.dart';
import '../problems/problem_scan.dart';
import '../problems/problems_dock.dart';

/// The editor's own docks, contributed the way a module's are: one
/// [DockDefinition] each, so the panel has a single code path.
abstract final class BuiltInDocks {
  static final Expando<List<DockDefinition>> _cache = Expando('builtInDocks');
  static final Expando<_LogCounts> _logCounts = Expando('logCounts');

  /// What is wrong with the open scene; one scan per editor, shared by the
  /// Problems dock, its tab badge and its readout.
  static ProblemScan problemScanOf(JustGameEditorPlugin plugin) =>
      ProblemScan.of(plugin.scope);

  /// The editor's undo stack, as the History dock takes it: one notifier
  /// per editor, disposed with the editor's scope.
  ///
  /// It used to follow the designer in and out of existence, so the dock
  /// was empty whenever the designer was shut; there is one stack now and
  /// it is always there. The notifier stays because that is what the dock
  /// takes, and a module may yet swap one in.
  static ValueNotifier<EditorHistory?> historyOf(JustGameEditorPlugin plugin) =>
      plugin.scope.service(
        () => ValueNotifier<EditorHistory?>(plugin.history),
        dispose: (history) => history.dispose(),
      );

  /// The profiler's frames: one capture per editor, fed every frame by
  /// [captureFrame] all the while — a spike is worth having even if the
  /// Profiler was shut — and disposed with the editor's scope.
  static FrameCapture frameCaptureOf(JustGameEditorPlugin plugin) =>
      FrameCapture.of(plugin.scope);

  /// Gives [plugin]'s capture, once there is one, the frame just run: every
  /// frame, not the debugger's few samples a second, which caught a single
  /// spike about one time in fifteen. The plugin calls this each update.
  static void captureFrame(JustGameEditorPlugin plugin) {
    final capture = FrameCapture.maybeOf(plugin.scope);
    if (capture == null || capture.paused || !plugin.engine.isInitialized) {
      return;
    }
    capture.add(
      plugin.engine.framePerformance(),
      entities: plugin.debuggerController.snapshot.entityCount,
    );
  }

  /// The errors and warnings logged in this session — not the earlier
  /// sessions' lines the log loads back, which said nothing about now —
  /// counted once per change of the log, for the status bar and the
  /// Console's tab.
  static ({int errors, int warnings}) sessionLogCounts(
    JustGameEditorPlugin plugin,
  ) {
    final entries = plugin.logService.entries.value;
    final known = _logCounts[plugin];
    if (known != null && identical(known.of, entries)) return known.counts;
    final since = plugin.sessionStartedAt;
    var errors = 0, warnings = 0;
    for (final e in entries) {
      if (e.timestamp.isBefore(since)) continue;
      if (e.level == DebuggerLogLevel.error) errors++;
      if (e.level == DebuggerLogLevel.warning) warnings++;
    }
    final counts = (errors: errors, warnings: warnings);
    _logCounts[plugin] = _LogCounts(entries, counts);
    return counts;
  }

  /// The project's asset index: one per editor, shared by the Assets dock
  /// and its readout, scanning once and then following the disk.
  static AssetIndex assetIndexOf(JustGameEditorPlugin plugin) =>
      plugin.scope.assetIndex;

  /// The built-in docks for [plugin], made once: their closures hold state
  /// a dock should not lose between builds.
  static List<DockDefinition> forPlugin(JustGameEditorPlugin plugin) {
    frameCaptureOf(plugin);
    return _cache[plugin] ??= of(plugin);
  }

  /// Forgets the docks [forPlugin] made, so the next ask makes them from the
  /// code as it now is: after a hot reload, an edited label or header action
  /// shows. What they share — the asset index, the frame capture, the undo
  /// notifier — is kept.
  static void invalidate(JustGameEditorPlugin plugin) => _cache[plugin] = null;

  /// Every dock there is: the editor's, then the modules', by order.
  static List<DockDefinition> allFor(JustGameEditorPlugin plugin) =>
      [...forPlugin(plugin), ...plugin.scope.docks]
        ..sort((a, b) => a.order.compareTo(b.order));

  /// Runs the editor command [input] names — by id, by label, or by the one
  /// command either starts with — and says what happened. Registered
  /// commands only: nothing typed here is evaluated as code.
  static String runCommand(JustGameEditorPlugin plugin, String input) {
    final scope = plugin.scope;
    final text = input.trim().toLowerCase();
    if (text.isEmpty) return '';
    final all = scope.commands.all;
    DesignerCommand? found = scope.commands.byId(input.trim());
    found ??= all.where((c) => c.label.toLowerCase() == text).firstOrNull;
    if (found == null) {
      final close = [
        for (final c in all)
          if (c.id.toLowerCase().contains(text) ||
              c.label.toLowerCase().contains(text))
            c,
      ];
      if (close.isEmpty) return 'No command called "${input.trim()}".';
      if (close.length > 1) {
        return 'Which one? ${close.take(6).map((c) => c.id).join(', ')}'
            '${close.length > 6 ? ', …' : ''}';
      }
      found = close.single;
    }
    final context = CommandContext(
      scope: scope,
      session: plugin.designer.value,
      host: plugin,
      modifiers: const ModifierKeys(),
      gridSize: plugin.gridSize.value,
    );
    // A Level Designer command works on the designer's session, and on the
    // level as authored — as its key does.
    if (found.availability == CommandAvailability.designer &&
        (context.session == null || !plugin.isAuthoring.value)) {
      return '"${found.label}" works in the Level Designer, while editing: '
          '${context.session == null ? 'open it first' : 'stop the play-test first'}.';
    }
    if (!found.enabledIn(context)) {
      return '"${found.label}" is not available right now.';
    }
    try {
      found.run(context);
    } catch (error) {
      plugin.scope.log.log(
        'The command "${found.label}" failed: $error',
        source: 'console',
        category: 'commands',
        level: DebuggerLogLevel.error,
      );
      return '"${found.label}" failed: $error';
    }
    return 'Ran "${found.label}".';
  }

  static List<DockDefinition> of(JustGameEditorPlugin plugin) {
    final scope = plugin.scope;
    final debugger = plugin.debuggerController;

    Widget withSettings(Widget Function(OverlayUiSettings settings) build) =>
        SignalBuilder<OverlayUiSettings>(
          signal: scope.prefs.settings,
          builder: (context, settings, _) => build(settings),
        );

    return [
      DockDefinition(
        id: DockIds.console,
        label: 'Console',
        icon: Icons.terminal_rounded,
        order: 10,
        keepAlive: true,
        tabBadge: (_) {
          final (:errors, :warnings) = sessionLogCounts(plugin);
          if (errors > 0) return DockBadge('$errors', DockSeverity.error);
          return warnings > 0
              ? DockBadge('$warnings', DockSeverity.warning)
              : null;
        },
        build: (context, dock) => ConsoleDock(
          scope: scope,
          dock: dock,
          runCommand: (input) => runCommand(plugin, input),
          commandNames: () => [
            for (final c in scope.commands.all) (c.id, c.label),
          ],
          playChanges: plugin.playController.state,
          isPlaying: () => plugin.playController.isRunning,
        ),
      ),
      DockDefinition(
        id: DockIds.assets,
        label: 'Assets',
        icon: Icons.folder_open_rounded,
        order: 20,
        keepAlive: true,
        build: (context, dock) => AssetsDock(
          scope: scope,
          dock: dock,
          index: assetIndexOf(plugin),
          onOpenScene: plugin.openScene,
          sceneManager: plugin.sceneManager,
        ),
      ),
      DockDefinition(
        id: DockIds.timeline,
        label: 'Timeline',
        icon: Icons.movie_filter_outlined,
        order: 30,
        defaultHeight: 300,
        build: (context, dock) {
          TimelineSession.of(scope)
            ..isAuthoring = (() => plugin.isAuthoring.value)
            ..onSaved = plugin.reloadAsset;
          return TimelineDock(
            scope: scope,
            openPath: dock.args['path'] as String?,
          );
        },
      ),
      DockDefinition(
        id: DockIds.profiler,
        label: 'Profiler',
        icon: Icons.speed_rounded,
        order: 40,
        keepAlive: true,
        tabBadge: (_) {
          final spikes = frameCaptureOf(plugin).spikes;
          return spikes > 0 && plugin.playController.isRunning
              ? DockBadge('$spikes', DockSeverity.warning)
              : null;
        },
        build: (context, dock) => ProfilerDock(
          scope: scope,
          dock: dock,
          capture: frameCaptureOf(plugin),
          // The runtime counters and history charts the panel had before.
          details: (context) => withSettings(
            (settings) =>
                DockPerformancePanel(controller: debugger, settings: settings),
          ),
        ),
      ),
      DockDefinition(
        id: DockIds.world,
        label: 'World',
        icon: Icons.hub_outlined,
        order: 50,
        build: (context, dock) =>
            WorldDock(scope: scope, dock: dock, debugger: debugger),
      ),
      DockDefinition(
        id: DockIds.problems,
        label: 'Problems',
        icon: Icons.rule_rounded,
        order: 60,
        tabBadge: (_) {
          final scan = problemScanOf(plugin);
          final n = scan.problems.length;
          if (n == 0) return null;
          return DockBadge(
            '$n',
            scan.errors > 0 ? DockSeverity.error : DockSeverity.warning,
          );
        },
        build: (context, dock) =>
            ProblemsDock(scope: scope, scan: problemScanOf(plugin)),
      ),
      DockDefinition(
        id: DockIds.tags,
        label: 'Tags',
        icon: Icons.label_outline,
        order: 65,
        build: (context, dock) => TagsDock(scope: scope),
      ),
      DockDefinition(
        id: DockIds.physics,
        label: 'Physics Layers',
        icon: Icons.layers_outlined,
        order: 66,
        build: (context, dock) => PhysicsLayersDock(scope: scope),
      ),
      DockDefinition(
        id: DockIds.history,
        label: 'History',
        icon: Icons.history_rounded,
        order: 70,
        pinnedByDefault: false,
        build: (context, dock) => HistoryDock(history: historyOf(plugin)),
      ),
      DockDefinition(
        id: DockIds.animator,
        label: 'Animator',
        icon: Icons.account_tree_outlined,
        order: 80,
        pinnedByDefault: false,
        build: (context, dock) => AnimatorDock(scope: scope),
      ),
      DockDefinition(
        id: DockIds.search,
        label: 'Search',
        icon: Icons.manage_search_rounded,
        order: 90,
        build: (context, dock) => SearchDock(scope: scope, dock: dock),
      ),
    ];
  }
}

/// The counts [BuiltInDocks.sessionLogCounts] made, and of which log.
class _LogCounts {
  const _LogCounts(this.of, this.counts);

  final List<Object?> of;
  final ({int errors, int warnings}) counts;
}
