import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../core/prefs/editor_prefs.dart';
import '../core/scope/editor_scope.dart';

/// A section a module adds to the editor's settings dialog, on its Modules
/// tab. Read and write your own [SettingPref]s through [EditorPrefs].
class SettingsSection {
  const SettingsSection({
    required this.id,
    required this.title,
    required this.build,
    this.order = 100,
  });

  final String id;
  final String title;
  final int order;
  final Widget Function(BuildContext context, EditorPrefs prefs) build;
}

/// How loudly a dock's badge speaks.
enum DockSeverity { none, info, warning, error }

/// The small marker on a dock's tab: a count, a dot for "something new".
class DockBadge {
  const DockBadge(this.text, [this.severity = DockSeverity.none]);

  /// Short: `3`, `●`. Empty shows nothing.
  final String text;
  final DockSeverity severity;
}

/// A fact a module's dock puts on the status bar: a live value that is
/// always in view — `Waves  3 left` — and a button to its dock, opened with
/// [openArgs].
class DockReadout {
  const DockReadout({
    required this.value,
    this.label,
    this.accent,
    this.openArgs,
  });

  /// What the number is — `FPS` on the Profiler's. The dock's own label
  /// when null.
  final String? label;

  /// Read a few times a second while the editor is open; keep it cheap.
  /// An empty string leaves the segment off the strip for now.
  final String Function(EditorScope scope) value;
  final Color? accent;

  /// Passed to the dock when the readout opens it — a preset filter, say.
  final Map<String, Object?>? openArgs;
}

/// What a dock remembers between launches: its filters, its view mode,
/// which folders were open. Small JSON-able values by key.
abstract class DockMemory {
  T? read<T>(String key);
  void write(String key, Object? value);
}

/// What a dock's content is built with.
class DockContext {
  const DockContext({
    required this.scope,
    required this.height,
    required this.onResize,
    required this.onClose,
    this.memory,
    this.args = const {},
  });

  final EditorScope scope;

  /// The dock's current height, in logical pixels.
  final double height;

  /// Called with the drag delta when the user resizes the dock.
  final ValueChanged<double> onResize;
  final VoidCallback onClose;

  /// This dock's own remembered values; null where nothing persists.
  final DockMemory? memory;

  /// What the dock was opened with ([DockReadout.openArgs], a command).
  final Map<String, Object?> args;
}

/// A dock in the bottom panel: a tab beside the built-in ones (Console,
/// Assets, Timeline, Profiler, World…).
class DockDefinition {
  const DockDefinition({
    required this.id,
    required this.label,
    required this.icon,
    required this.build,
    this.order = 100,
    this.defaultHeight = 280,
    this.badge,
    this.tabBadge,
    this.readout,
    this.headerActions,
    this.keepAlive = false,
    this.pinnedByDefault = true,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Lower sorts first; the built-ins occupy 0–99.
  final int order;
  final double defaultHeight;

  /// A short value shown in the status strip: a count, an FPS. Kept for
  /// modules written before [readout]; a [readout] wins when both are set.
  final String Function(EditorScope scope)? badge;

  /// The marker on the tab itself.
  final DockBadge? Function(EditorScope scope)? tabBadge;

  /// This dock's segment of the status strip.
  final DockReadout? readout;

  /// Buttons for the panel's header while this dock is the active one.
  final List<Widget> Function(BuildContext context, DockContext dock)?
  headerActions;

  /// Keep the dock built while another tab is showing, so it loses nothing:
  /// a scroll position, a capture in progress. Costs what the dock costs.
  final bool keepAlive;

  /// Whether the dock starts as a tab; otherwise it waits in the `+` menu.
  final bool pinnedByDefault;

  final Widget Function(BuildContext context, DockContext dock) build;
}

/// What a workspace's content is built with.
class WorkspaceContext {
  const WorkspaceContext({
    required this.scope,
    required this.onClose,
    this.path,
    this.reloadAssets,
    this.fullScreen,
    this.onToggleFullScreen,
    this.setCloseGuard,
  });

  final EditorScope scope;

  /// Registers what to ask before the workspace goes — "save your
  /// changes?" — when another is opened over it; null clears it. A
  /// workspace with unsaved work sets one, and asks the same itself before
  /// calling [onClose].
  final void Function(Future<bool> Function()? guard)? setCloseGuard;

  /// Whether the workspace fills the editor right now, for a button that
  /// shows which way it will go. Null where the host has no such choice.
  final ValueListenable<bool>? fullScreen;

  /// Switches between the dialog and filling the editor. A workspace puts
  /// this on a button beside its close button.
  final VoidCallback? onToggleFullScreen;

  /// Closes the workspace and gives the viewport back to the level.
  final VoidCallback onClose;

  /// The project-relative file the workspace was opened on, if any.
  final String? path;

  /// Tells the editor a file the workspace wrote has changed, so the level
  /// shows the new version. Null where there is no running editor.
  final void Function(String path)? reloadAssets;
}

/// How an open workspace sits in the editor.
enum WorkspacePresentation {
  /// A large dialog over the editor, which stays visible, dimmed, around it.
  /// On a window too small to spare the margin it fills instead.
  dialog,

  /// Fills the editor.
  fullScreen,
}

/// A large tool a module adds — a sprite editor, a dialogue graph — opened
/// over the editor while the scene stays loaded underneath. One is open at a
/// time. While one is, the level's tools, keys and play controls stand down.
class WorkspaceDefinition {
  const WorkspaceDefinition({
    required this.id,
    required this.label,
    required this.icon,
    required this.build,
    this.fileExtensions = const [],
    this.order = 100,
    this.presentation = WorkspacePresentation.dialog,
  });

  final String id;
  final String label;
  final IconData icon;
  final int order;
  final WorkspacePresentation presentation;

  /// File endings this workspace opens, lower case, without the dot —
  /// `png`, `animator.json`. The longest match wins, so `animator.json`
  /// beats `json`.
  final List<String> fileExtensions;

  final Widget Function(BuildContext context, WorkspaceContext workspace) build;

  /// How well this workspace fits [path]: the length of the ending it
  /// matched, 0 for none.
  int matchOf(String path) {
    final lower = path.toLowerCase();
    var best = 0;
    for (final ext in fileExtensions) {
      if (lower.endsWith('.$ext') && ext.length > best) best = ext.length;
    }
    return best;
  }
}

/// Something a module offers to do with a file in the Assets dock.
class AssetAction {
  const AssetAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.appliesTo,
    required this.run,
    this.order = 100,
  });

