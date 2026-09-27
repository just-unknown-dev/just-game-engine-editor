import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/painting.dart';
import 'package:just_debugger/just_debugger.dart';
import 'package:just_game_engine/just_game_engine.dart';

import '../../ui/level_designer/state/editor_commands.dart';
import '../../ui/level_designer/state/editor_history.dart';
import 'hierarchy_commands.dart';
import '../scope/editor_scope.dart';
import '../state/editor_scene_state.dart';
import '../state/unique_namer.dart';

/// Creates, deletes, groups, re-parents and copies entities in the world
/// being edited, keeping [sceneState] in step.
///
/// The selection operations take the designer's [EditorHistory] so each is
/// one undo step; the rest edit the world directly, as the scene tree always
/// has.
class EntityOps {
  EntityOps({
    required this.scope,
    required World Function() world,
    required this.sceneState,
    required Camera Function() camera,
    this.onChanged,
  }) : _worldOf = world,
       cameraOf = camera;

  final EditorScope scope;
  final World Function() _worldOf;

  /// The world being edited. Read on use: an engine's world does not exist
  /// until it initialises, and the overlay builds before that.
  World get world => _worldOf();
  final EditorSceneState sceneState;

  /// The viewport camera: where a new entity is placed.
  final Camera Function() cameraOf;

  /// Called after an edit the scene state does not itself announce.
  final VoidCallback? onChanged;

  /// Generates a `prefix_N` name that doesn't collide with any currently
  /// live entity.
  ///
  /// Using the live entity count as `N` (the old approach) collides as soon
  /// as an entity is deleted and a new one created afterwards — e.g. delete
  /// `entity_1` out of `entity_0`/`entity_1`/`entity_2` and the next create
  /// (count now 2) is named `entity_2`, duplicating the survivor. Duplicate
  /// names silently corrupt [openScene]'s name-keyed parent/child relinking
  /// on the next scene load.
  late final UniqueNamer uniqueName = UniqueNamer(
    () => world
        .query([TransformComponent])
        .map((e) => e.name)
        .whereType<String>(),
  );

