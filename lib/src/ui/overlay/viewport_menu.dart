/// The right-click menu on the level itself.
///
/// The same things the scene tree offers, where the entity actually is:
/// right-clicking a platform in the viewport should do what right-clicking
/// its row does, and on bare level it offers what can be made there.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_game_engine/just_game_engine.dart' as jge;

import '../../core/level_map/tile_selection_ops.dart';
import '../../core/plugin/editor_plugin.dart';
import 'package:just_editor_core/host.dart';
import '../../core/scope/editor_scope_services.dart';

/// Opens the viewport's context menu at [globalPosition].
///
/// [entity] is what was under the pointer, null for bare level; [worldPoint]
/// is where that is in the level, which is where a paste or a new entity
/// lands — [surface] instead in a 3-D scene: what the pointer is on, or
/// the ground, where the prefabs offered for space go too.
Future<void> showViewportMenu(
  BuildContext context,
  JustGameEditorPlugin plugin, {
  required jge.Entity? entity,
  required Offset globalPosition,
  required Offset worldPoint,
  SurfacePoint? surface,
}) async {
  if (!plugin.sceneState.hasScene) return;
  final scope = plugin.scope;
  final view = scope.view;

  // Tiles selected with Select tiles, while designing: the menu is about
  // them.
  if (plugin.designer.value != null && scope.tiles.selection.value.isNotEmpty) {
    await showTileSelectionMenu(context, plugin, globalPosition);
    return;
  }

  // Right-clicking something that is not in the selection selects it, so
  // the menu is never about something other than what was clicked.
  if (entity != null &&
      plugin.sceneState.selectedEntity.value?.id != entity.id &&
      !plugin.sceneState.isInMultiSelection(entity.id)) {
    plugin.sceneState.selectEntity(entity);
  }

  final prefabs = surface == null
      ? const <PrefabDefinition>[]
      : plugin.prefabsInSpace;
  // Many prefabs are offered by category, each opening a menu of its own.
  final byCategory = <String, List<PrefabDefinition>>{};
  for (final prefab in prefabs) {
    byCategory.putIfAbsent(prefab.category, () => []).add(prefab);
  }
  final grouped = prefabs.length > _flatPrefabs;
  final hasHidden = view.hidden.value.isNotEmpty;
  final hasLocked = view.locked.value.isNotEmpty;

  // The key that does the same, beside each item. The designer's keys
  // work only while it is open, so they show only then.
  String? key(String commandId) {
    final bound = scope.commands.bindingsFor(commandId);
    return bound.isEmpty ? null : bound.first.shortcut;
  }

  String? designerKey(String commandId) =>
      plugin.designer.value == null ? null : key(commandId);

  final chosen = await showEditorMenu<String>(context, globalPosition, [
    if (entity != null) ...[
      editorMenuItem(
        'focus',
        'Focus',
        icon: Icons.center_focus_strong_outlined,
        shortcut: designerKey('designer.frameSelection'),
      ),
      editorMenuItem(
        'duplicate',
        'Duplicate',
        icon: Icons.copy_outlined,
        shortcut: key('editor.duplicate'),
      ),
      editorMenuItem(
        'delete',
        'Delete',
        icon: Icons.delete_outline,
        shortcut: key('editor.delete'),
      ),
      editorMenuDivider(),
      editorMenuItem(
        'copy',
        'Copy',
        icon: Icons.content_copy_outlined,
        shortcut: key('editor.copy'),
      ),
    ],
    editorMenuItem(
      'paste',
      'Paste here',
      icon: Icons.content_paste_outlined,
      enabled: plugin.sceneState.hasClipboard,
      shortcut: key('editor.paste'),
    ),
    if (entity == null)
      editorMenuItem('create', 'New entity here', icon: Icons.add_box_outlined),
    editorMenuItem(
      'playFromHere',
      'Play from here',
      icon: Icons.play_circle_outline,
      enabled: plugin.playController.state.value == EditorPlayState.stopped,
    ),
    // In space: the modules' 3-D prefabs, on what the pointer is on.
    if (surface != null && prefabs.isNotEmpty) ...[
      editorMenuDivider(),
      if (!grouped)
        for (final prefab in prefabs)
          editorMenuItem(
            'prefab:${prefab.id}',
            'Add ${prefab.name}',
            icon: prefab.icon,
          )
      else ...[
        editorMenuHeading('Add'),
        for (final MapEntry(key: category, value: list) in byCategory.entries)
          editorMenuItem(
            'category:$category',
            '$category…',
            icon: list.first.icon,
          ),
      ],
    ],
    if (entity != null) ...[
      editorMenuDivider(),
      editorMenuItem('group', 'Group', icon: Icons.folder_open_rounded),
      editorMenuItem(
        'ungroup',
        'Ungroup',
        icon: Icons.folder_off_outlined,
        enabled:
            entity.getComponent<jge.ChildrenComponent>()?.childIds.isNotEmpty ??
            false,
      ),
      editorMenuDivider(),
      editorMenuItem(
        'hide',
        view.isHidden(entity.id) ? 'Show it' : 'Hide it',
        icon: view.isHidden(entity.id)
            ? Icons.visibility
            : Icons.visibility_off_outlined,
        shortcut: designerKey('designer.hide'),
      ),
      editorMenuItem(
        'lock',
        view.isLocked(entity.id) ? 'Unlock it' : 'Lock it',
        icon: view.isLocked(entity.id)
            ? Icons.lock_open_outlined
            : Icons.lock_outline,
        shortcut: designerKey('designer.lock'),
      ),
    ],
    if (hasHidden || entity != null)
      editorMenuItem(
        hasHidden ? 'showAll' : 'isolate',
        hasHidden ? 'Show everything again' : 'Isolate: hide everything else',
        icon: hasHidden ? Icons.visibility : Icons.visibility_outlined,
        shortcut: designerKey(
          hasHidden ? 'designer.unhideAll' : 'designer.isolate',
        ),
      ),
    if (hasLocked)
      editorMenuItem(
        'unlockAll',
        'Unlock everything',
        icon: Icons.lock_open_outlined,
        shortcut: designerKey('designer.unlockAll'),
      ),
    // What the modules add to an entity's tree menu, offered here too:
    // it is the same entity and the same question.
    if (entity != null && scope.sceneTreeActions.isNotEmpty) ...[
      editorMenuDivider(),
      for (final action in scope.sceneTreeActions)
        editorMenuItem(
          'module:${action.id}',
          action.label,
          icon: action.icon,
          enabled: action.isEnabled?.call(entity, scope) ?? true,
        ),
    ],
    if (entity != null) ...[
      editorMenuDivider(),
      editorMenuItem('copyName', 'Copy its name', icon: Icons.abc),
    ],
  ]);
  if (chosen == null) return;

  final entities = plugin.entities;
  switch (chosen) {
    case 'focus':
      if (entity != null) plugin.focusOn(entity);
    case 'duplicate':
      entities.duplicateSelection(
        scope.history,
        gridSize: plugin.sceneState.gridSize.value,
      );
    case 'delete':
      entities.deleteSelection(scope.history);
    case 'copy':
      if (entity != null) entities.copyEntity(entity);
    case 'paste':
      entities.pasteEntity(at: worldPoint, point: surface?.position);
    case 'create':
      entities.createEntity(at: worldPoint, point: surface?.position);
    case 'playFromHere':
      // A hair above the surface: a character stands on it, not in it.
      final at = surface == null
          ? jge.Vector3(worldPoint.dx, worldPoint.dy, 0)
          : surface.position + surface.normal * 0.05;
      plugin.playFrom(at);
    case 'group':
      entities.groupSelection();
    case 'ungroup':
      if (entity != null) entities.ungroup(entity);
    case 'hide':
      if (entity != null) view.toggleHidden(entity.id);
    case 'lock':
      if (entity != null) view.toggleLocked(entity.id);
    case 'isolate':
      if (entity != null) {
        view.isolate(scope.world, [
          for (final e in _selection(plugin, entity)) e.id,
        ]);
      }
    case 'showAll':
      view.showAll();
    case 'unlockAll':
      view.unlockAll();
    case 'copyName':
      await Clipboard.setData(ClipboardData(text: entity?.name ?? ''));
    default:
      if (chosen.startsWith('category:') && surface != null) {
        final list =
            byCategory[chosen.substring('category:'.length)] ?? const [];
        if (!context.mounted || list.isEmpty) return;
        final picked = await showEditorMenu<String>(context, globalPosition, [
          editorMenuHeading(list.first.category),
          for (final prefab in list)
            editorMenuItem(prefab.id, prefab.name, icon: prefab.icon),
        ]);
        for (final prefab in list) {
          if (prefab.id == picked) {
            plugin.placePrefab(prefab, surface);
            break;
          }
        }
        return;
      }
      if (chosen.startsWith('prefab:') && surface != null) {
        final id = chosen.substring('prefab:'.length);
        for (final prefab in prefabs) {
          if (prefab.id == id) {
            plugin.placePrefab(prefab, surface);
            break;
          }
        }
        return;
      }
      if (!chosen.startsWith('module:')) return;
      final id = chosen.substring('module:'.length);
      if (entity == null) return;
      for (final action in scope.sceneTreeActions) {
        if (action.id == id) action.run(entity, scope);
      }
  }
}

