import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart' show Entity;

import 'package:just_editor_core/host.dart';

/// A run of identical log lines, shown as one with a count.
class ConsoleRow {
  ConsoleRow(this.entry);

  final EditorLogEntry entry;
  int count = 1;

  /// When the last of the run arrived.
  late DateTime lastAt = entry.timestamp;
}

/// What the Console shows of [entries]: filtered, and with runs of the same
/// line folded together. Pure, so it can be tested without a widget.
class ConsoleView {
  const ConsoleView({
    this.query = '',
    this.levels = const {
      DebuggerLogLevel.info,
      DebuggerLogLevel.warning,
      DebuggerLogLevel.error,
    },
    this.hiddenSources = const {},
    this.collapse = true,
  });

  /// Plain text, or `/pattern/` for a regular expression.
  final String query;
  final Set<DebuggerLogLevel> levels;
  final Set<String> hiddenSources;
  final bool collapse;

  /// The matcher [query] asks for; null matches everything. A pattern that
  /// does not compile matches as plain text rather than hiding every line.
  bool Function(String text)? get _matcher {
    final q = query.trim();
    if (q.isEmpty) return null;
    if (q.length > 2 && q.startsWith('/') && q.endsWith('/')) {
      try {
        final pattern = RegExp(
          q.substring(1, q.length - 1),
          caseSensitive: false,
        );
        return pattern.hasMatch;
      } on FormatException {
        // Fall through: treat it as text.
      }
    }
    final needle = q.toLowerCase();
    return (text) => text.toLowerCase().contains(needle);
  }

  List<ConsoleRow> apply(List<EditorLogEntry> entries) {
    final matches = _matcher;
    final out = <ConsoleRow>[];
    for (final e in entries) {
      if (!levels.contains(e.level)) continue;
      if (hiddenSources.contains(e.source)) continue;
      if (matches != null &&
          !matches(e.message) &&
          !matches(e.source) &&
          !matches(e.details ?? '')) {
        continue;
      }
      final last = out.isEmpty ? null : out.last.entry;
      if (collapse &&
          last != null &&
          last.message == e.message &&
          last.level == e.level &&
          last.source == e.source) {
        out.last
          ..count += 1
          ..lastAt = e.timestamp;
      } else {
        out.add(ConsoleRow(e));
      }
    }
    return out;
  }

  static Map<DebuggerLogLevel, int> countLevels(List<EditorLogEntry> entries) {
    final counts = <DebuggerLogLevel, int>{};
    for (final e in entries) {
      counts[e.level] = (counts[e.level] ?? 0) + 1;
    }
    return counts;
  }
}

/// When a line was logged: the time, and the day too when that was not
/// today ([now], the clock by default).
///
/// The Console loads earlier sessions' lines back, and at a bare time a
/// week-old error read as one from a minute ago.
String consoleTimeLabel(DateTime at, {DateTime? now}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  final today = now ?? DateTime.now();
  if (at.year == today.year && at.month == today.month && at.day == today.day) {
    return clock;
  }
  return '${at.year}-${two(at.month)}-${two(at.day)} $clock';
}

/// Runs what was typed on the Console's command line; returns what to print.
typedef ConsoleCommandRunner = String Function(String input);

/// The Console: the editor's and the game's log, searchable, and a command
/// line for the editor's own commands.
class ConsoleDock extends StatefulWidget {
  const ConsoleDock({
    super.key,
    required this.scope,
    required this.dock,
    required this.runCommand,
    required this.commandNames,
    this.playChanges,
    this.isPlaying,
  });

  final EditorScope scope;
  final DockContext dock;
  final ConsoleCommandRunner runCommand;

  /// Every command's id and label, for completion.
  final List<(String id, String label)> Function() commandNames;

  /// Tells when the play-test starts or stops, for "clear on Play"; with
  /// [isPlaying] saying which.
  final Listenable? playChanges;
  final bool Function()? isPlaying;

  @override
  State<ConsoleDock> createState() => _ConsoleDockState();
}

class _ConsoleDockState extends State<ConsoleDock> {
  DockMemory? get _memory => widget.dock.memory;

  late String _query = _memory?.read<String>('query') ?? '';
  late bool _collapse = _memory?.read<bool>('collapse') ?? true;
  late bool _follow = _memory?.read<bool>('follow') ?? true;
  late bool _clearOnPlay = _memory?.read<bool>('clearOnPlay') ?? false;
  // A Console that has never been touched hides what the settings say.
  late final Set<DebuggerLogLevel> _levels = {
    for (final l in DebuggerLogLevel.values)
      if (!(_memory?.read<List<Object?>>('hiddenLevels') ??
              widget.scope.prefs.settings.value.consoleHiddenLevels)
          .contains(l.name))
        l,
  };
  late final Set<String> _hiddenSources = {
    ...(_memory?.read<List<Object?>>('hiddenSources') ?? const [])
        .whereType<String>(),
  };

