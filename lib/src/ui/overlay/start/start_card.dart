import 'dart:io' show FileSystemException;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/plugin/editor_plugin.dart';
import '../../../core/prefs/recent_scenes.dart';
import '../../../core/state/transform_mode.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../../extension/editor_contributions.dart';
import '../../dialogs/create_scene_overlay.dart';
import '../../kit/kit.dart';
import '../settings/overlay_ui_settings.dart';

/// What the viewport shows while no scene is open: the editor's backdrop in
/// place of the game, and on it [EditorStartCard] — how to use the editor.
///
/// It covers the canvas and takes every press, so the world underneath —
/// the game as it booted — can be neither seen nor picked. The chrome
/// floats over it as ever: the module buttons, the gear, the docks.
class EditorStartCover extends StatelessWidget {
  const EditorStartCover({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  @override
  Widget build(BuildContext context) => SignalBuilder<OverlayUiSettings>(
    signal: plugin.scope.prefs.settings,
    builder: (context, settings, _) => ColoredBox(
      color: settings.backdrop ?? EditorTheme.surfaceDarkest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Clear of the module buttons along the top and the gear in the
          // corner; the card scrolls when the room is short.
          const padding = EdgeInsets.fromLTRB(24, 72, 24, 32);
          return SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - padding.vertical,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: EditorStartCard(plugin: plugin),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// How to use the editor, shown while no scene is open.
///
/// - What to do now: New scene, and Reopen the scene last worked on (or
///   Open the one the game starts with).
/// - Five steps from an empty editor to a saved level, each with the keys
///   that do it — read from the bindings, so a key changed in the settings
///   shows changed here.
/// - The modules' tools that need no scene — the sprite, input and
///   interface editors — to open from here.
/// - What the modules say about working with them: the platformer's spawn
///   point, its path key.
/// - A few keys worth knowing from the start.
class EditorStartCard extends StatelessWidget {
  const EditorStartCard({super.key, required this.plugin});

  final JustGameEditorPlugin plugin;

  /// A module button's tooltip as a name and what it is for:
  /// `Sprite Studio: draw and animate sprites` → `Sprite Studio`,
  /// `Draw and animate sprites`. A key in brackets at the end is dropped.
  static (String, String?) splitTooltip(String tooltip) {
    final text = tooltip.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
    for (final separator in const [': ', ' — ', ' – ', ' - ']) {
      final at = text.indexOf(separator);
      if (at > 0) {
        final detail = text.substring(at + separator.length).trim();
        return (
          text.substring(0, at).trim(),
          detail.isEmpty ? null : detail[0].toUpperCase() + detail.substring(1),
        );
      }
    }
    return (text, null);
  }

  String? _key(String commandId) {
    final bound = plugin.scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  List<String> _scenes() {
    try {
      return plugin.sceneManager.store.listSceneNames();
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> _newScene(BuildContext context) async {
    final name = await showNewSceneDialog(
      context,
      store: plugin.sceneManager.store,
    );
    if (name != null) await plugin.openScene(name);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
    valueListenable: plugin.scope.prefs.watch(RecentScenes.lastScene),
    builder: (context, last, _) {
      final scenes = _scenes();
      final order = plugin.sceneManager.playOrder();
      final reopen = scenes.contains(last) ? last : null;
      final start = order.isNotEmpty
          ? order.first
          : scenes.isNotEmpty
          ? scenes.first
          : null;
      return Semantics(
        container: true,
        label: 'Getting started with the editor',
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          decoration: BoxDecoration(
            color: EditorTheme.panelBg,
            borderRadius: BorderRadius.circular(EditorMetrics.radiusLg + 4),
            border: Border.all(color: EditorTheme.borderStrong),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  EditorButton(
                    label: 'New scene',
                    icon: Icons.add_rounded,
                    kind: EditorButtonKind.primary,
                    onPressed: () => _newScene(context),
                  ),
                  if (reopen != null)
                    EditorButton(
                      label: 'Reopen $reopen',
                      icon: Icons.history_rounded,
                      onPressed: () => plugin.openScene(reopen),
                    )
                  else if (start != null)
                    EditorButton(
                      label: 'Open $start',
                      icon: Icons.map_outlined,
                      onPressed: () => plugin.openScene(start),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              _caption('Get started'),
              ..._steps(),
              ..._assetEditors(),
              ..._tips(),
              const SizedBox(height: 18),
              _caption('Keys worth knowing'),
              _keys(),
              const SizedBox(height: 18),
              const EditorDivider(),
              const SizedBox(height: 12),
              Text(
                'The editor runs in debug builds only: a release build of '
                'the game leaves it out.',
                style: TextStyle(
                  color: EditorTheme.textMuted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _header() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: EditorTheme.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(EditorMetrics.radiusLg),
          border: Border.all(color: EditorTheme.accent.withValues(alpha: 0.45)),
        ),
        child: Icon(
          Icons.videogame_asset_rounded,
          color: EditorTheme.accent,
          size: 22,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Just Game Engine Editor',
                style: TextStyle(
                  color: EditorTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No scene is open. Open one from the Scenes list on the '
              'right, or start a new one.',
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _caption(String label, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Semantics(
          header: true,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: EditorTheme.primaryBright,
              fontSize: EditorMetrics.fontCaption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              hint,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: EditorTheme.textMuted, fontSize: 10.5),
            ),
          ),
        ],
      ],
    ),
  );

  List<Widget> _steps() {
    final transform = [
      for (final mode in const [
        TransformMode.move,
        TransformMode.scale,
        TransformMode.rotate,
      ])
        ?_key(mode.commandId),
    ];
    final steps = <(String, String, List<String>)>[
      (
        'Open or create a scene',
        'A scene is one level of the game. The Scenes list on the right '
            'holds them all; the game starts with the first in the play '
            'order.',
        const [],
      ),
      (
        'Build the level',
        'The Level Designer paints tiles and places shapes and prefabs '
            'into the Level Map.',
        [?_key('editor.toggleDesigner')],
      ),
      (
        'Select and change things',
        'Click something to select it, then move, scale or rotate it. The '
            'Inspector on the right edits its components.',
        transform,
      ),
      (
        'Play-test',
        'Play runs the level right here. Stop puts everything back as it '
            'was before Play.',
        [?_key('editor.playToggle')],
      ),
      (
        'Save',
        'Writes assets/scenes/<name>.scene.json: the very file the game '
            'ships with.',
        [?_key('editor.save')],
      ),
    ];
    return [
      for (var i = 0; i < steps.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 12),
          child: _Step(
            number: i + 1,
            title: steps[i].$1,
            body: steps[i].$2,
            keys: steps[i].$3,
          ),
        ),
    ];
  }

  /// The modules' buttons, which open tools that need no scene.
  List<Widget> _assetEditors() {
    final scope = plugin.scope;
    final buttons = scope.toolbarButtons;
    if (buttons.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      _caption('Asset editors', hint: 'no scene needed'),
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          final columns = constraints.maxWidth >= 480
              ? 3
              : constraints.maxWidth >= 300
              ? 2
              : 1;
          // Never below zero: squeezed by the docks (a phone held upright)
          // the card can be narrower than its own padding, and a negative
          // width fails the tiles' constraints.
          final width = math.max(
            0.0,
            (constraints.maxWidth - gap * (columns - 1)) / columns - 0.01,
          );
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final button in buttons)
                SizedBox(
                  width: width,
                  child: _ToolTile(
                    button: button,
                    enabled: button.isEnabled?.call(scope) ?? true,
                    onTap: () => button.onPressed(scope),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }

  List<Widget> _tips() {
    final tips = plugin.scope.gettingStartedTips;
    if (tips.isEmpty) return const [];
    return [
      const SizedBox(height: 22),
      _caption('Tips'),
      for (final tip in tips)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  tip.icon ?? Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: EditorTheme.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tip.text,
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _keys() {
    final keys = <(String?, String)>[
      (plugin.toggleKey.keyLabel, 'Hide or show the editor'),
      (plugin.statusPanelToggleKey.keyLabel, 'The docks'),
      (_key('editor.settings'), 'Settings'),
      (_key('editor.undo'), 'Undo'),
    ];
    return Wrap(
      spacing: 18,
      runSpacing: 8,
      children: [
        for (final (key, label) in keys)
          if (key != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KeyCap(key),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: EditorTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
      ],
    );
  }
}

/// A numbered step: what to do, how, and the keys that do it.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.keys,
  });

  final int number;
  final String title;
  final String body;
  final List<String> keys;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EditorTheme.accent.withValues(alpha: 0.12),
          border: Border.all(color: EditorTheme.accent.withValues(alpha: 0.5)),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            color: EditorTheme.accent,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final key in keys) KeyCap(key),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              body,
              style: TextStyle(
                color: EditorTheme.textSecondary,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// A module's tool on the card: its icon, its name and what it is for.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.button,
    required this.enabled,
    required this.onTap,
  });

  final ToolbarButton button;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (name, detail) = EditorStartCard.splitTooltip(button.tooltip);
    return Tooltip(
      message: button.tooltip,
      child: FocusOutline(
        child: Material(
          color: EditorTheme.surfaceBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EditorMetrics.radiusMd),
            side: BorderSide(color: EditorTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            hoverColor: EditorTheme.accent.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    button.icon,
                    size: 18,
                    color: enabled
                        ? EditorTheme.accent
                        : EditorTheme.textMuted.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: EditorTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (detail != null)
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: EditorTheme.textMuted,
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