/// Up to this many prefabs are listed in the menu itself; more are listed
/// by category.
const int _flatPrefabs = 8;

/// What the menu acts on: the selection when the clicked entity is part of
/// it, otherwise that entity alone.
List<jge.Entity> _selection(JustGameEditorPlugin plugin, jge.Entity entity) {
  final selection = plugin.entities.selectionEntities;
  return selection.any((e) => e.id == entity.id) ? selection : [entity];
}

/// The right-click menu on the tiles selected with Select tiles: make them
/// an entity, copy, cut, delete, or let them go.
Future<void> showTileSelectionMenu(
  BuildContext context,
  JustGameEditorPlugin plugin,
  Offset globalPosition,
) async {
  final scope = plugin.scope;
  final world = plugin.engine.world;
  final n = TileSelectionOps.tileCount(scope, world);
  final layer = TileSelectionOps.layerOf(scope, world);
  final chosen = await showEditorMenu<String>(context, globalPosition, [
    editorMenuItem(
      'entity',
      n == 0
          ? 'No tiles of ${layer?.name ?? 'the layer'} selected'
          : 'Make ${n == 1 ? 'the tile' : 'the $n tiles'} an entity',
      icon: Icons.open_in_new,
      enabled: n > 0,
    ),
    editorMenuDivider(),
    editorMenuItem('copy', 'Copy tiles', icon: Icons.content_copy_outlined),
    editorMenuItem('cut', 'Cut tiles', icon: Icons.content_cut),
    editorMenuItem('delete', 'Delete tiles', icon: Icons.delete_outline),
    editorMenuDivider(),
    editorMenuItem('none', 'Select none', icon: Icons.deselect),
  ]);
  if (chosen == null) return;
  void say(String message) =>
      plugin.designer.value?.controller.setStatus(message);
  switch (chosen) {
    case 'entity':
      TileSelectionOps.makeEntity(scope, world, say);
    case 'copy':
      TileSelectionOps.copy(scope, world, say);
    case 'cut':
      TileSelectionOps.cut(scope, world, say);
    case 'delete':
      TileSelectionOps.delete(scope, world, say);
    case 'none':
      TileSelectionOps.deselect(scope, say);
  }
}
