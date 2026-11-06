/// A data file no window of its own opens, shown as it is.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_editor_core/io.dart';

/// A JSON file no installed module has a window for — a screen file
/// without the UI editor, an animator without the sprite editor — shown as
/// it is: pretty-printed, read-only, with its lines numbered and a search,
/// and a way to open it in the system's own app. Nothing here writes it.
///
/// A file that is not valid JSON is shown as written, with why.
class JsonWorkspace extends StatefulWidget {
  /// A JSON file no other window opens, shown as it is and never written:
  /// `json` is the shortest ending, so any window with a longer one —
  /// `material2d.json` — wins.
  static const String workspaceId = 'json';

  /// Its window, as the editor's own module contributes it.
  static WorkspaceDefinition get definition => WorkspaceDefinition(
    id: workspaceId,
    label: 'JSON',
    icon: Icons.data_object,
    order: 900,
    fileExtensions: const ['json'],
    build: (context, workspace) =>
        JsonWorkspace(path: workspace.path!, workspace: workspace),
  );

  const JsonWorkspace({
    super.key,
    required this.path,
    required this.workspace,
    this.index,
    this.loadOnStart = true,
  });

  /// Where the project's files are; the editor's own when null.
  final AssetIndex? index;

  /// The file, project-relative.
  final String path;

  /// The editor's handle on the window.
  final WorkspaceContext workspace;

  /// Whether it reads the file as it opens; a test calls
  /// [JsonWorkspaceState.load] itself instead.
  final bool loadOnStart;

  @override
  State<JsonWorkspace> createState() => JsonWorkspaceState();
}

/// The state of a [JsonWorkspace]; public for tests.
class JsonWorkspaceState extends State<JsonWorkspace> {
  /// How tall a line is drawn.
  static const double lineHeight = 18;

  List<String> _lines = const [];
  String? _problem;
  bool _loaded = false;
  String _query = '';
  List<(int line, int at)> _matches = const [];

  /// Where each match in [_matches] ends in its line.
  List<int> _ends = const [];

  /// Which of [_matches] are on each line, by line: a line drawn looks at
  /// its own and no others.
  Map<int, List<int>> _byLine = const {};
  int _current = 0;
  final ScrollController _scroll = ScrollController();

