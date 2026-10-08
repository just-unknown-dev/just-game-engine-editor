import 'package:flutter/material.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_signals/just_signals.dart';

import '../../../../core/plugin/editor_plugin.dart';
import '../../../../extension/editor_contributions.dart';
import '../../settings/overlay_ui_settings.dart';
import '../../../level_designer/commands/designer_command.dart';
import '../../../level_designer/state/modifier_keys.dart';
import '../assets/asset_index.dart';
import '../assets/assets_browser.dart';
import '../../../level_designer/state/editor_history.dart';
import '../console/console_dock.dart';
import '../extra/extra_docks.dart';
import '../profiler/frame_capture.dart';
import '../profiler/profiler_dock.dart';
import '../detail_cards.dart';
import '../../../timeline/timeline_dock.dart';
import '../../../timeline/timeline_session.dart';
import '../physics/physics_layers_dock.dart';
import '../tags/tags_dock.dart';
import '../world/world_dock.dart';

/// The editor's own docks, contributed the way a module's are: one
/// [DockDefinition] each, so the panel has a single code path.
abstract final class BuiltInDocks {
  static const String console = 'logs';
  static const String assets = 'assets';
  static const String timeline = 'timeline';
  static const String profiler = 'fps';
  static const String world = 'entities';
  static const String problems = 'problems';
  static const String history = 'history';
  static const String animator = 'animator';
  static const String search = 'search';
  static const String tags = 'tags';
  static const String physics = 'physics';

  /// The arg a readout passes to open the Console on one level.
  static const String levelArg = 'level';

  static final Expando<List<DockDefinition>> _cache = Expando('builtInDocks');
  static final Expando<AssetIndex> _indexes = Expando('assetIndex');
  static final Expando<FrameCapture> _captures = Expando('frameCapture');
  static final Expando<ValueNotifier<EditorHistory?>> _histories = Expando(
    'designerHistory',
  );

  /// What is wrong with the open scene; one scan per editor, shared by the
  /// Problems dock, its tab badge and its readout.
  static ProblemScan problemScanOf(JustGameEditorPlugin plugin) =>
      ProblemScan.of(plugin.scope);

  /// The editor's undo stack.
  ///
  /// It used to follow the designer in and out of existence, so the dock
  /// was empty whenever the designer was shut; there is one stack now and
  /// it is always there. The notifier stays because that is what the dock
  /// takes, and a module may yet swap one in.
  static ValueNotifier<EditorHistory?> _historyOf(
    JustGameEditorPlugin plugin,
  ) => _histories[plugin] ??= ValueNotifier<EditorHistory?>(plugin.history);

  /// The profiler's frames: one capture per editor, fed from the debugger
  /// all the while — a spike is worth having even if the Profiler was shut.
  static FrameCapture frameCaptureOf(JustGameEditorPlugin plugin) {
    final existing = _captures[plugin];
    if (existing != null) return existing;
    final capture = FrameCapture();
    final debugger = plugin.debuggerController;
    debugger.addListener(
      () => capture.add(
        debugger.performance,
        entities: debugger.snapshot.entityCount,
      ),
    );
    return _captures[plugin] = capture;
  }

  /// The project's asset index: one per editor, shared by the Assets dock
  /// and its readout, scanning once and then following the disk.
  static AssetIndex assetIndexOf(JustGameEditorPlugin plugin) =>
      _indexes[plugin] ??= (AssetIndex()
        ..scan()
        ..startWatching());

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
      plugin: plugin,
      modifiers: const ModifierKeys(),
      gridSize: plugin.gridSize.value,
    );
    if (!found.enabledIn(context)) {
      return '"${found.label}" is not available right now.';
    }
    found.run(context);
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

    int count(DebuggerLogLevel level) {
      var n = 0;
      for (final e in plugin.logService.entries.value) {
        if (e.level == level) n++;
      }
      return n;
    }

    return [
      DockDefinition(
        id: console,
        label: 'Console',
        icon: Icons.terminal_rounded,
        order: 10,
        keepAlive: true,
        tabBadge: (_) {
          final errors = count(DebuggerLogLevel.error);
          if (errors > 0) return DockBadge('$errors', DockSeverity.error);
          final warnings = count(DebuggerLogLevel.warning);
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
        id: assets,
        label: 'Assets',
        icon: Icons.folder_open_rounded,
        order: 20,
        keepAlive: true,
        build: (context, dock) => AssetsBrowserDock(
          scope: scope,
          dock: dock,
          index: assetIndexOf(plugin),
        ),
      ),
      DockDefinition(
        id: timeline,
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
        id: profiler,
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
        id: world,
        label: 'World',
        icon: Icons.hub_outlined,
        order: 50,
        build: (context, dock) =>
            WorldDock(scope: scope, dock: dock, debugger: debugger),
      ),
      DockDefinition(
        id: problems,
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
        id: tags,
        label: 'Tags',
        icon: Icons.label_outline,
        order: 65,
        build: (context, dock) => TagsDock(scope: scope),
      ),
      DockDefinition(
        id: physics,
        label: 'Physics Layers',
        icon: Icons.layers_outlined,
        order: 66,
        build: (context, dock) => PhysicsLayersDock(scope: scope),
      ),
      DockDefinition(
        id: history,
        label: 'History',
        icon: Icons.history_rounded,
        order: 70,
        pinnedByDefault: false,
        build: (context, dock) => HistoryDock(history: _historyOf(plugin)),
      ),
      DockDefinition(
        id: animator,
        label: 'Animator',
        icon: Icons.account_tree_outlined,
        order: 80,
        pinnedByDefault: false,
        build: (context, dock) => AnimatorMonitorDock(scope: scope),
      ),
      DockDefinition(
        id: search,
        label: 'Search',
        icon: Icons.manage_search_rounded,
        order: 90,
        build: (context, dock) => SceneSearchDock(scope: scope, dock: dock),
      ),
    ];
  }
}