  final String id;
  final String label;
  final IconData icon;
  final int order;

  /// Whether to offer this for [path] (project-relative, forward slashes).
  /// [isDirectory] lets an action be a folder's "New …".
  final bool Function(String path, {required bool isDirectory}) appliesTo;

  final void Function(EditorScope scope, String path) run;
}

/// A button a module adds to the play-controls toolbar, after the built-in
/// Play, Pause, Stop and Level Designer buttons.
class ToolbarButton {
  const ToolbarButton({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.order = 100,
    this.isEnabled,
    this.isActive,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final int order;
  final bool Function(EditorScope scope)? isEnabled;
  final bool Function(EditorScope scope)? isActive;
  final void Function(EditorScope scope) onPressed;
}

/// A line a module adds to the start card, the guide shown over the
/// viewport while no scene is open: how to work with what the module
/// brings. One sentence, or two short ones.
class GettingStartedTip {
  const GettingStartedTip({
    required this.id,
    required this.text,
    this.icon,
    this.order = 100,
  });

  final String id;
  final String text;

  /// Drawn before the text; a light bulb when null.
  final IconData? icon;
  final int order;
}

/// An entry a module adds to an entity's context menu in the scene tree.
class SceneTreeAction {
  const SceneTreeAction({
    required this.id,
    required this.label,
    required this.run,
    this.icon,
    this.order = 100,
    this.isEnabled,
  });

  final String id;
  final String label;
  final IconData? icon;
  final int order;
  final bool Function(jge.Entity entity, EditorScope scope)? isEnabled;
  final void Function(jge.Entity entity, EditorScope scope) run;
}

/// Something drawn at the end of an entity's row in the scene tree: a
/// badge, a toggle.
class SceneTreeRowDecoration {
  const SceneTreeRowDecoration({
    required this.id,
    required this.build,
    this.order = 100,
  });

  final String id;
  final int order;
  final Widget? Function(BuildContext context, jge.Entity entity) build;
}

/// An icon for an entity in the scene tree, when a module knows better
/// than the generic one.
///
/// The editor knows about interface and about parents and children; what
/// a *coin* or a *hazard* looks like is a game's own business, which is
/// why this is a hook and not a switch in here. The first one to answer
/// wins, lowest [order] asked first.
class EntityIcon {
  const EntityIcon({required this.id, required this.of, this.order = 100});

  final String id;
  final int order;

  /// The icon for [entity], or null to leave it to the next one.
  final IconData? Function(jge.Entity entity) of;
}

/// Says which entities the scene tree must not delete. The built-in rule
/// protects the camera; a module adds its own.
class EntityProtectionRule {
  const EntityProtectionRule({required this.id, required this.isProtected});

  final String id;
  final bool Function(jge.Entity entity) isProtected;
}

/// A section a module adds to the inspector, after the component sections.
class InspectorSection {
  const InspectorSection({
    required this.id,
    required this.build,
    this.order = 100,
    this.appliesTo,
  });

  final String id;
  final int order;

  /// Null shows the section for every entity.
  final bool Function(jge.Entity entity)? appliesTo;
  final Widget Function(
    BuildContext context,
    jge.Entity entity,
    EditorScope scope,
  )
  build;
}
