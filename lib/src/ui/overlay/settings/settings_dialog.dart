import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_editor_core/io.dart';
import 'package:just_signals/just_signals.dart';

import 'package:just_editor_core/host.dart';
import '../../level_designer/panels/tool_palette.dart';
import '../shared/transform_toolbar.dart';
import 'settings_controls.dart';
import 'shortcut_row.dart';
import '../shared/quick_snap_bar.dart';
import '../../level_designer_3d/panels/space_status_controls.dart';

part 'settings_catalog.dart';

/// The gear at the foot of the viewport, bottom right, that opens the
/// settings — framed like the play controls and the transform column above
/// it.
class SettingsGearButton extends StatelessWidget {
  const SettingsGearButton({
    super.key,
    required this.scope,
    required this.settings,
  });

  final EditorScope scope;
  final OverlayUiSettings settings;

  /// How tall it stands, for what has to clear it: the tool strip above
  /// it. One of the strip's buttons in the strip's frame.
  static double get height =>
      FloatingToolFrame.heightFor(ToolStripButton.extent);

  /// How wide it stands, for what stands beside it: the messages, to its
  /// left. The tool strip's width in the frame's line.
  static const double width = ToolPalette.width + 2;

  @override
  Widget build(BuildContext context) {
    final bound = scope.commands.bindingsFor(EditorSettingsDialog.commandId);
    return SignalBuilder<bool>(
      signal: scope.chrome.settingsOpen,
      // As wide as the tool strip above it, with the strip's button.
      builder: (context, open, _) => FloatingToolFrame(
        settings: settings,
        child: SizedBox(
          width: ToolPalette.width,
          child: Padding(
            padding: ToolStripButton.padding,
            child: EditorToolButton(
              icon: Icons.settings_outlined,
              tooltip: 'Editor settings',
              shortcut: bound.isEmpty ? null : bound.first.shortcut,
              showShortcut: false,
              isActive: open,
              onTap: scope.chrome.toggleSettings,
              width: double.infinity,
              height: ToolStripButton.buttonHeight,
              iconSize: ToolStripButton.iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

/// Puts the settings dialog over the editor while it is open, in the frame
/// the sprite editor's dialog has. A click on the dim closes it: nothing in
/// it is ever unsaved.
class EditorSettingsHost extends StatelessWidget {
  const EditorSettingsHost({super.key, required this.scope});

  final EditorScope scope;

  static const Key scrimKey = Key('settingsScrim');

  @override
  Widget build(BuildContext context) => SignalBuilder2<bool, OverlayUiSettings>(
    signal1: scope.chrome.settingsOpen,
    signal2: scope.prefs.settings,
    builder: (context, open, settings, _) {
      if (!open) return const SizedBox.shrink();
      void close() => scope.chrome.settingsOpen.value = false;
      return EditorDialogFrame(
        cornerRadius: settings.cornerRadius + 6,
        borderColor: settings.accent,
        onDismiss: close,
        scrimKey: scrimKey,
        child: EditorSettingsDialog(scope: scope, onClose: close),
      );
    },
  );
}

/// The editor's settings: a page per subject down the left, the settings of
/// the one picked on the right, and a search over all of them.
///
/// Every change applies at once and is saved; a slider previews while it is
/// dragged and saves when it is let go.
class EditorSettingsDialog extends StatefulWidget {
  const EditorSettingsDialog({
    super.key,
    required this.scope,
    required this.onClose,
  });

  final EditorScope scope;
  final VoidCallback onClose;

  /// The command that opens and shuts it: Ctrl+, unless a module rebinds
  /// it.
  static const String commandId = 'editor.settings';

  @override
  State<EditorSettingsDialog> createState() => _EditorSettingsDialogState();
}

/// A page in the list on the left.
class _Page {
  const _Page(this.id, this.label, this.icon, this.description, {this.section});

  final String id;
  final String label;
  final IconData icon;
  final String description;

  /// The module section the page shows, for a module's page.
  final SettingsSection? section;
}

/// One of the editor's own settings: where it lives, what it is called,
/// what it does, whether it has moved, and its control.
class _Setting {
  const _Setting({
    required this.page,
    required this.label,
    required this.hint,
    required this.isDefault,
    required this.reset,
    required this.control,
    this.keywords = '',
    this.group,
  });

  final String page;
  final String label;
  final String hint;

  /// The heading it sits under within its page, when the page has them.
  final String? group;

  /// More words to be found by, beyond the label and hint.
  final String keywords;
  final bool isDefault;
  final OverlayUiSettings Function(OverlayUiSettings s) reset;
  final Widget control;

  bool matches(String query) =>
      '$label $hint $keywords'.toLowerCase().contains(query);
}

/// A command and the keys bound to it, for the Keyboard page.
typedef _Shortcut = ({
  String group,
  DesignerCommand command,
  List<String> keys,
});

class _EditorSettingsDialogState extends State<EditorSettingsDialog> {
  static final SettingPref<String> _lastPage = SettingPref.text(
    'editor.settings.page',
    _appearance,
  );

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late String _pageId = widget.scope.prefs.get(_lastPage);
  bool _confirmingReset = false;

  /// What the last export or import did, said in the footer until the next
  /// change of page.
  String? _note;
  bool _noteIsError = false;

  EditorScope get _scope => widget.scope;
  String get _query => _search.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    // Typing goes straight to the search, as in any settings window.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _onSearch() => setState(() {
    _confirmingReset = false;
    _note = null;
  });

  @override
  void dispose() {
    _previewSoon?.cancel();
    _search
      ..removeListener(_onSearch)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_Page> get _pages => [
    const _Page(
      _appearance,
      'Appearance',
      Icons.palette_outlined,
      'How the editor looks: its accent, spacing, corners and motion.',
    ),
    const _Page(
      _accessibility,
      'Accessibility',
      Icons.accessibility_new_rounded,
      'Reading, seeing, moving and pointing: the editor made to suit you. '
          'The sprite and input editors follow it too.',
    ),
    const _Page(
      _editing,
      'Editing',
      Icons.edit_note_rounded,
      'How far undo reaches, and what asks first.',
    ),
    const _Page(
      _snapping,
      'Snapping',
      Icons.straighten_rounded,
      'What moving, turning and scaling snap to, and in what steps.',
    ),
    const _Page(
      _viewport,
      'Viewport',
      Icons.grid_4x4_rounded,
      'The grid the level is built on, and how the editor draws over the '
          'game.',
    ),
    const _Page(
      _saving,
      'Saving',
      Icons.save_outlined,
      'Keeping your work safe, and where the editor starts.',
    ),
    const _Page(
      _playing,
      'Play-testing',
      Icons.play_circle_outline_rounded,
      'What happens while the game runs inside the editor.',
    ),
    const _Page(
      _console,
      'Console & messages',
      Icons.terminal_rounded,
      'What the Console keeps and shows, and which messages appear over '
          'the editor.',
    ),
    const _Page(
      _performance,
      'Performance',
      Icons.speed_rounded,
      'The frame rate the game is measured against, and what the editor '
          'spends keeping its readouts live.',
    ),
    const _Page(
      _keyboard,
      'Keyboard',
      Icons.keyboard_outlined,
      'Every command, and the keys that run it. Click a command\'s keys to '
          'change them.',
    ),
    for (final section in _scope.settingsSections)
      _Page(
        'module:${section.id}',
        section.title,
        Icons.extension_outlined,
        'Settings a module adds.',
        section: section,
      ),
  ];

  void _open(String id) {
    _search.clear();
    setState(() {
      _pageId = id;
      _confirmingReset = false;
      _note = null;
    });
    _scope.prefs.set(_lastPage, id);
  }

  // ── Changing settings ────────────────────────────────────────────────────

  Timer? _previewSoon;
  OverlayUiSettings? _previewing;

  /// How often a slider mid-drag shows what it would do: a size or a colour
  /// draws the whole editor again, which every pointer move was too often.
  static const Duration _previewEvery = Duration(milliseconds: 100);

  /// Shows [next] without saving it: a slider mid-drag. At most once per
  /// [_previewEvery], the last value of each stretch.
  void _preview(OverlayUiSettings next) {
    _previewing = next;
    _previewSoon ??= Timer(_previewEvery, () {
      _previewSoon = null;
      final shown = _previewing;
      _previewing = null;
      if (shown != null && mounted) _scope.prefs.settings.value = shown;
    });
  }

  void _save(OverlayUiSettings next) {
    _previewSoon?.cancel();
    _previewSoon = null;
    _previewing = null;
    _scope.prefs.update(next);
    _scope.theme.select(next.themeId);
  }

  Widget _slider(
    OverlayUiSettings s,
    double value,
    SettingRange range,
    double step,
    OverlayUiSettings Function(double v) apply, {
    double displayScale = 1,
    int decimals = 0,
    String unit = '',
    bool preview = true,
  }) => EditorSlider(
    value: value,
    min: range.min,
    max: range.max,
    step: step,
    accent: s.accent,
    displayScale: displayScale,
    decimals: decimals,
    unit: unit,
    // A limit that drops what is past it — undo steps, Console lines — is
    // not tried out mid-drag: going under on the way would drop them for
    // good. It applies when the drag ends.
    onChanged: preview ? (v) => _preview(apply(v)) : (_) {},
    onChangeEnd: (v) => _save(apply(v)),
  );

  _Setting _toggleSetting(
    OverlayUiSettings s, {
    required String page,
    required String label,
    required String hint,
    required bool value,
    required OverlayUiSettings Function(bool v) apply,
    bool fallback = false,
    String keywords = '',
    String? group,
  }) => _Setting(
    page: page,
    group: group,
    label: label,
    hint: hint,
    keywords: keywords,
    isDefault: value == fallback,
    reset: (_) => apply(fallback),
    control: EditorToggle(
      value: value,
      label: label,
      accent: s.accent,
      onChanged: (v) => _save(apply(v)),
    ),
  );

  // ── The Keyboard page ────────────────────────────────────────────────────

  static String _groupOf(String commandId) {
    final prefix = commandId.split('.').first;
    return switch (prefix) {
      'editor' => 'Editor',
      'designer' => 'Level Designer',
      'dock' => 'Docks',
      'timeline' => 'Timeline',
      '' => 'Other',
      _ => '${prefix[0].toUpperCase()}${prefix.substring(1)}',
    };
  }

  List<_Shortcut> _shortcuts() {
    final registry = _scope.commands;
    final all = [
      for (final command in registry.all)
        (
          group: _groupOf(command.id),
          command: command,
          keys: [for (final b in registry.bindingsFor(command.id)) b.shortcut],
        ),
    ];
    all.sort((a, b) {
      final byGroup = a.group.compareTo(b.group);
      return byGroup != 0
          ? byGroup
          : a.command.label.toLowerCase().compareTo(
              b.command.label.toLowerCase(),
            );
    });
    return all;
  }

  /// [chords] now run [commandId]. With [takeFrom], that command gives up
  /// [chord]. A command back at the keys it was built with is no longer a
  /// change. Chords are as settings store them ([KeyBinding.savedChord]),
  /// so the file reads the same on every OS.
  void _setShortcut(
    OverlayUiSettings s,
    String commandId,
    List<String> chords, {
    String? takeFrom,
    String? chord,
  }) {
    final registry = _scope.commands;
    final next = {...s.shortcuts};
    void put(String id, List<String> keys) {
      final built = [
        for (final b in registry.builtBindingsFor(id)) b.savedChord,
      ];
      if (listEquals(built, keys)) {
        next.remove(id);
      } else {
        next[id] = keys;
      }
    }

    if (takeFrom != null) {
      put(takeFrom, [
        for (final b in registry.bindingsFor(takeFrom))
          if (b.savedChord != chord) b.savedChord,
      ]);
    }
    put(commandId, chords);
    // Laid over the registry now, so the page shows it as it rebuilds.
    registry.applyShortcuts(next);
    _save(s.copyWith(shortcuts: next));
  }

  void _resetShortcut(OverlayUiSettings s, String commandId) {
    final next = {...s.shortcuts}..remove(commandId);
    _scope.commands.applyShortcuts(next);
    _save(s.copyWith(shortcuts: next));
  }

  static bool _shortcutMatches(_Shortcut s, String query) =>
      s.command.label.toLowerCase().contains(query) ||
      s.group.toLowerCase().contains(query) ||
      s.keys.any((k) => k.toLowerCase().contains(query));

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => SignalBuilder<OverlayUiSettings>(
    signal: _scope.prefs.settings,
    builder: (context, s, _) => _dialog(context, s),
  );

  Widget _dialog(BuildContext context, OverlayUiSettings s) {
    final accent = s.accent;
    final pages = _pages;
    final page = pages.firstWhere(
      (p) => p.id == _pageId,
      orElse: () => pages.first,
    );
    final settings = _settingsFor(s);
    final query = _query;
    final searching = query.isNotEmpty;

    // What the list on the left marks: a page with a moved setting, and
    // while searching, how many hits each page has.
    final modifiedPages = {
      for (final def in settings)
        if (!def.isDefault) def.page,
      if (s.shortcuts.isNotEmpty) _keyboard,
    };
    final hits = <String, int>{};
    if (searching) {
      for (final def in settings) {
        if (def.matches(query)) hits[def.page] = (hits[def.page] ?? 0) + 1;
      }
      final keys = _shortcuts().where((x) => _shortcutMatches(x, query));
      if (keys.isNotEmpty) hits[_keyboard] = keys.length;
      for (final p in pages) {
        if (p.section != null && p.label.toLowerCase().contains(query)) {
          hits[p.id] = 1;
        }
      }
    }

    // Its text is the chrome's: the look over the chrome shows the size and
    // weight being picked as they change.
    return EditorLook(
      child: Material(
        color: EditorTheme.dialogBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(
              accent: accent,
              search: _search,
              searchFocus: _searchFocus,
              onClose: widget.onClose,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Sidebar(
                    pages: pages,
                    selectedId: searching ? null : page.id,
                    modified: modifiedPages,
                    hits: searching ? hits : null,
                    accent: accent,
                    onSelect: _open,
                  ),
                  Expanded(
                    child: searching
                        ? _results(s, settings, pages, query)
                        : _page(s, page, settings),
                  ),
                ],
              ),
            ),
            _footer(s, page, settings, searching),
          ],
        ),
      ),
    );
  }

  Widget _page(OverlayUiSettings s, _Page page, List<_Setting> settings) {
    final section = page.section;
    final List<Widget> body;
    if (section != null) {
      body = [_ModuleCard(section: section, prefs: _scope.prefs)];
    } else if (page.id == _keyboard) {
      body = _keyboardRows(s, _shortcuts());
    } else {
      body = _rows(s, [
        for (final def in settings)
          if (def.page == page.id) def,
      ]);
    }
    return _PageBody(
      key: ValueKey(page.id),
      title: page.label,
      description: page.description,
      children: body,
    );
  }

  Widget _results(
    OverlayUiSettings s,
    List<_Setting> settings,
    List<_Page> pages,
    String query,
  ) {
    final children = <Widget>[];
    for (final p in pages) {
      final section = p.section;
      if (section != null) {
        if (p.label.toLowerCase().contains(query)) {
          children
            ..add(_Caption(p.label))
            ..add(_ModuleCard(section: section, prefs: _scope.prefs));
        }
      } else if (p.id == _keyboard) {
        final keys = [
          for (final x in _shortcuts())
            if (_shortcutMatches(x, query)) x,
        ];
        if (keys.isNotEmpty) {
          children
            ..add(_Caption(p.label))
            ..addAll(_keyboardRows(s, keys, grouped: false));
        }
      } else {
        final defs = [
          for (final def in settings)
            if (def.page == p.id && def.matches(query)) def,
        ];
        if (defs.isNotEmpty) {
          children
            ..add(_Caption(p.label))
            ..addAll(_rows(s, defs, headings: false));
        }
      }
    }
    return _PageBody(
      key: const ValueKey('search'),
      title: 'Search',
      description: children.isEmpty
          ? 'Nothing matches “${_search.text.trim()}”.'
          : 'Everything that matches “${_search.text.trim()}”.',
      children: children,
    );
  }

  List<Widget> _rows(
    OverlayUiSettings s,
    List<_Setting> defs, {
    bool headings = true,
  }) => [
    for (var i = 0; i < defs.length; i++) ...[
      // A page's own headings: a new one wherever the group changes.
      if (headings &&
          defs[i].group != null &&
          (i == 0 || defs[i].group != defs[i - 1].group))
        _Caption(defs[i].group!)
      else if (i > 0)
        const _RowDivider(),
      SettingRow(
        label: defs[i].label,
        hint: defs[i].hint,
        control: defs[i].control,
        accent: s.accent,
        isModified: !defs[i].isDefault,
        onReset: () => _save(defs[i].reset(s)),
      ),
    ],
  ];

  List<Widget> _keyboardRows(
    OverlayUiSettings s,
    List<_Shortcut> shortcuts, {
    bool grouped = true,
  }) {
    final rows = <Widget>[];
    String? group;
    for (final x in shortcuts) {
      if (grouped && x.group != group) {
        group = x.group;
        rows.add(_Caption(group));
      }
      final id = x.command.id;
      rows.add(
        ShortcutRow(
          key: ValueKey('shortcut:$id'),
          scope: _scope,
          command: x.command,
          keys: x.keys,
          isModified: s.shortcuts.containsKey(id),
          accent: s.accent,
          onChanged: (chords, {takeFrom, chord}) =>
              _setShortcut(s, id, chords, takeFrom: takeFrom, chord: chord),
          onReset: () => _resetShortcut(s, id),
        ),
      );
    }
    return rows;
  }

  // ── Export and import ─────────────────────────────────────────────────

  /// The project's settings file: shared with whoever works on it, or
  /// carried to another machine.
  static const String settingsFilePath = '.editor/settings.json';

  File get _settingsFile => File('${Directory.current.path}/$settingsFilePath');

  void _say(String note, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _note = note;
      _noteIsError = error;
    });
  }

