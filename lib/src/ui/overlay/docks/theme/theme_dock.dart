/// The UI theme editor: the tokens on the left, what they look like on the
/// right.
///
/// A theme is one file for a whole game's interface — a widget names a
/// *role* rather than a colour — so this is where a game is restyled, and
/// the gallery beside it is built from the same widgets a canvas is, to
/// save opening the game to find out.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../../../core/constants/editor_constants.dart';
import '../../../inspector/field_rows.dart';
import '../../../inspector/field_style.dart';
import '../../../inspector/ui_field_editors.dart';
import '../../../widgets/scrubbable_number_field.dart';
import '../shared/dock_widgets.dart';

class ThemeDock extends StatefulWidget {
  const ThemeDock({super.key, required this.root, this.onSaved});

  /// The project the themes are read from and written to.
  final String root;

  /// Called after a save, so every canvas using the theme is restyled.
  final Future<void> Function(String path)? onSaved;

  @override
  State<ThemeDock> createState() => _ThemeDockState();
}

class _ThemeDockState extends State<ThemeDock> {
  /// The file being edited, project-relative.
  String? _path;

  /// What is in it now, changed as the tokens are edited.
  jge.UiTheme _theme = jge.UiTheme.fallback;

  bool _dirty = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _openFirst();
  }

  /// The themes in the project, by path.
  List<String> get _themes {
    final root = Directory('${widget.root}/assets');
    if (!root.existsSync()) return const [];
    return [
      for (final entry in root.listSync(recursive: true))
        if (entry is File && entry.path.endsWith('.uitheme.json'))
          entry.path
              .replaceAll(r'\', '/')
              .replaceFirst('${widget.root.replaceAll(r'\', '/')}/', ''),
    ]..sort();
  }

  void _openFirst() {
    final found = _themes;
    if (found.isEmpty) return;
    _open(found.first);
  }

  void _open(String path) {
    final file = File('${widget.root}/$path');
    if (!file.existsSync()) return;
    setState(() {
      _path = path;
      _theme = jge.UiTheme.parse(file.readAsStringSync());
      _dirty = false;
      _message = null;
    });
  }

  void _set(jge.UiTheme next) => setState(() {
    _theme = next;
    _dirty = true;
  });

  Future<void> _save() async {
    final path = _path;
    if (path == null) return;
    const encoder = JsonEncoder.withIndent('  ');
    // Written before anything is awaited: the file on disk is the record,
    // and a theme half-saved is worse than one saved slowly.
    File(
      '${widget.root}/$path',
    ).writeAsStringSync(encoder.convert(_theme.toJson()));
    // Every canvas drawn with it is restyled on the next frame.
    await widget.onSaved?.call(path);
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _message = 'Saved $path';
    });
  }

  void _create() {
    const path = 'assets/ui/default.uitheme.json';
    final file = File('${widget.root}/$path');
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      file.writeAsStringSync(
        encoder.convert(
          jge.UiTheme.fallback.copyWith(name: 'default').toJson(),
        ),
      );
    }
    _open(path);
  }

  @override
  Widget build(BuildContext context) {
    final themes = _themes;
    if (_path == null) {
      return EditorEmptyState(
        icon: Icons.palette_outlined,
        title: themes.isEmpty ? 'No theme yet' : 'No theme open',
        hint: themes.isEmpty
            ? 'A theme is one file for a whole game’s interface: '
                  'colours, text and the sounds a menu makes.'
            : 'Open one of the project’s themes.',
        actionLabel: themes.isEmpty ? 'Make one' : null,
        actionIcon: Icons.add,
        onAction: themes.isEmpty ? _create : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(themes),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 280, child: _tokens()),
              VerticalDivider(width: 1, color: EditorTheme.border),
              Expanded(child: _gallery()),
            ],
          ),
        ),
      ],
    );
  }

  // The toolbar's height and line, with the theme picker filling it.
  Widget _header(List<String> themes) => Container(
    height: EditorToolbar.height,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: EditorTheme.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: DropdownEditorRow(
            label: 'Theme',
            value: _path!,
            options: themes,
            onChanged: _open,
          ),
        ),
        const SizedBox(width: 12),
        if (_message != null)
          Text(
            _message!,
            style: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
          ),
        const SizedBox(width: 8),
        EditorButton(
          label: _dirty ? 'Save' : 'Saved',
          kind: _dirty ? EditorButtonKind.primary : EditorButtonKind.ghost,
          onPressed: _dirty ? _save : null,
        ),
      ],
    ),
  );

  Widget _tokens() => SingleChildScrollView(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Colours'),
        for (final role in jge.UiPalette.roles) ...[
          ColorEditorRow(
            label: role,
            paintStyle: jge.ShapePaintStyle(
              color: _theme.palette.byName(role) ?? const Color(0xFF000000),
            ),
            onChanged: (style) =>
                _set(_theme.copyWith(palette: _withRole(role, style.color))),
          ),
          const SizedBox(height: 6),
        ],
        const _SectionLabel('Text'),
        for (final role in const ['title', 'body', 'caption', 'button']) ...[
          UiTextStyleEditorRow(
            label: role,
            style: _theme.textStyles[role] ?? const jge.UiTextStyle(),
            fontFamilies: jge.UiFonts.families,
            // What the role looks like when this theme says nothing about
            // it: the engine's default for that role, in this theme's
            // colours.
            inherited: jge.UiTheme(palette: _theme.palette).textStyle(role),
            inheritedFrom: 'the default',
            onChanged: (style) => _set(
              _theme.copyWith(textStyles: {..._theme.textStyles, role: style}),
            ),
          ),
          const SizedBox(height: 6),
        ],
        const _SectionLabel('Shape'),
        ScrubFieldRow(
          label: 'Corner',
          value: _theme.radius,
          scrubConfig: const NumberScrubConfig(fractionDigits: 0),
          onChanged: (v) => _set(_theme.copyWith(radius: v)),
        ),
        const SizedBox(height: 6),
        ScrubFieldRow(
          label: 'Spacing',
          value: _theme.spacing,
          scrubConfig: const NumberScrubConfig(fractionDigits: 0),
          onChanged: (v) => _set(_theme.copyWith(spacing: v)),
        ),
        const SizedBox(height: 10),
        const _SectionLabel('Sounds'),
        AssetRefEditorRow(
          label: 'Hover',
          value: _theme.sounds.hover,
          extensions: const ['wav', 'mp3', 'ogg'],
          onChanged: (path) => _set(
            _theme.copyWith(
              sounds: jge.UiSounds(
                hover: path,
                press: _theme.sounds.press,
                toggle: _theme.sounds.toggle,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        AssetRefEditorRow(
          label: 'Press',
          value: _theme.sounds.press,
          extensions: const ['wav', 'mp3', 'ogg'],
          onChanged: (path) => _set(
            _theme.copyWith(
              sounds: jge.UiSounds(
                hover: _theme.sounds.hover,
                press: path,
                toggle: _theme.sounds.toggle,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  jge.UiPalette _withRole(String role, Color color) => switch (role) {
    'primary' => _theme.palette.copyWith(primary: color),
    'onPrimary' => _theme.palette.copyWith(onPrimary: color),
    'surface' => _theme.palette.copyWith(surface: color),
    'onSurface' => _theme.palette.copyWith(onSurface: color),
    'accent' => _theme.palette.copyWith(accent: color),
    'danger' => _theme.palette.copyWith(danger: color),
    'success' => _theme.palette.copyWith(success: color),
    'muted' => _theme.palette.copyWith(muted: color),
    'outline' => _theme.palette.copyWith(outline: color),
    _ => _theme.palette,
  };

  /// What the theme looks like, built from the same widgets a canvas is.
  Widget _gallery() => Theme(
    data: _theme.toThemeData(),
    child: Material(
      color: _theme.palette.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle(
          style: _theme.textStyle('body').toTextStyle(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The quick brown fox',
                style: _theme.textStyle('title').toTextStyle(),
              ),
              const SizedBox(height: 4),
              const Text('Body text, as a line of dialogue would read.'),
              const SizedBox(height: 4),
              Text(
                'A caption underneath.',
                style: _theme.textStyle('caption').toTextStyle(),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Play')),
                  FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      backgroundColor: _theme.palette.danger,
                    ),
                    child: const Text('Quit'),
                  ),
                  FilledButton(onPressed: null, child: const Text('Locked')),
                  Switch(value: true, onChanged: (_) {}),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 260,
                child: Slider(value: 0.6, onChanged: (_) {}),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_theme.radius),
                  child: LinearProgressIndicator(
                    value: 0.65,
                    color: _theme.palette.accent,
                    backgroundColor: _theme.palette.outline,
                    minHeight: 8,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 260,
                padding: EdgeInsets.all(_theme.spacing),
                decoration: BoxDecoration(
                  color: _theme.palette.surface,
                  border: Border.all(color: _theme.palette.outline),
                  borderRadius: BorderRadius.circular(_theme.radius),
                ),
                child: const Text(
                  'A panel, at the theme’s corner and '
                  'spacing.',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: InspectorField.labelStyle.copyWith(
        color: EditorTheme.primaryBright,
        letterSpacing: 0.5,
      ),
    ),
  );
}