  /// Creates a new entity at the camera centre, adds a visible
  /// [RectangleComponent] so it immediately appears on canvas, selects it,
  /// and registers it in the authoring scene graph.
  /// Makes an empty entity, at [at] in world coordinates when given — a
  /// right click on the level means "one of these, here".
  void createEntity({Offset? at}) {
    if (!sceneState.hasScene) return;

    final camera = cameraOf();
    final spawnPos = at ?? camera.position;

    final entity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
    ], name: uniqueName('entity'));

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    scope.log.log(
      'Created entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
    );
  }

  /// Names UI entities, which have no transform and so are not covered by
  /// [uniqueName].
  late final UniqueNamer uniqueUiName = UniqueNamer(
    () => world.entities.map((e) => e.name).whereType<String>(),
  );

  /// Creates a piece of interface of [kind] and selects it.
  ///
  /// Everything but a canvas goes under one: under [parent] when it is
  /// given, otherwise under what is selected, otherwise under the scene's
  /// first canvas — and if there is no canvas at all, one is made, because
  /// UI outside a canvas is never drawn.
  Entity? createUi(String kind, {Entity? parent}) {
    if (!sceneState.hasScene) return null;

    final isRoot = kind == 'canvas' || kind == 'screen';
    final under = isRoot ? null : (parent ?? _uiParent());
    if (!isRoot && under == null) return null;

    final entity = world.createEntityWithComponents([
      ..._componentsFor(kind),
      if (!isRoot) ParentComponent(parentId: under!.id),
    ], name: uniqueUiName(_nameFor(kind)));

    if (!isRoot) {
      var children = under!.getComponent<ChildrenComponent>();
      if (children == null) {
        children = ChildrenComponent();
        under.addComponent(children);
      }
      children.addChild(entity.id);
    }

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    sceneState.refresh();
    onChanged?.call();
    scope.log.log(
      'Created UI ${entity.name} ($kind).',
      source: 'editor',
      category: 'entity',
    );
    return entity;
  }

  /// Where a new element goes: what is selected if that is UI, the canvas
  /// above it if it is not a container, or the scene's first canvas.
  Entity? _uiParent() {
    final selected = sceneState.selectedEntity.value;
    if (selected != null && _isUi(selected)) return selected;
    for (final entity in world.query([UiCanvasComponent])) {
      return entity;
    }
    return createUi('canvas');
  }

  static bool _isUi(Entity entity) =>
      entity.getComponent<UiCanvasComponent>() != null ||
      entity.getComponent<UiSlotComponent>() != null;

  static String _nameFor(String kind) =>
      kind.startsWith('custom:') ? kind.substring(7) : kind;

  static List<Component> _componentsFor(String kind) {
    if (kind.startsWith('custom:')) {
      return [
        UiCustomComponent(widgetId: kind.substring(7)),
        UiSlotComponent(),
      ];
    }
    return switch (kind) {
      'canvas' => [UiCanvasComponent(), ChildrenComponent()],
      'screen' => [
        UiCanvasComponent(isScreen: true, modal: true, visible: false),
        ChildrenComponent(),
      ],
      'row' => _container(UiLayoutKind.row),
      'column' => _container(UiLayoutKind.column),
      'stack' => _container(UiLayoutKind.stack),
      'wrap' => _container(UiLayoutKind.wrap),
      'grid' => _container(UiLayoutKind.grid),
      'scroll' => _container(UiLayoutKind.scroll),
      'panel' => [
        UiPanelComponent(),
        UiSlotComponent(mode: UiSlotMode.anchored),
        ChildrenComponent(),
      ],
      'text' => [TextComponent(text: 'Text'), UiSlotComponent()],
      'button' => [ButtonComponent(label: 'Button'), UiSlotComponent()],
      'image' => [UiImageComponent(), UiSlotComponent()],
      'progress' => [UiProgressComponent(), UiSlotComponent()],
      'toggle' => [UiToggleComponent(label: 'Toggle'), UiSlotComponent()],
      'slider' => [UiSliderComponent(), UiSlotComponent()],
      'field' => [UiTextFieldComponent(hint: 'Type here'), UiSlotComponent()],
      'dropdown' => [
        UiDropdownComponent(options: ['One', 'Two']),
        UiSlotComponent(),
      ],
      'spacer' => [UiSpacerComponent(), UiSlotComponent()],
      // Something from a newer editor, or a typo in a shortcut: an empty
      // node is easier to delete than a crash is to recover from.
      _ => [UiSlotComponent()],
    };
  }

  static List<Component> _container(UiLayoutKind kind) => [
    UiLayoutComponent(kind: kind),
    UiSlotComponent(mode: UiSlotMode.anchored, anchor: UiAnchor.stretch),
    ChildrenComponent(),
  ];

  /// Renames [entity], refusing a name something else already has.
  ///
  /// Returns false when the name is taken, so the row can say so and keep
  /// the box open. Names are how a scene file records who a child's parent
  /// is, and two entities sharing one quietly breaks the hierarchy the
  /// next time the scene is loaded.
  bool renameEntity(Entity entity, String name) {
    final trimmed = name.trim();
    if (trimmed == entity.name) return true;
    if (!RenameCommand.isAvailable(trimmed, entity, world: world)) {
      return false;
    }
    scope.history.push(
      RenameCommand(sceneState: sceneState, entity: entity, name: trimmed),
    );
    onChanged?.call();
    return true;
  }

  /// Turns everything selected into one group, as an undoable step.
  Entity? groupSelection() {
    final targets = selectionEntities;
    if (targets.isEmpty || !sceneState.hasScene) return null;

    // Where the group goes: the middle of what it holds, so moving it
    // afterwards turns them about something sensible.
    var sum = Offset.zero;
    var counted = 0;
    for (final entity in targets) {
      final t = entity.getComponent<TransformComponent>();
      if (t == null) continue;
      sum += Offset(t.position.x, t.position.y);
      counted++;
    }
    final centre = counted == 0
        ? cameraOf().position
        : sum / counted.toDouble();

    final command = GroupCommand(
      world: world,
      sceneState: sceneState,
      entities: targets,
      name: uniqueName('group'),
      position: Vector3.fromOffset(centre),
    );
    scope.history.push(command);

    final group = command.group;
    sceneState.clearMultiSelection();
    if (group != null) sceneState.selectEntity(group);
    sceneState.refresh();
    onChanged?.call();
    return group;
  }

  /// Takes a group apart: its children move up to where it was, and the
  /// empty group goes.
  void ungroup(Entity group) {
    final children = group.getComponent<ChildrenComponent>()?.childIds;
    if (children == null || children.isEmpty) return;
    scope.history.push(
      UngroupCommand(
        world: world,
        sceneState: sceneState,
        group: group,
        codec: scope.codec,
      ),
    );
    sceneState.refresh();
    onChanged?.call();
  }

  /// Entities covered by the current selection: the multi-selection when there
  /// is one, otherwise just the primary selection.
  List<Entity> get selectionEntities {
    final ids = sceneState.multiSelectedIds.value;
    if (ids.isNotEmpty) {
      return ids
          .map(world.getEntity)
          .whereType<Entity>()
          .where((e) => e.isActive)
          .toList();
    }
    final selected = sceneState.selectedEntity.value;
    return selected == null ? const [] : [selected];
  }

  static String _describe(List<Entity> entities) => entities.length == 1
      ? entities.single.name ?? 'entity'
      : '${entities.length} entities';

  /// Deletes everything selected as one undoable action.
  void deleteSelection(EditorHistory history) {
    final targets = selectionEntities;
    if (targets.isEmpty) return;
    history.push(
      DeleteEntitiesCommand(
        label: 'Delete ${_describe(targets)}',
        world: world,
        sceneState: sceneState,
        entities: targets,
        codec: scope.codec,
      ),
    );
  }

  /// Duplicates everything selected, offset by one grid cell so the copies are
  /// visible rather than hidden exactly behind the originals.
  void duplicateSelection(EditorHistory history, {required double gridSize}) {
    final targets = selectionEntities;
    if (targets.isEmpty) return;

    final offset = Offset(gridSize, gridSize);
    final specs = targets
        .map(
          (entity) => EntitySpec.of(
            entity,
            scope.codec,
            world: world,
          ).translated(offset, newName: uniqueName(_baseName(entity.name))),
        )
        .toList();

    history.push(
      CreateEntitiesCommand(
        label:
            'Duplicate ${targets.length} entit'
            '${targets.length == 1 ? 'y' : 'ies'}',
        world: world,
        sceneState: sceneState,
        specs: specs,
        onCreated: (created) {
          sceneState.clearMultiSelection();
          for (final entity in created) {
            sceneState.toggleMultiSelect(entity);
          }
          if (created.isNotEmpty) sceneState.selectEntity(created.first);
        },
      ),
    );
  }

  /// Repeats the selection [count] times, each copy [step] further along.
  ///
  /// Blocking out a staircase or a row of pillars by hand is the kind of
  /// repetitive work a level editor should be doing for you.
  void arraySelection(
    EditorHistory history, {
    required int count,
    required Offset step,
  }) {
    final targets = selectionEntities;
    if (targets.isEmpty || count < 1) return;

    final specs = <EntitySpec>[];
    for (var i = 1; i <= count; i++) {
      for (final entity in targets) {
        specs.add(
          EntitySpec.of(entity, scope.codec, world: world).translated(
            step * i.toDouble(),
            newName: uniqueName(_baseName(entity.name)),
          ),
        );
      }
    }

    history.push(
      CreateEntitiesCommand(
        label: 'Array x$count',
        world: world,
        sceneState: sceneState,
        specs: specs,
      ),
    );
  }

  /// Strips any trailing `_12` from a generated name, so duplicating
  /// `Platform_3` yields `Platform_4` rather than `Platform_3_1`.
  String _baseName(String? name) {
    if (name == null || name.isEmpty) return 'entity';
    final match = RegExp(r'^(.*?)_\d+$').firstMatch(name);
    return match?.group(1) ?? name;
  }

  /// Destroys [entity] from the ECS world and removes its authoring node.
  void deleteEntity(Entity entity) {
    // Clean up parent link before destroying.
    detachFromParent(entity);
    // Detach all children so they become root entities.
    final children = entity.getComponent<ChildrenComponent>();
    if (children != null) {
      for (final childId in List.of(children.childIds)) {
        final child = world.getEntity(childId);
        if (child != null) detachFromParent(child);
      }
    }
    sceneState.removeEntityNode(entity.id);
    world.destroyEntity(entity);
    scope.log.log(
      'Deleted entity ${entity.name ?? entity.id}.',
      source: 'editor',
      category: 'entity',
      level: DebuggerLogLevel.warning,
    );
    onChanged?.call();
  }

  // ── Group operations ──────────────────────────────────────────────────────

  /// Creates an empty group entity and optionally adds [children] to it.
  ///
  /// When [children] is null and a multi-selection is active, all
  /// multi-selected entities are grouped automatically.
  void createGroup({List<Entity>? children}) {
    if (!sceneState.hasScene) return;

    final camera = cameraOf();
    final spawnPos = camera.position;

    final groupEntity = world.createEntityWithComponents([
      TransformComponent(position: Vector3.fromOffset(spawnPos)),
      ChildrenComponent(),
    ], name: uniqueName('group'));

    sceneState.registerEntity(groupEntity);

    final targets =
        children ??
        (sceneState.hasMultiSelection
            ? sceneState.multiSelectedIds.value
                  .map(world.getEntity)
                  .whereType<Entity>()
                  .toList()
            : null);

    if (targets != null) {
      for (final child in targets) {
        reparentEntity(child, groupEntity);
      }
    }

    sceneState.clearMultiSelection();
    sceneState.selectEntity(groupEntity);
    sceneState.refresh();
    scope.log.log(
      'Created group ${groupEntity.name ?? groupEntity.id}.',
      source: 'editor',
      category: 'group',
    );
  }

  /// Moves [moved] to just before or after [anchor] among its siblings.
  ///
  /// Sibling order is what a row or a column lays its children out in, and
  /// it is kept by the order the scene file is written in — so this is a
  /// real edit, not a view.
  ///
  /// Only within a parent: the entities at the root of a scene have no
  /// list to be ordered in.
  void reorderEntity(Entity moved, Entity anchor, {required bool before}) {
    if (moved.id == anchor.id) return;
    final parentId = anchor.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);

    // Where the anchor sits among the things it shares a level with.
    final siblings = parent == null
        ? sceneState.rootOrder(world)
        : parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[];
    var at = siblings.indexOf(anchor.id);
    if (at < 0) return;
    if (!before) at++;
    // Moving something that is already above the anchor shifts the target
    // down by the gap it leaves behind.
    final from = siblings.indexOf(moved.id);
    if (from >= 0 && from < at) at--;

    final sameLevel =
        moved.getComponent<ParentComponent>()?.parentId == parentId;
    if (sameLevel) {
      scope.history.push(
        ReorderCommand(
          label:
              'Move ${moved.name ?? moved.id} '
              '${before ? 'before' : 'after'} ${anchor.name ?? anchor.id}',
          world: world,
          sceneState: sceneState,
          entity: moved,
          index: at,
        ),
      );
    } else {
      reparentAll([moved], parent, index: at);
    }
    onChanged?.call();
  }

  /// Moves [entity] one place up or down among the things it sits with.
  void nudgeOrder(Entity entity, {required bool up}) {
    final parentId = entity.getComponent<ParentComponent>()?.parentId;
    final parent = parentId == null ? null : world.getEntity(parentId);
    final siblings = parent == null
        ? sceneState.rootOrder(world)
        : parent.getComponent<ChildrenComponent>()?.childIds ??
              const <EntityId>[];
    final at = siblings.indexOf(entity.id);
    if (at < 0) return;
    final to = up ? at - 1 : at + 1;
    if (to < 0 || to >= siblings.length) return;
    scope.history.push(
      ReorderCommand(
        label: 'Move ${entity.name ?? entity.id} ${up ? 'up' : 'down'}',
        world: world,
        sceneState: sceneState,
        entity: entity,
        index: to,
      ),
    );
    onChanged?.call();
  }

  /// Makes [child] a child of [newParent], auto-computing localOffset.
  /// Makes [child] a child of [newParent], as one undoable step.
  ///
  /// [index] puts it at a place among the new parent's children; without
  /// one it goes last.
  void reparentEntity(Entity child, Entity newParent, {int? index}) {
    final command = ReparentCommand(
      label:
          'Move ${child.name ?? child.id} into '
          '${newParent.name ?? newParent.id}',
      world: world,
      sceneState: sceneState,
      entities: [child],
      parent: newParent,
      index: index,
    );
    if (!command.isValid) return;
    scope.history.push(command);
    onChanged?.call();
    scope.log.log(
      'Reparented ${child.name ?? child.id} under '
      '${newParent.name ?? newParent.id}.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  /// Moves [entities] under [parent] — or to the top level when it is
  /// null — as one undoable step. Into a level map with [mapLayer], onto
  /// that layer of it.
  void reparentAll(
    List<Entity> entities,
    Entity? parent, {
    int? index,
    int? mapLayer,
  }) {
    if (entities.isEmpty) return;
    final command = ReparentCommand(
      label: entities.length == 1
          ? 'Move ${entities.single.name ?? 'entity'}'
          : 'Move ${entities.length} entities',
      world: world,
      sceneState: sceneState,
      entities: entities,
      parent: parent,
      index: index,
      mapLayer: mapLayer,
    );
    if (!command.isValid) return;
    scope.history.push(command);
    onChanged?.call();
  }

  /// Removes [child] from its parent, making it a root entity.
  void detachFromParent(Entity child) {
    final pc = child.getComponent<ParentComponent>();
    if (pc?.parentId == null) return;

    final parentEntity = world.getEntity(pc!.parentId!);
    parentEntity?.getComponent<ChildrenComponent>()?.removeChild(child.id);

    child.removeComponent<ParentComponent>();

    sceneState.markDirty();
    sceneState.refresh();
    scope.log.log(
      'Detached ${child.name ?? child.id} from parent.',
      source: 'editor',
      category: 'hierarchy',
      mirrorToDebugger: false,
    );
  }

  /// Copies [entity]'s components to the clipboard as serialised JSON.
  void copyEntity(Entity entity) {
    final components = entity.components
        .map(scope.codec.encode)
        .whereType<Map<String, dynamic>>()
        .toList();
    sceneState.setClipboard(components);
    scope.log.log(
      'Copied entity ${entity.name ?? entity.id} to clipboard.',
      source: 'editor',
      category: 'clipboard',
      mirrorToDebugger: false,
    );
  }

  /// Spawns a new entity from the clipboard, offset from the camera centre.
  void pasteEntity({Offset? at}) {
    if (!sceneState.hasClipboard) return;

    final components = (sceneState.clipboard.value ?? [])
        .map(scope.codec.decode)
        .whereType<Component>()
        .toList();

    final pastePosOffset = at ?? cameraOf().position + const Offset(30, 30);
    final pastePos = Vector3.fromOffset(pastePosOffset);

    final transform = components.whereType<TransformComponent>().firstOrNull;
    if (transform != null) {
      transform.position.setFrom(pastePos);
    } else {
      components.insert(0, TransformComponent(position: pastePos));
    }

    final entity = world.createEntityWithComponents(
      components,
      name: uniqueName('entity'),
    );

    sceneState.registerEntity(entity);
    sceneState.selectEntity(entity);
    scope.log.log(
      'Pasted entity ${entity.name ?? entity.id} from clipboard.',
      source: 'editor',
      category: 'clipboard',
    );
    onChanged?.call();
  }
}

/// One entry of the editor's Create-UI menu.
class UiCreateOption {
  const UiCreateOption(this.id, this.label, this.icon, {this.group = ''});

  /// What [EntityOps.createUi] is called with — `text`, `row`, or
  /// `custom:inventory_grid`.
  final String id;
  final String label;
  final IconData icon;

  /// How the menu groups it: Roots, Containers, Elements, or the empty
  /// string for what the game brought.
  final String group;
}

/// The icon a piece of interface is shown with, in the tree and anywhere
/// else a row stands for one.
///
/// Beside [UiCreateOptions] on purpose: the icon a thing is made with and
/// the icon it is then listed under should be the same one, and here they
/// cannot drift apart.
IconData? uiIconFor(Entity entity) {
  if (entity.getComponent<UiCanvasComponent>() case final canvas?) {
    return canvas.isScreen ? Icons.web_asset_outlined : Icons.web_asset;
  }
  if (entity.getComponent<UiCustomComponent>() != null) {
    return Icons.extension_outlined;
  }
  if (entity.getComponent<UiLayoutComponent>() case final layout?) {
    return switch (layout.kind) {
      UiLayoutKind.row => Icons.view_column,
      UiLayoutKind.column => Icons.view_agenda,
      UiLayoutKind.stack => Icons.layers,
      UiLayoutKind.wrap => Icons.wrap_text,
      UiLayoutKind.grid => Icons.grid_view,
      UiLayoutKind.scroll => Icons.swap_vert,
      UiLayoutKind.safeArea => Icons.crop_free,
    };
  }
  if (entity.getComponent<TextComponent>() != null) return Icons.text_fields;
  if (entity.getComponent<ButtonComponent>() != null) {
    return Icons.smart_button;
  }
  if (entity.getComponent<UiImageComponent>() != null) {
    return Icons.image_outlined;
  }
  if (entity.getComponent<UiProgressComponent>() != null) {
    return Icons.linear_scale;
  }
  if (entity.getComponent<UiToggleComponent>() != null) {
    return Icons.toggle_on_outlined;
  }
  if (entity.getComponent<UiSliderComponent>() != null) return Icons.tune;
  if (entity.getComponent<UiTextFieldComponent>() != null) {
    return Icons.keyboard_alt_outlined;
  }
  if (entity.getComponent<UiDropdownComponent>() != null) {
    return Icons.arrow_drop_down_circle_outlined;
  }
  if (entity.getComponent<UiSpacerComponent>() != null) {
    return Icons.space_bar;
  }
  // A panel last: it is usually *also* something else, and what that
  // something is says more about the row than its background does.
  if (entity.getComponent<UiPanelComponent>() != null) {
    return Icons.rectangle_outlined;
  }
  // Interface, but nothing yet says what kind.
  return entity.getComponent<UiSlotComponent>() == null
      ? null
      : Icons.widgets_outlined;
}

/// What a Create-UI menu offers: the built-in kinds, then everything the
/// running game registered through `UiWidgets`.
abstract final class UiCreateOptions {
  static const List<UiCreateOption> builtIns = [
    UiCreateOption('canvas', 'Canvas', Icons.web_asset, group: 'Root'),
    UiCreateOption('screen', 'Screen', Icons.web_asset_outlined, group: 'Root'),
    UiCreateOption('row', 'Row', Icons.view_column, group: 'Containers'),
    UiCreateOption('column', 'Column', Icons.view_agenda, group: 'Containers'),
    UiCreateOption('stack', 'Stack', Icons.layers, group: 'Containers'),
    UiCreateOption('wrap', 'Wrap', Icons.wrap_text, group: 'Containers'),
    UiCreateOption('grid', 'Grid', Icons.grid_view, group: 'Containers'),
    UiCreateOption('scroll', 'Scroll', Icons.swap_vert, group: 'Containers'),
    UiCreateOption(
      'panel',
      'Panel',
      Icons.rectangle_outlined,
      group: 'Containers',
    ),
    UiCreateOption('text', 'Text', Icons.text_fields, group: 'Elements'),
    UiCreateOption('button', 'Button', Icons.smart_button, group: 'Elements'),
    UiCreateOption('image', 'Image', Icons.image_outlined, group: 'Elements'),
    UiCreateOption(
      'progress',
      'Progress bar',
      Icons.linear_scale,
      group: 'Elements',
    ),
    UiCreateOption(
      'toggle',
      'Toggle',
      Icons.toggle_on_outlined,
      group: 'Elements',
    ),
    UiCreateOption('slider', 'Slider', Icons.tune, group: 'Elements'),
    UiCreateOption(
      'field',
      'Text field',
      Icons.keyboard_alt_outlined,
      group: 'Elements',
    ),
    UiCreateOption(
      'dropdown',
      'Dropdown',
      Icons.arrow_drop_down_circle_outlined,
      group: 'Elements',
    ),
    UiCreateOption('spacer', 'Spacer', Icons.space_bar, group: 'Elements'),
  ];

  /// The built-ins plus the game's own widgets, which are only there while
  /// a game that registered them is running in the editor.
  static List<UiCreateOption> get all => [
    ...builtIns,
    for (final definition in UiWidgets.all)
      UiCreateOption(
        'custom:${definition.id}',
        definition.label,
        definition.icon ?? Icons.extension_outlined,
        group: 'From the game',
      ),
  ];
}
