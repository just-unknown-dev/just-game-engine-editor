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

/// What a dock's content is built with.
class DockContext {
  const DockContext({
    required this.scope,
    required this.height,
    required this.onResize,
    required this.onClose,
  });

  final EditorScope scope;

  /// The dock's current height, in logical pixels.
  final double height;

  /// Called with the drag delta when the user resizes the dock.
  final ValueChanged<double> onResize;
  final VoidCallback onClose;
}

/// A bottom dock a module adds beside the built-in ones (FPS, Entities,
/// Logs, Assets, Timeline). Docks open one at a time; opening one closes
/// whichever was open.
class DockDefinition {
  const DockDefinition({
    required this.id,
    required this.label,
    required this.icon,
    required this.build,
    this.order = 100,
    this.defaultHeight = 280,
    this.badge,
  });

  final String id;
  final String label;
  final IconData icon;

  /// Lower sorts first; the built-ins occupy 0–99.
  final int order;
  final double defaultHeight;

  /// A short value shown on the dock's status button: a count, an FPS.
  final String Function(EditorScope scope)? badge;
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
  });

  final EditorScope scope;

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