  Future<void> _exportToProject() async {
    try {
      final file = _settingsFile;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        OverlaySettingsStore.export(_scope.prefs.settings.value),
      );
      _say('Saved to $settingsFilePath.');
    } catch (error) {
      _say('Could not save $settingsFilePath: $error', error: true);
    }
  }

  Future<void> _exportToClipboard() async {
    await Clipboard.setData(
      ClipboardData(
        text: OverlaySettingsStore.export(_scope.prefs.settings.value),
      ),
    );
    _say('Copied to the clipboard.');
  }

  Future<void> _importFromProject() async {
    final file = _settingsFile;
    if (!file.existsSync()) {
      _say('There is no $settingsFilePath in the project.', error: true);
      return;
    }
    try {
      _import(await file.readAsString(), from: settingsFilePath);
    } catch (error) {
      _say('Could not read $settingsFilePath: $error', error: true);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    _import(data?.text ?? '', from: 'the clipboard');
  }

  void _import(String text, {required String from}) {
    final current = _scope.prefs.settings.value;
    final imported = OverlaySettingsStore.import(text, current);
    if (imported == null) {
      _say('Nothing in $from is a settings export.', error: true);
      return;
    }
    _scope.commands.applyShortcuts(imported.shortcuts);
    _save(imported);
    _say(
      imported == current
          ? 'Imported from $from: it was all as it is.'
          : 'Imported from $from.',
    );
  }

  Widget _footer(
    OverlayUiSettings s,
    _Page page,
    List<_Setting> settings,
    bool searching,
  ) {
    final accent = s.accent;
    final onPage = [
      for (final def in settings)
        if (def.page == page.id && !def.isDefault) def,
    ];
    final anyMoved = s != const OverlayUiSettings.defaults();
    final onKeyboard = !searching && page.id == _keyboard;

    final List<Widget> children;
    if (_confirmingReset) {
      children = [
        Icon(Icons.warning_amber_rounded, size: 15, color: EditorTheme.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Put every editor setting and key back to its default? A '
            'module’s own settings stay as they are.',
            style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
          ),
        ),
        _FooterButton(
          label: 'Cancel',
          color: EditorTheme.textSecondary,
          onPressed: () => setState(() => _confirmingReset = false),
        ),
        const SizedBox(width: 6),
        _FooterButton(
          label: 'Reset all',
          color: EditorTheme.error,
          filled: true,
          onPressed: () {
            setState(() => _confirmingReset = false);
            _save(const OverlayUiSettings.defaults());
          },
        ),
      ];
    } else {
      children = [
        _FooterMenu(
          label: 'Export…',
          color: EditorTheme.textSecondary,
          items: [
            ('Save to the project', Icons.save_alt_rounded, _exportToProject),
            ('Copy to the clipboard', Icons.copy_rounded, _exportToClipboard),
          ],
        ),
        const SizedBox(width: 2),
        _FooterMenu(
          label: 'Import…',
          color: EditorTheme.textSecondary,
          items: [
            ('From the project', Icons.file_open_outlined, _importFromProject),
            (
              'Paste from the clipboard',
              Icons.content_paste_rounded,
              _importFromClipboard,
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _note ??
                'Changes apply as you make them, and are kept for next time.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _note == null
                  ? EditorTheme.textMuted
                  : _noteIsError
                  ? EditorTheme.warning
                  : EditorTheme.textSecondary,
              fontSize: 10.5,
            ),
          ),
        ),
        if (onKeyboard) ...[
          _FooterButton(
            label: 'Reset keys',
            color: accent,
            onPressed: s.shortcuts.isEmpty
                ? null
                : () {
                    _scope.commands.applyShortcuts(const {});
                    _save(s.copyWith(shortcuts: const {}));
                  },
          ),
          const SizedBox(width: 6),
        ],
        if (!searching && page.section == null && page.id != _keyboard) ...[
          _FooterButton(
            label: 'Reset page',
            color: accent,
            onPressed: onPage.isEmpty
                ? null
                : () {
                    var next = s;
                    for (final def in onPage) {
                      next = def.reset(next);
                    }
                    _save(next);
                  },
          ),
          const SizedBox(width: 6),
        ],
        _FooterButton(
          label: 'Reset all…',
          color: EditorTheme.textSecondary,
          onPressed: anyMoved
              ? () => setState(() => _confirmingReset = true)
              : null,
        ),
      ];
    }
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: EditorTheme.menuBg,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(children: children),
    );
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────────