  /// Sideways, for lines wider than the window: a long string, an encoded
  /// image, a deep key — shown whole, not cut at the edge.
  final ScrollController _across = ScrollController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'json search');

  /// How wide the widest line is drawn, and one character of it: measured
  /// once per file, as the lines are in one fixed-width font.
  double _textWidth = 0;
  double _charWidth = 0;

  /// The lines shown: the file pretty-printed, or as written when it is
  /// not valid JSON.
  List<String> get lines => _lines;

  /// Why the file is shown as written: what is wrong with it as JSON; null
  /// when it is valid.
  String? get problem => _problem;

  /// Where what is searched for is found: each a line and where in it.
  List<(int line, int at)> get matches => _matches;

  /// The match shown, of [matches].
  int get current => _current;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnStart) load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _across.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The width of the line with the most characters, and of a character,
  /// in the lines' font.
  (double, double) _measure(List<String> lines) {
    var longest = '';
    for (final line in lines) {
      if (line.length > longest.length) longest = line;
    }
    final painter = TextPainter(
      text: TextSpan(text: longest.isEmpty ? ' ' : longest, style: _mono),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = longest.isEmpty ? 0.0 : painter.width;
    final char = painter.width / (longest.isEmpty ? 1 : longest.length);
    painter.dispose();
    return (width, char);
  }

  AssetIndex get _index => widget.index ?? widget.workspace.scope.assetIndex;

  String get _absolute => _index.absolute(widget.path);

  /// Reads the file and shows it.
  Future<void> load() async {
    String text;
    try {
      text = await File(_absolute).readAsString();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _problem = "Can't be read: $error";
          _loaded = true;
        });
      }
      return;
    }
    String? problem;
    try {
      text = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException catch (error) {
      problem = 'Not valid JSON: ${error.message}';
    }
    if (!mounted) return;
    final lines = const LineSplitter().convert(text);
    final (width, char) = _measure(lines);
    setState(() {
      _lines = lines;
      _textWidth = width;
      _charWidth = char;
      _problem = problem;
      _loaded = true;
    });
    search(_query);
  }

  /// Finds [query] (ignoring case) in the lines, and shows the first.
  ///
  /// Matched in the lines as they are, not in lower-cased copies, whose
  /// length can differ (`İ` lower-cases to two characters): where a match
  /// starts and ends is where it is in the line drawn.
  void search(String query) {
    final found = <(int, int)>[];
    final ends = <int>[];
    final byLine = <int, List<int>>{};
    if (query.isNotEmpty) {
      final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
      for (var i = 0; i < _lines.length; i++) {
        for (final match in pattern.allMatches(_lines[i])) {
          if (match.end == match.start) continue;
          (byLine[i] ??= []).add(found.length);
          found.add((i, match.start));
          ends.add(match.end);
        }
      }
    }
    setState(() {
      _query = query;
      _matches = found;
      _ends = ends;
      _byLine = byLine;
      _current = 0;
    });
    _reveal();
  }

  /// Shows the next match (or, [back], the one before), round again past
  /// the last.
  void step({bool back = false}) {
    if (_matches.isEmpty) return;
    setState(
      () => _current =
          (_current + (back ? -1 : 1) + _matches.length) % _matches.length,
    );
    _reveal();
  }

  void _reveal() {
    if (_matches.isEmpty) return;
    final (line, at) = _matches[_current];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final view = _scroll.position.viewportDimension;
      final target = (line * lineHeight - view / 3).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.jumpTo(target);
      // Sideways too, when the match is past the window's edge.
      if (!_across.hasClients) return;
      final across = _across.position;
      final x = _gutterWidth + at * _charWidth;
      if (x >= across.pixels + 24 &&
          x <= across.pixels + across.viewportDimension - 48) {
        return;
      }
      _across.jumpTo(
        (x - across.viewportDimension / 3).clamp(0.0, across.maxScrollExtent),
      );
    });
  }

  /// How wide the line numbers and the gap after them are.
  double get _gutterWidth => 14 + '${_lines.length}'.length * 8.0 + 12;

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (EditorKeys.primaryPressed &&
        event.logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextStyle get _mono => TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    height: lineHeight / 12,
    color: EditorTheme.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    final name = widget.path.substring(widget.path.lastIndexOf('/') + 1);
    final kind = widget.workspace.scope.assetKinds.of(widget.path);
    return WorkspaceKeyScope(
      onKey: _onKey,
      child: ColoredBox(
        color: EditorTheme.panelBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspaceHeader(
              icon: Icons.data_object,
              title: 'JSON',
              file: name,
              showHistory: false,
              tools: const [EditorBadge(label: 'Read-only')],
              trailing: [
                EditorButton(
                  label: 'Copy all',
                  kind: EditorButtonKind.ghost,
                  onPressed: _lines.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: _lines.join('\n')),
                        ),
                ),
                EditorButton(
                  label: 'Open in system app',
                  kind: EditorButtonKind.ghost,
                  onPressed: () => _index.openExternally(widget.path),
                ),
              ],
              fullScreen: widget.workspace.fullScreen,
              onToggleFullScreen: widget.workspace.onToggleFullScreen,
              onClose: widget.workspace.onClose,
            ),
            _searchBar(kind),
            if (_problem case final problem?)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Text(
                  problem,
                  style: TextStyle(color: EditorTheme.warning, fontSize: 11),
                ),
              ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _searchBar(AssetKind kind) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            // A kind's label names a group of them: Animators, Screens.
            'No window for ${kind == AssetKind.data ? 'this file' : kind.label.toLowerCase()} '
            'is installed: it is shown as it is.',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        EditorSearchField(
          hint: 'Find (${EditorKeys.withPrimary('F')})',
          width: 220,
          focusNode: _searchFocus,
          onChanged: search,
          onSubmitted: (_) => step(),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 70,
          child: Text(
            _query.isEmpty
                ? ''
                : _matches.isEmpty
                ? 'None'
                : '${_current + 1} of ${_matches.length}',
            textAlign: TextAlign.center,
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
          ),
        ),
        EditorIconButton(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'The match before',
          onTap: _matches.isEmpty ? null : () => step(back: true),
        ),
        EditorIconButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'The next match (Enter)',
          onTap: _matches.isEmpty ? null : step,
        ),
      ],
    ),
  );

  Widget _body() {
    if (!_loaded) {
      return Center(
        child: Text(
          'Reading…',
          style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
        ),
      );
    }
    final digits = '${_lines.length}'.length;
    // Every line as wide as the widest, which scrolls sideways when the
    // window is narrower: nothing is cut off at its edge.
    final contentWidth = _gutterWidth + _textWidth + 16;
    return ColoredBox(
      color: const Color(0xFF15181D),
      child: LayoutBuilder(
        builder: (context, box) => Scrollbar(
          controller: _across,
          child: SingleChildScrollView(
            controller: _across,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: math.max(box.maxWidth, contentWidth),
              height: box.maxHeight,
              child: _lineList(digits),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lineList(int digits) => SelectionArea(
    child: ListView.builder(
      controller: _scroll,
      itemExtent: lineHeight,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final line = _lines[i];
        final spans = <TextSpan>[];
        var from = 0;
        for (final m in _byLine[i] ?? const <int>[]) {
          final at = _matches[m].$2, end = _ends[m];
          if (at < from || end > line.length) continue;
          if (at > from) {
            spans.add(TextSpan(text: line.substring(from, at)));
          }
          final isShown = m == _current;
          spans.add(
            TextSpan(
              text: line.substring(at, end),
              style: TextStyle(
                backgroundColor: isShown
                    ? EditorTheme.accent
                    : EditorTheme.accent.withValues(alpha: 0.35),
                color: isShown ? Colors.white : null,
              ),
            ),
          );
          from = end;
        }
        if (from < line.length) {
          spans.add(TextSpan(text: line.substring(from)));
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionContainer.disabled(
              child: SizedBox(
                width: 14 + digits * 8.0,
                child: Text(
                  '${i + 1}',
                  textAlign: TextAlign.right,
                  style: _mono.copyWith(color: EditorTheme.textMuted),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: spans),
                style: _mono,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
            ),
          ],
        );
      },
    ),
  );
}