  /// While paused, the list as it was when Pause was pressed.
  List<EditorLogEntry>? _frozen;
  final Set<EditorLogEntry> _expanded = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _command = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final List<String> _history = [];
  int _historyAt = -1;
  VoidCallback? _stopWatchingLog;
  VoidCallback? _stopWatchingSettings;
  late bool _timestamps = widget.scope.prefs.settings.value.consoleTimestamps;

  @override
  void initState() {
    super.initState();
    _stopWatchingLog = widget.scope.log.entries.watch(_onLog);
    _stopWatchingSettings = widget.scope.prefs.settings.watch(() {
      final on = widget.scope.prefs.settings.value.consoleTimestamps;
      if (mounted && on != _timestamps) setState(() => _timestamps = on);
    });
    widget.playChanges?.addListener(_onPlayChanged);
    _applyArgs();
    if (_follow) _scrollToEnd();
  }

  @override
  void didUpdateWidget(ConsoleDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dock.args, widget.dock.args)) _applyArgs();
  }

  /// A readout can open the Console on one level: `{'level': 'error'}`.
  void _applyArgs() {
    final level = DebuggerLogLevel.values
        .asNameMap()[widget.dock.args['level']];
    if (level == null) return;
    _levels
      ..clear()
      ..add(level);
  }

  void _onLog() {
    if (!mounted || _frozen != null) return;
    setState(() {});
    if (_follow) _scrollToEnd();
  }

  bool _wasPlaying = false;

  void _onPlayChanged() {
    final playing = widget.isPlaying?.call() ?? false;
    // Once, as play starts — not again on pause and resume.
    if (_clearOnPlay && playing && !_wasPlaying) widget.scope.log.clear();
    _wasPlaying = playing;
  }

  /// Jumps to the newest line. Rows are built lazily and are not all one
  /// height, so the list only learns its true length by getting there: the
  /// jump is made twice, a frame apart.
  void _scrollToEnd([int again = 1]) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        if (again > 0) {
          setState(() {});
          _scrollToEnd(again - 1);
        }
      });

  @override
  void dispose() {
    _stopWatchingLog?.call();
    _stopWatchingSettings?.call();
    widget.playChanges?.removeListener(_onPlayChanged);
    _scroll.dispose();
    _command.dispose();
    _commandFocus.dispose();
    super.dispose();
  }

  void _remember() {
    _memory
      ?..write('query', _query)
      ..write('collapse', _collapse)
      ..write('follow', _follow)
      ..write('clearOnPlay', _clearOnPlay)
      ..write('hiddenLevels', [
        for (final l in DebuggerLogLevel.values)
          if (!_levels.contains(l)) l.name,
      ])
      ..write('hiddenSources', _hiddenSources.toList());
  }

  void _update(VoidCallback change) {
    setState(change);
    _remember();
  }

  /// Lines that came in since Pause. The log is capped, so lengths cannot
  /// be compared: count what follows the last line that was showing.
  int get _arrivedWhilePaused {
    final frozen = _frozen;
    if (frozen == null) return 0;
    final live = widget.scope.log.entries.value;
    if (frozen.isEmpty) return live.length;
    final at = live.lastIndexOf(frozen.last);
    return at < 0 ? live.length : live.length - 1 - at;
  }

  List<EditorLogEntry> get _entries =>
      _frozen ?? widget.scope.log.entries.value;

  static String _time(DateTime t) => consoleTimeLabel(t);

  static String _line(ConsoleRow row) {
    final e = row.entry;
    final times = row.count > 1 ? '  ×${row.count}' : '';
    final details = e.details == null ? '' : '\n    ${e.details}';
    return '${_time(e.timestamp)} [${e.level.name}] ${e.source}: '
        '${e.message}$times$details';
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _say('$what copied');
  }

  // The editor's own messages, like everything else it says.
  void _say(String text) => EditorMessenger.of(context).showSnackBar(
    EditorSnackBarEntry(
      message: text,
      type: EditorSnackBarType.success,
      duration: const Duration(milliseconds: 1600),
    ),
  );

  Future<void> _export(List<ConsoleRow> rows) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(
      '${Directory.current.path}/.editor_logs/console_$stamp.log',
    );
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(rows.map(_line).join('\n'));
      widget.scope.log.log(
        'Exported ${rows.length} lines to .editor_logs/console_$stamp.log',
        source: 'editor',
        category: 'console',
      );
    } catch (e) {
      widget.scope.log.log(
        'Could not export the log: $e',
        source: 'editor',
        category: 'console',
        level: DebuggerLogLevel.error,
      );
    }
  }

  /// The entity a line is about: `#12`, or a name in double quotes.
  Entity? _entityIn(String message) {
    final world = widget.scope.world;
    final id = RegExp(r'#(\d+)').firstMatch(message)?.group(1);
    if (id != null) {
      final entity = world.getEntity(int.parse(id));
      if (entity != null) return entity;
    }
    for (final m in RegExp('"([^"]+)"').allMatches(message)) {
      final entity = world.findEntityByName(m.group(1)!);
      if (entity != null) return entity;
    }
    return null;
  }

  // ── The command line ─────────────────────────────────────────────────────

  List<(String, String)> get _completions {
    final typed = _command.text.trim().toLowerCase();
    if (typed.isEmpty) return const [];
    return [
      for (final c in widget.commandNames())
        if (c.$1.toLowerCase().contains(typed) ||
            c.$2.toLowerCase().contains(typed))
          c,
    ].take(6).toList();
  }

  void _submit([String? input]) {
    final text = (input ?? _command.text).trim();
    if (text.isEmpty) return;
    _history
      ..remove(text)
      ..add(text);
    _historyAt = -1;
    final result = widget.runCommand(text);
    widget.scope.log.log(
      '> $text\n$result',
      source: 'console',
      category: 'command',
    );
    _command.clear();
    setState(() {});
    _commandFocus.requestFocus();
  }

  KeyEventResult _onCommandKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      if (_history.isEmpty) return KeyEventResult.handled;
      final step = key == LogicalKeyboardKey.arrowUp ? 1 : -1;
      _historyAt = (_historyAt + step).clamp(-1, _history.length - 1);
      _command.text = _historyAt < 0
          ? ''
          : _history[_history.length - 1 - _historyAt];
      _command.selection = TextSelection.collapsed(
        offset: _command.text.length,
      );
      setState(() {});
      return KeyEventResult.handled;
    }
    // Tab completes when there is something to complete; otherwise it moves
    // the focus on, as Tab does everywhere else.
    if (key == LogicalKeyboardKey.tab) {
      final options = _completions;
      if (options.isEmpty || _command.text == options.first.$1) {
        return KeyEventResult.ignored;
      }
      _command.text = options.first.$1;
      _command.selection = TextSelection.collapsed(
        offset: _command.text.length,
      );
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final all = _entries;
    final counts = ConsoleView.countLevels(all);
    final sources = {for (final e in all) e.source}.toList()..sort();
    final rows = ConsoleView(
      query: _query,
      levels: _levels,
      hiddenSources: _hiddenSources,
      collapse: _collapse,
    ).apply(all);
    final completions = _commandFocus.hasFocus
        ? _completions
        : const <(String, String)>[];

    return Column(
      children: [
        EditorToolbar(
          children: [
            EditorSearchField(
              initial: _query,
              hint: 'Search, or /regex/',
              onChanged: (v) => _update(() => _query = v),
            ),
            const SizedBox(width: 4),
            for (final (level, label, color, icon) in [
              (
                DebuggerLogLevel.info,
                'Info',
                EditorTheme.textSecondary,
                Icons.info_outline_rounded,
              ),
              (
                DebuggerLogLevel.warning,
                'Warnings',
                EditorTheme.warning,
                Icons.warning_amber_rounded,
              ),
              (
                DebuggerLogLevel.error,
                'Errors',
                EditorTheme.error,
                Icons.error_outline_rounded,
              ),
            ])
              EditorChip(
                label: label,
                icon: icon,
                color: color,
                count: counts[level] ?? 0,
                selected: _levels.contains(level),
                onTap: () => _update(
                  () => _levels.contains(level)
                      ? _levels.remove(level)
                      : _levels.add(level),
                ),
              ),
            if (sources.length > 1)
              PopupMenuButton<String>(
                tooltip: 'Sources',
                color: EditorTheme.dialogBg,
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.filter_list_rounded,
                  size: 14,
                  color: _hiddenSources.isEmpty
                      ? EditorTheme.textSecondary
                      : EditorTheme.primaryBright,
                ),
                onSelected: (s) => _update(
                  () => _hiddenSources.contains(s)
                      ? _hiddenSources.remove(s)
                      : _hiddenSources.add(s),
                ),
                itemBuilder: (context) => [
                  for (final s in sources)
                    CheckedPopupMenuItem(
                      value: s,
                      height: 28,
                      checked: !_hiddenSources.contains(s),
                      child: Text(
                        s,
                        style: TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            const Spacer(),
            EditorIconButton(
              icon: Icons.compress_rounded,
              tooltip: 'Fold repeated lines into one',
              isActive: _collapse,
              onTap: () => _update(() => _collapse = !_collapse),
            ),
            EditorIconButton(
              icon: _frozen == null
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              tooltip: _frozen == null
                  ? 'Pause: hold the list still'
                  : 'Resume ($_arrivedWhilePaused new)',
              isActive: _frozen != null,
              color: EditorTheme.warning,
              onTap: () => setState(
                () => _frozen = _frozen == null
                    ? List.of(widget.scope.log.entries.value)
                    : null,
              ),
            ),
            EditorIconButton(
              icon: Icons.vertical_align_bottom_rounded,
              tooltip: 'Follow new lines',
              isActive: _follow,
              onTap: () {
                _update(() => _follow = !_follow);
                if (_follow) _scrollToEnd();
              },
            ),
            EditorIconButton(
              icon: Icons.cleaning_services_outlined,
              tooltip: 'Clear when Play starts',
              isActive: _clearOnPlay,
              onTap: () => _update(() => _clearOnPlay = !_clearOnPlay),
            ),
            EditorIconButton(
              icon: Icons.copy_all_rounded,
              tooltip: 'Copy what is shown',
              onTap: rows.isEmpty
                  ? null
                  : () => _copy(
                      rows.map(_line).join('\n'),
                      '${rows.length} lines',
                    ),
            ),
            EditorIconButton(
              icon: Icons.save_alt_rounded,
              tooltip: 'Export what is shown to .editor_logs/',
              onTap: rows.isEmpty ? null : () => _export(rows),
            ),
            EditorIconButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Clear',
              onTap: all.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _frozen = null;
                        _expanded.clear();
                      });
                      widget.scope.log.clear();
                    },
            ),
          ],
        ),
        Expanded(
          child: rows.isEmpty
              ? EditorEmptyState(
                  icon: Icons.terminal_rounded,
                  title: all.isEmpty ? 'Nothing logged yet' : 'Nothing matches',
                  hint: all.isEmpty
                      ? 'What the editor and the game print shows here.'
                      : 'Loosen the search or the level filters.',
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _row(rows[i]),
                ),
        ),
        if (completions.isNotEmpty)
          Container(
            alignment: Alignment.centerLeft,
            color: EditorTheme.surfaceDarker,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Wrap(
              spacing: 6,
              children: [
                for (final (id, label) in completions)
                  InkWell(
                    onTap: () => _submit(id),
                    child: Text(
                      '$id  —  $label',
                      style: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Container(
          height: 26,
          decoration: BoxDecoration(
            color: EditorTheme.surfaceDarker,
            border: Border(top: BorderSide(color: EditorTheme.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Text(
                '>',
                style: TextStyle(
                  color: EditorTheme.primaryBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Focus(
                  onKeyEvent: _onCommandKey,
                  child: TextField(
                    controller: _command,
                    focusNode: _commandFocus,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    onTapOutside: (_) => _commandFocus.unfocus(),
                    style: TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText:
                          'Run an editor command — type to search, Tab completes, ↑ recalls',
                      hintStyle: TextStyle(
                        color: EditorTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ConsoleRow row) {
    final e = row.entry;
    final color = switch (e.level) {
      DebuggerLogLevel.error => EditorTheme.error,
      DebuggerLogLevel.warning => EditorTheme.warning,
      _ => EditorTheme.textSecondary,
    };
    final expanded = _expanded.contains(e);
    final entity = _entityIn(e.message);
    final hasMore = e.details != null || e.message.contains('\n');
    return InkWell(
      onTap: hasMore
          ? () => setState(
              () => expanded ? _expanded.remove(e) : _expanded.add(e),
            )
          : null,
      onLongPress: () => _copy(_line(row), 'Line'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: e.level == DebuggerLogLevel.error
              ? EditorTheme.error.withValues(alpha: 0.06)
              : null,
          border: Border(
            left: BorderSide(
              width: 2,
              color: e.level == DebuggerLogLevel.info
                  ? Colors.transparent
                  : color,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_timestamps) ...[
              Text(
                _time(row.lastAt),
                style: TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
            ],
            SizedBox(
              width: 64,
              child: Text(
                e.source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: EditorTheme.primaryMutedLight,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                expanded
                    ? [e.message, ?e.details].join('\n')
                    : e.message.split('\n').first,
                maxLines: expanded ? null : 1,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
            if (row.count > 1)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '×${row.count}',
                  style: TextStyle(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (hasMore)
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 13,
                color: EditorTheme.textMuted,
              ),
            if (entity != null)
              Tooltip(
                message: 'Select ${entity.name ?? 'entity #${entity.id}'}',
                child: InkWell(
                  onTap: () => widget.scope.sceneState.selectEntity(entity),
                  child: Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 12,
                      color: EditorTheme.primaryBright,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