/// Title, search and close, in the sprite editor's 34 px bar.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.accent,
    required this.search,
    required this.searchFocus,
    required this.onClose,
  });

  final Color accent;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: EditorTheme.menuBg,
      border: Border(
        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
    ),
    child: Row(
      children: [
        Icon(Icons.settings_outlined, size: 15, color: accent),
        const SizedBox(width: 6),
        Text(
          'Editor Settings',
          style: TextStyle(
            color: EditorTheme.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 16),
        EditorSearchField(
          controller: search,
          focusNode: searchFocus,
          width: 260,
          hint: 'Search settings and shortcuts',
          onChanged: (_) {},
        ),
        const Spacer(),
        EditorIconButton(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          shortcut: 'Esc',
          activeColor: accent,
          onTap: onClose,
        ),
      ],
    ),
  );
}

/// The pages, down the left; the modules' under a caption of their own.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.pages,
    required this.selectedId,
    required this.modified,
    required this.hits,
    required this.accent,
    required this.onSelect,
  });

  final List<_Page> pages;

  /// Null while searching: the results are not one page.
  final String? selectedId;
  final Set<String> modified;

  /// Hits per page while searching, else null.
  final Map<String, int>? hits;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final builtIn = [
      for (final p in pages)
        if (p.section == null) p,
    ];
    final modules = [
      for (final p in pages)
        if (p.section != null) p,
    ];
    Widget item(_Page p) => _SidebarItem(
      page: p,
      selected: p.id == selectedId,
      modified: modified.contains(p.id),
      hits: hits == null ? null : hits![p.id] ?? 0,
      accent: accent,
      onTap: () => onSelect(p.id),
    );
    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: EditorTheme.menuBg,
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final p in builtIn) item(p),
          if (modules.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Text(
                'MODULES',
                style: TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final p in modules) item(p),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.page,
    required this.selected,
    required this.modified,
    required this.hits,
    required this.accent,
    required this.onTap,
  });

  final _Page page;
  final bool selected;
  final bool modified;
  final int? hits;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dimmed = hits == 0;
    final tone = selected
        ? EditorTheme.textPrimary
        : dimmed
        ? EditorTheme.textMuted.withValues(alpha: 0.5)
        : EditorTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: accent.withValues(alpha: 0.08),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(page.icon, size: 15, color: selected ? accent : tone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    page.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tone,
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (hits != null && hits! > 0)
                  Text(
                    '$hits',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (hits == null && modified)
                  Tooltip(
                    message: 'Something here is not at its default',
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page's title, what it is for, and its rows, no wider than reads well.
class _PageBody extends StatelessWidget {
  const _PageBody({
    super.key,
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
    children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    ],
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: EditorTheme.textMuted,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    ),
  );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.05));
}

/// What a module put on the settings, in a card of its own.
class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.section, required this.prefs});

  final SettingsSection section;
  final EditorPrefs prefs;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: EditorTheme.surfaceBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: section.build(context, prefs),
  );
}

/// A footer button whose choices open in a menu above it.
class _FooterMenu extends StatelessWidget {
  const _FooterMenu({
    required this.label,
    required this.color,
    required this.items,
  });

  final String label;
  final Color color;
  final List<(String, IconData, Future<void> Function())> items;

  @override
  Widget build(BuildContext context) => _FooterButton(
    label: label,
    color: color,
    onPressed: () async {
      final box = context.findRenderObject()! as RenderBox;
      final at = box.localToGlobal(Offset(0, -8.0 * items.length - 24));
      final run = await showEditorMenu<Future<void> Function()>(context, at, [
        for (final (text, icon, action) in items)
          editorMenuItem(action, text, icon: icon),
      ]);
      await run?.call();
    },
  );
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: filled ? Colors.white : color,
      backgroundColor: filled ? color.withValues(alpha: 0.85) : null,
      disabledForegroundColor: EditorTheme.textMuted.withValues(alpha: 0.5),
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    child: Text(label),
  );
}
