# Just Game Engine Editor - Architecture

The editor is an engine plugin and a widget. `JustGameEditorPlugin` attaches to a running `Engine`, owns one `EditorScope` (every registry and service of one editor), and does its work on the engine's frames; `JustGameEngineEditor` puts `JustGameEditorOverlay` over the game's `GameWidget`. Games, kits and tools add to it through `EditorModule`s. Nothing in it is process-wide, and a profile or release build holds none of it.

## Package layout

The editor is two packages. **`just_editor_core`** is what a module builds on: the module contract, the scope and its services, undo and the entity commands, the inspector's rows and field-editor API, the Level Designer's tool and overlay API, and the UI kit. **`just_game_engine_editor`** (this package) is the host: the plugin, the overlay and its chrome, the docks, the Level Designer itself, the timeline, the Tileset Editor, scene loading and play-testing, and the editor's own tools, which arrive the way a module's do (`BuiltInEditorModule`). A kit or an editor plugin depends on the core alone; a game's editor entry point depends on this package, whose library re-exports the core's.

```
just_editor_core/lib/
├── just_editor_core.dart   ← what a module imports
├── host.dart               ← everything, for the editor that hosts modules
├── kit.dart                ← the UI kit alone
└── src/
    ├── extension/   ← EditorModule and its contributions (FieldAccessory among them), AssetKind and the
    │                  asset index, AudioDrop, EditorMarker, ViewportOverlay, ViewportHandles, PrefabVariant
    ├── scope/       ← EditorScope (one editor's just_di container), EditorScopeProvider
    ├── model/       ← EditorHistory, the entity and hierarchy commands, ComponentEdit, CommandRegistry and
    │                  DesignerCommand, EditorScene, EditorSceneState, EditorViewState, SceneCodec, SceneStore
    ├── designer/    ← the Level Designer's API: DesignerSession, LevelToolHandler and ToolRegistry, PathTool,
    │                  DesignerOverlay, SnapProvider, SmartSnap, PrefabDefinition, LayerPreset, grid/
    ├── inspector/   ← DefinitionSection, FieldEditorRegistry, the field rows, ComponentExtras, CollectionEditor,
    │                  AddComponentPicker
    ├── view/        ← EditorView, GameCameraEditorView (2-D), EntityPicker, RayEntityPicker, HandleDragSession
    ├── project/     ← ProjectTags, TagReferences, ProjectPhysicsLayers, ProjectColours
    ├── settings/    ← EditorPrefs and SettingPref, OverlayUiSettings and their store, EditorChromeState
    ├── services/    ← EditorLogService and its storage, PackageAssetPaths
    ├── validation/  ← SceneValidator, ValidationContext, SceneProblem
    ├── scene_tree/  ← SceneTreeModel, the row tile and its drop zones
    └── look/        ← EditorTheme, EditorThemeData, ThemeController, EditorMetrics, the snackbar;
                       kit/ (the shared widgets), widgets/ (EditorDropdown, EditorMenu, EditorScrollbar,
                       ScrubbableNumberField)

just_game_engine_editor/lib/
├── just_game_engine_editor.dart   ← the public library (and the core's, re-exported)
└── src/
    ├── core/
    │   ├── plugin/          ← JustGameEditorPlugin: the engine plugin, keys, autosave, the designer session
    │   ├── scope/           ← EditorScopeServices: the editor's own services on the scope (docks, EntityOps,
    │   │                      the Level Map's), each made when first asked for
    │   ├── state/           ← PlaySnapshot
    │   ├── view/            ← OrbitFlyEditorView (3-D), PlanarEntityPicker
    │   ├── input/           ← ViewportInput, the gizmo drag solvers (planar, ray)
    │   ├── entity/          ← EntityOps
    │   ├── scene/           ← SceneIO (open, save, migrate), SceneLoading's host side
    │   ├── serialization/   ← SceneManager, SceneNameValidator
    │   ├── play/            ← PlayController, EntitySpawner
    │   ├── level_map/       ← the Level Map: documents, provision, tile edits, TilesToEntity, Tiled import and export
    │   ├── physics/         ← LayerRefactor, PhysicsBodies, ColliderOverlay3D, HullOutline
    │   ├── tags/            ← TagRefactor, tag edits
    │   ├── validation/      ← BuiltInValidators, PhysicsChecks, Physics3DChecks, TagChecks
    │   ├── assets/          ← FileSpriteAssetLoader, AssetLoadCounter
    │   ├── prefs/           ← RecentScenes
    │   ├── project/         ← EditorPresence (the editor.lock heartbeat)
    │   └── ecs/             ← the editor's two systems
    ├── extension/           ← BuiltInEditorModule, and the built-in contributions it gathers: camera, audio,
    │                          tags, tiles, 3-D physics, row decorations
    ├── integration/         ← JustGameEngineEditor
    ├── debugger/            ← EngineDebuggerPanel (unused: the plugin attaches the engine's debugger itself)
    └── ui/
        ├── overlay/         ← JustGameEditorOverlay: chrome/, docks/, settings/, right_panel/, shared/, start/;
        │                      the gizmos, the viewport menu, the camera rigs
        ├── inspector/       ← the built-in field editors and extras, EntityHeader; physics/ (PhysicsBodyExtras,
        │                      ColliderEditSession)
        ├── panels/          ← EntityInspectorPanel, ScenePickerPanel, SceneRow
        ├── scene_tree/      ← SceneTreePanel, SceneTreeController, MapItemRow
        ├── level_designer/  ← the Level Designer: its session, workspace, panels, controls, the built-in tools,
        │                      overlays and commands
        ├── timeline/        ← TimelineSession and the Timeline dock's views
        ├── tileset/         ← the Tileset Editor workspace
        └── dialogs/         ← the New scene dialog, the scene actions
```

## The plugin

### `JustGameEditorPlugin`

`lib/src/core/plugin/editor_plugin.dart`. An `EnginePlugin` (id `editor`): `attach` runs `onInitialize`, the engine's `update` runs `onUpdate`, and `renderOverlay` (which the engine calls from its overlay hook, after the world is drawn) runs `onRender` while the editor is visible.

`register({engine, scope, modules, spawners, bindPhysicsBodies, toggleKey, statusPanelToggleKey, protectedSceneNames, startVisible, onReassemble})` is the only way to make one. It returns null outside a debug build and off the desktop (`supportsPlatform`). Without a `scope` the plugin makes and owns one with the given modules; with one, the modules are registered into it.

- **`onInitialize`**: starts `EditorPresence` and the log session; adds the editor's systems (below); points the engine's loaders at the project's files (`engine.context.overrideLoaders`: sprites, animator graphs, timelines, tile text, through `FileSpriteAssetLoader`, restored on detach, so another engine in the process is not affected); adds the sprite, level-map and map-collision default systems; sets up camera ownership and Level Map focus; installs the hardware key handler; and `scope.reload()`s.
- **`onUpdate`**: the modules' `onUpdate`, the play controller's tick, autosave, and which runtime systems run (below); while visible, the 3-D fly keys and a snapped evaluation of the camera brain while authoring.
- **`onRender`**: the grid (or, in 3-D, the ground grid), the camera rigs, markers, viewport overlays and handles, the gizmo, the collider being edited, and the game preview.

The plugin owns visibility, keyboard dispatch, the grid and the Level Designer session, and hands everything else to services that take only what they need: `playController` (`PlayController`, `core/play/`), `sceneIO` (`SceneIO`, `core/scene/`), `entities` (`EntityOps`, `core/entity/`), `viewport` (`ViewportInput`, `core/input/`), `sceneManager`. Panels take the service they need rather than the plugin. Its signals are `isVisible`, `isStatusPanelVisible`, `showGrid`, `showGamePreview` and `gridSize`; `isAuthoring` and `isGridVisible` are computed from them.

`reassemble()` is called by the overlay's `State.reassemble` on a hot reload: the app's `onReassemble`, the component definitions (`EngineContext.refreshDefinitions`), the scope's registries (`EditorScope.reassemble`), the designer's tools, the built-in docks, and live components a changed definition no longer fits (see the README's *Hot reload and hot restart*).

### `JustGameEngineEditor`

`lib/src/integration/just_game_editor_adapter.dart`. In a debug build it registers the plugin with `engine.plugins` and makes sure `engine.world.render` is an overlay hook, so the world is drawn before the editor; it builds `JustGameEditorOverlay(gameChild: GameWidget(...))`. With no plugin (a profile or release build, or no desktop) it is a plain `GameWidget`.

### The editor's systems

| System | From | Added |
|--------|------|-------|
| `SimpleMovementSystem` | the engine | always |
| `EditorLogCaptureSystem` | `core/ecs/systems/` | always: logs changes in the entity and system counts |
| `PhysicsBodyBindingSystem` | `core/ecs/systems/` | with `bindPhysicsBodies` (the default): while authoring, a body being dragged is held still and kept awake |
| `PhysicsJointBindingSystem` | the engine | with `bindPhysicsBodies` |
| the sprite, level-map and map-collision default systems | the engine (`registerDefaultSystems`) | always |

Each is added only if the world has none. What runs depends on whether the editor is authoring (`_syncRuntimeSystems`): `TimelineSystem` and `MapCollisionSystem` run only in a play-test (map collision is built at Play and its generated bodies cleared after), the Level Map's tile animation runs on wall time while authoring, and the render filter hides what the editor hides.

## The scope and its state

### `EditorScope`

Everything one editor owns, in a `just_di` container (`just_editor_core/lib/src/scope/editor_scope.dart`): the component definitions, the `SceneCodec`, the scene store (`scenes`), the field-editor, extras, prefab, layer, command and module registries, the undo stack (`history`), the preferences (`prefs`), the theme, the chrome state, the log, the `EditorSceneState`, hide and lock (`view`), the project's tags, physics layers and colours, and the editor's view and camera brain (`editorView`, `cameraBrain`). The services only the editor uses — the dock controller, `EntityOps` (`entities`), the Level Map's (`mapDocs`, `tiles`, `mapProvision`) — are this package's: `EditorScopeServices` (`lib/src/core/scope/editor_scope_services.dart`) puts them on the scope as getters, each registered in its container the first time it is asked for. The scope holds no built-ins of its own either: the editor makes it with `builtIns: [BuiltInEditorModule.new]` (the plugin adds it to a scope it is handed), a module registered ahead of every other whose Level Designer contributions are live whichever designer is chosen; `modules.all` lists the others, `modules.withBuiltIns` both. There are no process-wide registries: two scopes share nothing, and `reload()` rebuilds every registry from the built-in module and the registered `EditorModule`s, so nothing accumulates across hot reloads; a module's `onRegister` runs on its first pass only, and `reassemble()` (a hot reload) runs each module's `onReassemble` and remakes the theme presets before rebuilding. `EditorScopeProvider` makes it available to a widget subtree.

The scope also holds what the editor is doing: `activeWorkspace`, `activeDesigner`, `isPlayTesting`, `spawners` (read at Play), `hiddenOverlays`, `highlightedLayer` and `highlightedTag`, and `authoredStateGuards` (below).

### State management

All editor state is `just_signals`: `Signal` fields on the services (`PlayController.state`, `DockController.openId`, `ThemeController.current`, `EditorLogService.entries`, `EditorPrefs.settings`, `EditorChromeState`, `EditorSnackBarController`) and on the plugin, with `Computed` for what derives from them. Widgets read `.value` and rebuild through `SignalBuilder` (one signal), `SignalBuilder2` or `SignalConsumer` (several); `batch()` groups the writes of one operation into one notification. Nothing in the editor extends `ChangeNotifier`; the only listenables left are Flutter's own controllers and the debugger's `JustDebuggerController`.

### `EditorSceneState`

The open scene and the selection (`just_editor_core/lib/src/model/editor_scene_state.dart`). Every piece of it is a `Signal`: `activeScene`, `sceneMode` (2-D or 3-D, from the file's header; `editingMode` reads it), `selectedEntity`, `multiSelectedIds`, `isDirty`, the grid and snap steps (`gridSize`, `moveStep`, `moveStep3D` in metres, rotation and scale steps), `localGizmo`, `clipboard` — plus `revision`, bumped by any edit no other signal captures (a transform drag, a rename, a component added). A panel watches only what it reads. Hide and lock are `EditorViewState` (`scope.view`): the editor's alone, never saved.

## Commands, keys and focus

Every action that has a key is a `DesignerCommand` in the scope's `CommandRegistry` (`ui/level_designer/commands/`), bound by a `KeyBinding`. A command has a scope: `always` (runs even while typing in a field: Play, Save, the docks), `editor` (not while typing: undo, copy, delete, the transform modes, the 3-D view) or `designer` (only with the Level Designer open: nudges, quarter turns, hide and lock, bookmarks). A command or binding can also be limited to 2-D or 3-D scenes (`Dimensions`). Dispatch takes the newest binding whose chord matches exactly and whose command fits the scope and the scene's mode, so a module's binding (added after the built-ins) beats a built-in's, and one chord can mean one command in 2-D and another in 3-D (F frames the selection in both, through different commands). The changed keys from Settings → Keyboard (`editor.keys.shortcuts`) are laid over the bindings with `applyShortcuts`, again after every `reload()`.

The plugin's `HardwareKeyboard` handler sees every key before the focused widget. In order: a chord being captured in Settings takes everything; the 3-D fly keys are swallowed while the right button is held; F1 toggles the editor; the settings dialog keeps every key but Esc; **a focused `EditorKeyClaim` that claims the key gets it alone**; F2 toggles the dock panel; nothing more while the editor is hidden or a workspace is open; `always` commands (after `PendingFieldEdits.flush()`, so a save keeps what is being typed); nothing more while typing in a field; the collider being edited (Esc, Delete); the Level Designer (its tool's `onKey`, then `designer` commands, then a bare letter that picks a tool); and last the `editor` commands.

Flutter delivers a key to the focused widget even when a handler has taken it, so a panel that acts on keys of its own must wrap itself in `EditorKeyClaim(claims: …)` with exactly those keys; otherwise both it and the editor act (one Ctrl+D, two copies). The scene tree, the Scenes panel, the Timeline dock and the colour picker do. A workspace's keys are its own while it is open (`WorkspaceKeyScope`).

## Undo

One stack per editor: `EditorHistory` (`scope.history`, `just_editor_core/lib/src/model/editor_history.dart`), as deep as the Undo steps setting (200 by default). An `EditorCommand` has a `label`, `redo`, `undo` and `mergeWith(next)`; `push` runs a command, `pushApplied` records a change already made, `jumpTo` serves the History dock, and `breakMerge` ends a run of merging. `canUndo`, `canRedo`, the next labels and `revision` are signals.

- **Entity commands** (`editor_commands.dart`): `TransformCommand` (before and after poses; one per gesture unless given a `mergeKey`), `CreateEntitiesCommand` (with `adopting` for entities already made), `DeleteEntitiesCommand`, `AddComponentCommand`, `RemoveComponentCommand`, `ReorderComponentsCommand`, `ComponentFieldCommand` (merges with the next edit of the same field of the same component, so a scrub is one step), and `EntityStateCommand`, the state undo: whole `EntitySpec`s before and after, for edits too wide to describe field by field. `CompositeCommand` makes several one step, undone in reverse.
- **Hierarchy and maps**: `ReparentCommand`, `ReorderCommand`, `RenameCommand`, `SetEnabledCommand`, `GroupCommand`, `UngroupCommand` (`just_editor_core/lib/src/model/hierarchy_commands.dart`); `TileEditCommand` and `MapStructureCommand` (`core/level_map/tile_commands.dart`); `ColliderEditCommand`.
- **Editing a component as a whole**: `ComponentEdit.begin(scope, component)` … `commit(label)` (`just_editor_core/lib/src/model/component_edit.dart`) records every saved field that changed as one step. A viewport handle's drag is one (`HandleDragSession`).
- **Fields**: the inspector pushes a `ComponentFieldCommand` per change. `LivePreview` shows a value without recording it (a colour picker that is open) and `PendingFieldEdits` (`just_editor_core/lib/src/look/kit/fields.dart`) keeps what is typed in a field when anything else happens first.
- **Documents of their own** keep their own stacks: the Timeline (`TimelineSession`) and the Tileset Editor (`TilesetSession`) hold snapshots. `EditorHistory.dirty`, `markSaved()` and `breakMerge()` let a module's document show whether it is saved (the interface and sprite editors do); the scene's unsaved mark is `EditorSceneState.isDirty`.

## Scenes on disk

- **`SceneStore`** (`just_editor_core/lib/src/model/scene_store.dart`): the folder `assets/scenes/` under the working directory, one `<name>.scene.json` per scene, the play order in `scenes.json` (`SceneManifest`). `SceneManager` lists, renames, duplicates and deletes, refusing `protectedSceneNames`. New scenes are `SceneStarters.forMode(name, mode:)` from `just_game_engine_formats`, the same starters `just game scene new` writes (`test/scene_starters_parity_test.dart` keeps them matching the live components).
- **`SceneCodec`** encodes and decodes entities through each component's `ComponentDefinition`; the file is `{version, name, mode, entities, editor}`, each entity `{name, parentName, components: [{type, fields}]}` (plus `enabled: false` when off). `version` is `SceneFormat.current` (9). The `editor` section is `LevelDesignerSession.editorData()`: the designer in use, guides, view bookmarks and each module's `saveEditorData` under its id. The game never reads it.
- **`SceneIO`** (`core/scene/scene_io.dart`) opens and saves, one at a time. Opening clears the world and the history, migrates an older file in memory (`SceneFormat.migrateWithReport`, with the context's migration hooks; "Save to persist" in the Console), decodes, re-links parents by name and tells the modules (`onSceneOpened`). Saving writes the map files first (`mapDocs.saveDirty()`), and during a play-test saves the level as authored (the snapshot's records), never as play left it. The shipped game reads the same files through `SceneLoader`, which migrates the same way.
- **Authored state.** `EditorScope.authoredStateGuards` / `restoreAuthoredState()`: anything previewing a change in the live world (the Timeline's preview) registers a guard; saving and Play call `restoreAuthoredState()` before they read the scene, so a preview never leaks into a save or a play-test. Autosave waits while one is held.
- **Autosave and recovery.** On the plugin's tick, every `autosaveMinutes` (2), when the scene is dirty: a backup to `.editor_backups/<scene>/<stamp>.scene.json` (keeping `backupsToKeep`, 10, and skipping one identical to the last), or a save if `autosaveMode` says so. `openScene` asks `askToRecover` (wired by the overlay) when the newest backup is newer than the file and differs from it: recovering opens it marked unsaved; declining sets it aside.
- **Logs and presence.** `EditorLogService` keeps the log in `.editor_logs/editor_runtime.jsonl` (rotated at 5 MB) and replays it at start; `EditorPresence` touches `.dart_tool/just_core_cli/editor.lock` every 5 seconds (not under `flutter test`) so the `just` tool knows the editor has the project open.

### Unknown components

A scene can name a component no registered definition can read — a module not registered this session, or one that moved to another package (the interface components did, to `just_ui_editor`). `SceneCodec.decodeAll` collects every such entry on an entity into one `UnknownComponents` (`just_editor_core/lib/src/model/unknown_components.dart`), exactly as the file had it, and `encodeAll` writes them back unchanged. `BuiltInValidators.unknownComponents` lists each entity that holds one as an error in Problems — the game will not load the scene until the module is registered — and the inspector shows a card for it. `SceneCodec.inTreeOrder` (parents first, the order a file wants) and `encodeInOrder` are public for callers that need records paired with entities, such as the play-test snapshot.

## Play-testing

`PlayController` (`core/play/play_controller.dart`; `EditorPlayState` stopped, playing, paused). `play()` from stopped restores the authored state, resets the camera brain, captures a `PlaySnapshot`, spawns at every spawn point through `scope.spawners` (a spawn point naming no spawner is a warning) and sets the time scale to the speed (0.25, 0.5, 1 or 2). `pause()` sets it to 0, `step()` runs one frame, `restart()` stops and plays. `stop()` destroys what was spawned and restores the snapshot. The Play-testing settings can pause on a logged error and hide the chrome while playing.

### The play-test snapshot

`PlaySnapshot` (`core/state/play_snapshot.dart`) captures the authored scene when play starts and puts it back when it stops. It takes the entities in tree order and encodes them in that same order, so record *i* belongs to entity *i*; each record also keeps its parent as an index into the records, not an id. Restoring applies each record to its own entity in place (ids, selection, undo and bound physics bodies stay valid), recreates only what play destroyed and removes only what play made, then rebuilds every parent and child link from the records' indices. What the engine generates (`GeneratedEntityComponent`: map collision bodies) is never authored.

### Cameras

The engine's virtual cameras are ordinary entities with ordinary definitions, so the inspector, picker, prefabs and save format need nothing camera-specific. What the editor adds: `EditorScope.cameraBrain`; the hand-over in `JustGameEditorPlugin._syncCameraOwnership` (authoring: `brain.driveOutput = false`, the output camera *is* the editor view; Play: the brain drives it and the view is restored on Stop) plus a `snap` evaluation on the unscaled tick; `CameraRigPainter` / `CameraRigOverlay` (`lib/src/ui/overlay/camera_rig_painter.dart`) for frames, framing zones, triggers, bounds and tracks; the game preview, which renders the world — and the engine's scene renderers, so a 3-D game's image too — with the output camera briefly showing `brain.liveState`; and `BuiltInCameraContributions` (`lib/src/extension/`), which adds Solo and the LIVE badge through the same scene-tree and inspector seams a module uses. Every system that draws captures the one output camera object, which is why ownership is a flag on the brain rather than a second camera.

## The viewport

### Views

What the editor looks through is an `EditorView` (`just_editor_core/lib/src/view/editor_view.dart`): screen to world and back, a ray from a screen point, the point on the ground under it, zoom and pan, and whether it is planar. `GameCameraEditorView` is the 2-D one (the game's main camera, moved by the editor). `OrbitFlyEditorView` (`core/view/orbit_fly_editor_view.dart`) is the 3-D one: a pivot, a distance, yaw and pitch, with `orbit`, `pan`, `dolly`, `look`, `fly`, `focusOn(Aabb3)` and `viewFrom(yaw:, pitch:)`; the engine's +Y is down and the ground is y = 0. `EditorScope.editorView` keeps one view per scene mode, made by a module's `viewFactories[mode]` (the last module wins) or the built-in one.

### Input

`ViewportInput` (`core/input/viewport_input.dart`) takes the viewport's pointer while authoring. A press goes, in order, to 3-D navigation (right button to look, Alt+left to orbit, middle to pan; a right click that does not travel opens the menu), the collider being edited, a viewport handle, the Level Designer's tool, and the gizmo. `flyTick` flies the 3-D view while the right button is held. A gizmo drag ends in `commitTransform`, one `TransformCommand`.

### Picking

`EntityPicker` (`just_editor_core/lib/src/view/entity_picker.dart`) answers `pickAt` and `pickInRect`; `PlanarEntityPicker` is 2-D's. `RayEntityPicker` (`just_editor_core/lib/src/view/ray_entity_picker.dart`) casts the view's ray at each entity's box — the union of its components' `ComponentExtent`s, transformed, or a half-metre cube — nearest first, and asks the modules' `EntityRayTest`s (`EditorModule.pickTests`) for the exact distance to the shape inside; a test that does not know the entity lets the box decide. `placementAt` gives a `SurfacePoint` (position, normal, and what it lies on): the face of the nearest box, else the ground.

### Gizmos

In 2-D, `GizmoPainter` draws one of Move, Scale or Rotate, as `scope.view.transformMode` and the floating `TransformToolbar` say, through `TransformGizmo` (`ui/overlay/transform_gizmo.dart`), which the Level Designer's select tools draw and hit-test with too; `GizmoHitTester.hitTest(mode:)` answers only that mode's handles. In 3-D, `Gizmo3D` (`ui/overlay/gizmo_3d.dart`) has the uniform-scale centre, plane squares, axis arms and rotation rings, in the world's axes or the entity's own (`localGizmo`); `RayGizmoHitTester` finds a handle, then a body; `RayGizmoDragSolver` (`core/input/ray_gizmo_drag_solver.dart`) moves along an axis or across a plane, turns by the angle swept in a ring's plane and scales, snapping to `moveStep3D`, the rotation step and the scale step. `paintGroundGrid` draws the 3-D grid around the view's focus.

### What a module draws and places

- **Markers** (`EditorMarker`, `just_editor_core/lib/src/extension/editor_marker.dart`): an icon at each entity with given components; cameras and spawn points are the built-ins.
- **Viewport overlays** (`ViewportOverlay`, `just_editor_core/lib/src/extension/viewport_overlay.dart`): painting over the viewport while authoring, in the scene modes named, given a `ViewportOverlayContext` (canvas, size, view, scope, world, selection, a `project` helper); `scope.hiddenOverlays` turns one off.
- **Handles** (`ViewportHandles`, `just_editor_core/lib/src/extension/viewport_handles.dart`): points of the single selection to drag or click (`ViewportHandle` with `onDrag(HandleDrag)` — on a plane, along a line, snapped with Ctrl — and `onClick`). `HandleDragSession` picks them before tools and the gizmo and records each drag or click as one step.
- **Asset kinds** (`AssetKind`, `just_editor_core/lib/src/extension/asset_kind.dart`): a kind of file's icon, colour, filter chip, preview and `drop` (given an `AssetDrop`: where, and a `place` helper). `AssetKinds.active` asks the modules' kinds first. `JustGameEditorPlugin.dropAsset` runs a kind's drop, else the built-in drops (tileset, map, Tiled map, image, sprite sheet).
- **Prefabs in space.** In 3-D the viewport menu (`ui/overlay/viewport_menu.dart`) offers every prefab whose `dimensions` allow 3-D, from every module, and each `PrefabVariant` (`just_editor_core/lib/src/extension/prefab_variant.dart`) of them that applies — more than eight are grouped by category — placed with `PrefabDefinition.buildAt(SurfacePoint)`, as one `CreateEntitiesCommand`.

## Physics in the editor

- **2-D.** `PhysicsBodyExtras` (`ui/inspector/physics/physics_body_extras.dart`) adds to the engine's definitions: the summary line, the material presets (one step), notes, and the live readout while playing; on `Collider2D`, *Fit to visual* and *Edit collider*. `ColliderEditSession` puts the handles on a collider in the viewport (2-D only; one `ColliderEditCommand` per change), and stops when the selection changes or play starts. The collision layers are `ProjectPhysicsLayers` (`core/physics/`; `assets/project/physics.json`, pushed to the engine on every change), renamed and deleted across scenes by `LayerRefactor`, counted by `PhysicsBodies` (2-D and 3-D), edited in the Physics Layers dock.
- **3-D.** `BuiltInPhysics3DContributions` (`extension/built_in_physics_3d_contributions.dart`) applies when the engine's definitions know `RigidBody3D` (`appliesTo`): the material presets for `RigidBody3D`, `ColliderOverlay3D` (`core/physics/collider_overlay_3d.dart`: colliders, sensors and characters as wireframes, a matched shape by its solid parts, hulls outlined by `HullOutline`) and the Solid and Trigger prefab variants (a static body or sensor with a collider matching the shape). `Physics3DChecks` are always in the built-in checks and look only at 3-D scenes.

## The inspector: definitions, field editors, extras

Every row is a label of `InspectorField.labelWidth` and then its control, and every control is the same box — `InspectorField` (`just_editor_core/lib/src/inspector/field_style.dart`) holds the fill, border, corner, padding, type size and height, and hands out the `InputDecoration` for text fields and a `BoxDecoration` for what is not one. A new kind of field takes its look from there; `inspector_look_test.dart` measures a real panel and fails if the boxes stop agreeing. A component's inspector section is built from its runtime `ComponentDefinition` (`just_editor_core/lib/src/inspector/definition_section.dart`): the fields from the schema, the name, icon, labels, groups and scrub feel from its `ComponentHints`. There is no second, design-time description. `FieldEditorRegistry` (`field_editor.dart`) maps each `FieldType` id to a control — the built-ins in `built_in_field_editors.dart` (including the compound physics-shape editor), a module's `fieldEditors` over them. `ComponentExtrasRegistry` (`component_extras.dart`) holds what the editor adds beyond fields: header actions, a custom section, a replacement editor for one field. A component a scene names but no registered definition reads is kept, not dropped (see *Unknown components*), and shows as a card of its own (`UnknownComponentsCard`). A workspace with a document of its own builds its inspector with `buildComponentSections(history:, world:)` and adds components with `AddComponentPicker(history:)`; left out, both are the level's.

The Add Component catalogue is `getComponentRegistryEntries(scope)` (`just_editor_core/lib/src/model/component_registry.dart`): every definition the scope knows as a `ComponentEntry` (name, group, description, factory, `allowMultiple`), grouped by `ComponentHints.group`. It owns no state; it is a view over `scope.definitions`.

`ScrubbableNumberField` (`just_editor_core/lib/src/look/widgets/scrubbable_number_field.dart`) is the number field everywhere: typing, and dragging to scrub, as the field's `ScrubHint` says.

## Problems

A check is a `SceneValidator` (`just_editor_core/lib/src/validation/scene_validator.dart`): a function from a `ValidationContext` to `SceneProblem`s, each with a message, a severity (warning or error), the entity, a hint and `ProblemFix`es — a label and an edit pushed on the undo stack like any other. `BuiltInValidators.all` (`lib/src/core/validation/built_in_validators.dart`) holds the editor's own: missing assets, entity references that name nothing, animator clips a sheet lacks, timelines, cameras with nothing to follow, the tag checks (`TagChecks`: unknown tags, spawn points with no spawner, targets naming nothing), the physics checks (`PhysicsChecks`, `Physics3DChecks`), drawing with no transform, the Level Map checks, unshipped tile and layer files, and unknown components. A module adds checks with `EditorModule.validators`. `ProblemScan` runs them all, errors first, caches the result for a moment for the dock, its tab badge and the status strip, and turns a check that throws into a problem of its own.

## The module contract

An `EditorModule` (`just_editor_core/lib/src/extension/editor_module.dart`) declares what it adds; the scope folds it in on every `reload()`. Its members, by where they show:

- **Lifecycle**: `id` (reusing one replaces the module), `name`, `icon`; `onRegister(EditorModuleContext)` once, `onReassemble` after each hot reload, `onSceneOpened`, `onUpdate`, `onAssetChanged(path)` (a file in the project changed), `onPlayStateChanged(playing)`, `dispose`.
- **Level Designer**: `prefabs` (only while the module is the Level Designer in use) and `sharedPrefabs` (in every Level Designer), `prefabCategories`, `createTools` and the `toolGroups` they stand under, `overlays` (an `InteractiveOverlay` also takes pointer input, topmost first, before any tool), `createSnapProviders`, `createSessionState` (reached from a tool through `ToolContext.stateOf<T>()`, kept across reloads), `saveEditorData` / `restoreEditorData` (the scene file's `editor.modules.<id>`), `statusControls`, `designerPanels`, `layers`, `gridTopology` (`SquareGrid` by default; `HexGrid`, with `HexGridModule` in the package), `tiledObjectMappers`, and `providesLevelDesigner` (the module is an entry in the designer switch).
- **Commands**: `commands` and `keyBindings`.
- **Chrome**: `docks`, `workspaces`, `settingsSections`, `toolbarButtons`, `gettingStartedTips` (the start card), `themePresets`.
- **Scene tree**: `sceneTreeActions`, `rowDecorations`, `entityIcons` (the first module to answer wins, lowest `order` first), `protectionRule`.
- **Inspector**: `fieldEditors`, `componentExtras`, `componentGroups`, `inspectorSections`, `inheritedColors` (what an unset colour field falls back to, so the inspector shows the colour and where it comes from).
- **Assets**: `assetKinds`, `assetActions` (buttons on Assets-dock rows), `dataFileSuffixes` (the JSON files the module owns, so a `.ui.json` is never taken for a sprite atlas).
- **3-D**: `viewFactories`, `markers`, `pickTests`, `viewportOverlays`, `viewportHandles`, `prefabVariants`.
- **Project data and checks**: `tags` (built-in tag names its code relies on), `validators`.

`EditorModuleContext` gives `onRegister` the scope, the world and whether this is a debug build; `DesignerToolContext` gives `createTools` the scope, world, scene state, history and a unique namer. `saveEditorData`, `restoreEditorData`, the status controls and the side-panel sections are handed a `DesignerSession` — the open designer as a module sees it (scope, world, scene state, history, controller, camera, `setTool`, `stateOf<T>()`) — and a command's `CommandContext` carries it as `session`, with `host` for what dispatched it; the editor's own commands read the concrete session and plugin through `EditorCommandContext` (`designer`, `plugin`). `fieldAccessories` put a widget beside a component's fields and hear of each edit made through them: the timeline's key button is one.

### The Level Designer's seams

Module designers are opt-in per scene. `EditorScope.designers` lists every module with `providesLevelDesigner`; `activeDesigner` (a signal, null for the built-in designer) and `selectDesigner()` choose one, and the scope recomputes prefabs, layers, grid, palette categories, status controls and side-panel sections from the built-ins plus that module. `LevelDesignerSession` watches the signal and reloads its tools, overlays, snap providers and module state; the palette, tool strip, layers panel, status bar and side panel rebuild through it. `DesignerSwitch` (`panels/designer_switch.dart`) is the header control, shown only when there is something to switch to. The session writes the choice as `editor.designer` and restores it before the module data. `DesignerConfig` and `SelectionHandleLayout` are scope services for what used to be literals. The designer's cells are a `GridTopology` (`just_editor_core/lib/src/designer/grid/`; `HexGrid` is this package's); tools reach it as `context.grid`. A prefab's `depth` fixes the depth it goes to (see *The Level Map*).

### The overlay's seams

Modules *append* to the built-in set — docks, toolbar buttons, settings sections, scene-tree actions and row decorations, inspector sections, theme presets. The built-in docks, the right panel's order and the play toolbar's own buttons are private and cannot be replaced or reordered from outside; that is the deliberate cut. The in-game interface is a module like any other: `UiEditorModule`, in `just_ui_editor`; the editor has no interface editor, Theme dock, UI mode or interface tree of its own.

## The overlay

### `JustGameEditorOverlay`

The widget over the game canvas (`lib/src/ui/overlay/editor_overlay.dart`). It provides the `EditorScope`, the theme (`EditorThemeScope`) and the messenger to everything below, portal children included, and is split into libraries by responsibility:

| Library | Responsibility |
|---------|----------------|
| `chrome/editor_chrome.dart` | The full chrome: toolbar, viewport, right panel, status bar; `WorkspaceHost`; the compact chrome while hidden or playing |
| `docks/` | The dock panel: `CompactStatusDock`, `DockController`, the shell (`BuiltInDocks`, `DockPanel`, `DockPopouts`) and one folder per built-in dock |
| `settings/settings_dialog.dart`, `settings_catalog.dart`, `shortcut_row.dart`, `overlay_settings_store.dart` | The settings dialog — a page per subject, search over all of them, in `EditorDialogFrame` — opened by the gear at the viewport's foot or Ctrl+,; each module `SettingsSection` gets a page under MODULES. The catalog lists every built-in setting; the store's `encode`/`decode` is the one table a save, a load, an export and an import all use |
| `right_panel/right_panel.dart` | Right sidebar host (the Scenes panel, or the scene tree and inspector); while the Level Designer is open, Inspector \| Level tabs (`EditorChromeState.rightPanelTab`) |
| `start/start_card.dart` | `EditorStartCover` + `EditorStartCard`: what `GameCanvasArea` shows over the game while no scene is open (steps, live keys, module tools and `GettingStartedTip`s) |
| `shared/` | The play toolbar (transport, view and mode, then module `ToolbarButton`s), `TransformToolbar`, `QuickSnapBar`, stacked messages |
| `chrome_state.dart` | `EditorChromeState`: transient widths and open dialogs, a scope service |
| `gizmo_painter.dart`, `transform_gizmo.dart`, `gizmo_3d.dart`, `viewport_menu.dart`, `camera_rig_painter.dart` | What is drawn over the level, and its right-click menu |

### Theme, sizes and the kit

`EditorThemeData` (`just_editor_core/lib/src/look/editor_theme_data.dart`) holds the palette — accent, surfaces, borders, text, and error, warning, success and info; `ThemeController` (a scope service) holds the current one and the presets — five built-in accents, plus any a module contributes. The overlay root keeps it in step with the settings and applies it to `EditorTheme` (`just_editor_core/lib/src/look/editor_constants.dart`), whose getters every widget reads (`EditorTheme.accent`, `EditorTheme.surfaceBg`…), and builds the chrome again when it changes; `EditorTheme.of(context)` reads the same palette through the tree. `EditorMetrics` (`just_editor_core/lib/src/look/editor_metrics.dart`) is the same for sizes: radii from the corner radius, gaps from the density, durations from the animation speed. Text needs neither: `EditorLook` (kit) scales it with a `TextScaler`, so a font size is written as it reads at 100%. The accessibility settings sit over all three: high contrast and the colour-blind safe colours are variants of the palette the overlay applies (`highContrast()`, `colourBlindSafe()`); bigger targets, no motion and longer timings are `EditorMetrics`; bold text, reduced motion and tooltip timing are `EditorLook`'s, which the chrome, and every dialog and menu the editor opens, sit under.

Who follows which setting: the scope, from the first time its prefs are read, keeps its services in step — `EditorHistory.capacity`, `EditorLogService.maxEntries`, the scene state's snap steps, and the changed keys laid over the command registry (`applyShortcuts`, again after every `reload()`). The plugin keeps the painting and the play-test in step — `ViewportLook` (grid colour and strength, handle size, selection colour, read by the painters), the backdrop while authoring, pause on error, autosave on its update tick, and where the session was left. The overlay supplies the questions only a window can ask (`plugin.askToRecover`, `EntityOps.confirmDelete`), reopens the last session once the settings load, and steps aside for the game while a play-test runs if asked. Preferences are `EditorPrefs` (`core/prefs/`) over the machine's `just_storage`; a module keeps its own with `SettingPref`. Settings export to and import from `.editor/settings.json` or the clipboard.

Build UI from the kit (`just_editor_core/lib/src/look/kit/`, exported): `EditorIconButton`, `EditorToolButton`, `EditorButton`, `EditorSearchField`, `CommitTextField`, `EditorToggle`, `EditorSegmented`, `EditorSlider`, `EditorChip`, `EditorBadge`, `EditorToolbar`, `EditorSectionHeader`, `EditorCard`, `EditorEmptyState`, `EditorAlert`, `showEditorConfirm`, `askToSaveChanges`, `EditorDialogFrame`, `EditorKeyClaim`, and a workspace's frame (`WorkspaceHeader`, `WorkspaceFullScreenButton`, `WorkspaceKeyScope`, `mayLeaveUnsaved`; see *Workspaces*) — and `editorMenuItem(shortcut:)` for menus. They take their colours and sizes from the above, so they follow the settings; every target is at least 24 px. The sprite editor's and input editor's own palettes (`StudioPalette`, `InputEditorPalette`) are handed the editor's by the modules that open them.

## The dock panel

The foot of the editor is a status strip and, above it, one tabbed panel (`ui/overlay/docks/`). `CompactStatusDock` is the host the chrome mounts — in the Level Designer too, where the order bottom up is the status strip, any open panel, then the designer's status bar standing on them, with the designer inset by `DockController.panelHeight`. `DockPanel` is the tab bar (a right-click on a tab: pop out, maximise, take off the bar; `+` lists every dock not on the bar, popped-out ones included), header and active dock; `DockStatusStrip` is the status bar — a line of facts, each a button to where it came from (errors to the Console on its errors, the frame rate to the Profiler, a module's readout to its dock with `DockReadout.openArgs`), and the rest of the bar opens or shuts the panel (F2); `DockPopouts` floats the docks that were popped out, which reopen where they were left. `DockController` holds what is open, tab order, pins, heights, maximise, pop-outs and each dock's memory, and persists all of it as one JSON preference (`editor.docks`).

The built-in docks, in order: Console (`logs`), Assets, Timeline, Profiler (`fps`), World (`entities`), Problems, Tags, Physics Layers (`physics`), History, Animator and Search. Every dock is a `DockDefinition` — the editor's own are in `docks/shell/built_in_docks.dart`, registered exactly as a module's are:

```dart
@override
List<DockDefinition> get docks => [
  DockDefinition(
    id: 'mygame.waves',
    label: 'Waves',
    icon: Icons.waves,
    order: 200,                       // built-ins use 0–99
    tabBadge: (scope) => DockBadge('3', DockSeverity.warning),
    readout: DockReadout(label: 'Waves', value: (scope) => '3 left'),
    headerActions: (context, dock) => [/* buttons */],
    keepAlive: true,                  // stay built while another tab shows
    build: (context, dock) {
      final filter = dock.memory?.read<String>('filter'); // survives restarts
      return MyWavesView(filter: filter, args: dock.args);
    },
  ),
];
```

Build a dock from the kit (`EditorToolbar`, `EditorSearchField`, `EditorChip`, `EditorIconButton`, `EditorEmptyState`) and `DockTable` from `docks/shared/dock_widgets.dart`, and it looks like the rest. Two rules keep the panel cheap: a readout and a tab badge are polled a few times a second, so they must be cheap to compute (cache, as `ProblemScan` and `AssetIndex` do); and a dock listens to what it needs itself — the panel does not rebuild it on a timer. The Console's command line runs registered commands only (by id, label or prefix); it never evaluates code.

## Workspaces

A module can open a large tool of its own over the editor, as a dialog with the level dimmed behind it (`WorkspaceHost`; `presentation: fullScreen` to fill instead) — `WorkspaceDefinition` in `EditorModule.workspaces`, opened with `EditorScope.openWorkspace(id, {path})` or, for a file, `openInWorkspace(path)` (the longest matching file ending wins). `activeWorkspace` is the one that is open; the chrome mounts it over everything, and while it is there the key handler hands the level's commands nothing, so the workspace's own `Focus` owns Ctrl+S and the letter keys. It is built with a `WorkspaceContext` whose `reloadAssets(path)` is how a tool tells the running level a file changed (`JustGameEditorPlugin.reloadAsset` → the engine's sprite and animator systems). `AssetAction` (`EditorModule.assetActions`) puts buttons on Assets-dock rows. The Sprite Studio (`just_sprite_editor`) was the first user of both.

The editor brings one workspace of its own, the Tileset Editor (`BuiltInWorkspaces`, `ui/tileset/built_in_workspaces.dart`). The interface editor is `UiEditorModule`'s, from `just_ui_editor`.

**Close guards.** A workspace with unsaved work registers what to ask before it goes through `WorkspaceContext.setCloseGuard` — the chrome passes it on to `EditorScope.setWorkspaceCloseGuard(guard, of: open)`. `openWorkspace` asks the open workspace's guard before opening another over it, and opens only if the guard agrees; `requestCloseWorkspace()` asks it before closing. Clearing a guard (`null`) only clears the asker's own, so a workspace let go after another opened in its place leaves the new one's question in place. A workspace that asks for itself calls `closeWorkspace()` once it has.

**The frame** (`just_editor_core/lib/src/look/kit/workspace.dart`, in the kit) is what every workspace is built with, so they read as one editor's windows: `WorkspaceHeader` (icon, title, the open file, a dot while it is not saved, Save, Undo and Redo — `showHistory: false` hides the last two — the workspace's tools, full screen and close), `WorkspaceFullScreenButton`, `WorkspaceKeyScope` (keys go to the workspace except while typing in a field; a click on anything that is not a field takes them back; focus is asked for after the first frame, since a route that finishes opening later would otherwise take it) and `mayLeaveUnsaved` (asks Save / Don't save / Cancel and does it; false if the save failed). The Tileset Editor is built with them, and its close guard is `mayLeaveUnsaved`.

## The Timeline

`lib/src/ui/timeline/`. The runtime is the engine's (`subsystems/timeline/`); the editor adds a session and views of it.

- **`TimelineSession`** (`TimelineSession.of(scope)`, one per editor) holds the open `TimelineAsset` — a file, or the inline timeline of the selected entity's player — as an immutable value, so undo is a list of assets and a drag is one step (`beginDrag` / `dragItems` / `endDrag`). Things on tracks are addressed as `TimelineItemRef(track, index)`; every edit that re-sorts items returns where they went. An inline edit is written into the player and marks the scene dirty; a file is saved on request and on leaving it.
- **Preview** drives a `TimelinePlayback(isPreview: true)` against the live world. The engine calls `onWillWrite(component, field)` before a track first writes a field; the session keeps the field's saved form and `endPreview()` decodes it back. It is an authored-state guard (see *Scenes on disk*), and the plugin switches `TimelineSystem.isActive` off while authoring, so nothing but the session moves a timeline in the editor.
- **Record** compares every animatable field of the watched entities (the owner, and whoever a track is bound to) with what it held when the timeline was last shown; a difference is an edit, keyed at the playhead, and the field's pre-edit value is what `endPreview()` restores. The inspector calls `captureEdits()` on every change and the dock polls it for gizmo drags.
- **Two ranges, deliberately different.** The **work range** is the editor's: a stretch to loop while working, not saved. The **play range** lives on the entity's `TimelinePlayerComponent` (`from` / `to`) and is what the game plays. `applyWorkRangeToPlayer` is the one place the first becomes the second, and the ruler draws them apart — the play range dims what is never played and carries a grip at each end; the work range is a tinted band with a bar along the foot.
- **Scrolling** is the session's: `viewWidth` (published by the dock's layout), `visibleSpan`, `scrollEnd` and `maxScroll` bound it, and every gesture — wheel, trackpad, middle-drag, the bar's thumb — goes through `scrollTo` / `scrollBy` / `scrollByPixels`, so none of them can leave the timeline behind. `revealTime` is what keeps the playhead on screen.
- **Views**: `TimelineDock` (focus, keys — in an `EditorKeyClaim` — and menus), `TimelineHeader`, `TimelineItemBar`, `TrackTree`, `TimelineRuler` + `DopeSheet` (one `Listener` for the whole sheet, so a box crosses rows), `CurveView`, `FieldKeyButton` (the inspector's diamond), `TimelineScrollBar` and `MotionPathOverlay` (a built-in designer overlay). A new engine track kind shows up as rows of `UnknownTrack` until it subclasses `BlockTrack`, which the sheet and the item bar already edit. The Add track menu lists what the engine offers (`TimelineTrackOffer`), a package's kinds included.

## The Level Map

The runtime is the engine's (`subsystems/level_map/`: data, geometry for all four orientations, collision, drawing, the built-in tilesets, Tiled interop); the editor paints it, inside the Level Designer, with no mode of its own. A scene has one map, the entity named `LevelMaps.primaryName` ("Level Map"; its `LevelMapComponent` shows as *Map*). Its layers hold tiles. Everything else in the level is an ordinary entity: what the designer places is a child of the map that names one of its layers with `LayerComponent.mapLayer` (the layer's id). The engine's `LevelMapSystem` draws such a member at its layer's depth, just above the layer's tiles and below the next layer's, and hides it while the layer is hidden; `LevelMaps.ownerOf` and `memberLayer` find a member's map and layer. The editor's half is `core/level_map/`, the hierarchy commands in `core/entity/`, and the designer's panels, tools and overlays.

- **Documents, not objects.** `LevelMapDocuments` (`level_map_documents.dart`, `scope.mapDocs`) resolves an entity to its map — the component's `inline` data, or a `.map.json` (an old `.tilemap.json` is still read) loaded once into `TileAssets` and edited in place — as a `LevelMapTarget`. Editor code never keeps a `LevelMapComponent` or `LevelMapData`: Stop and a state undo replace them, so everything looks the map up by entity id or path (`LevelMapRef`) each time, and a layer by its id. Map files are written by `saveDirty()` on Ctrl+S with the scene, and the scene's unsaved mark covers them.
- **Made on demand.** `LevelMapProvision` (`level_map_provision.dart`, `scope.mapProvision`). `ensure` puts an empty map in the scene (one collidable `Ground` layer, cells the grid's size) for the gesture that needs one — the first tile, the first thing placed, a dropped tileset, a built-in tile picked — and `commit` / `keep` records its making *and* what was drawn as one step, or `cancel`s it when the gesture drew nothing. `keepWith(label, edit)` does the same for an edit to the scene's tree rather than the map's data (entities placed under it): a redo makes the map first, an undo takes the edit back first, so one Ctrl+Z removes the map, its new layer and what was placed. *Create Level Map* is `ensure` + `keep`. A dropped `.map.json` and a Tiled *Import into this scene* make the map, take the place of an empty one (`LevelMapProvision.isBlank`), or are refused; `BuiltInValidators.levelMaps` warns of a second map.
- **Placement.** `MapPlacement` (`ui/level_designer/state/map_placement.dart`) is where Draw, Paint, a point prefab and a dropped image or atlas put things while designing. `place(scope, world, [(name, components)], depth:, label:, say:, select:)` makes an entity of each, `parentName` the map, on its layer at `depth`: the layer being painted if it draws there, else the frontmost there, else a new layer named after the depth (a `MapStructureCommand`). The whole is one `CompositeCommand`, or goes through `keepWith` when the map is new too. A locked or hidden layer, a Tiled map or an unnamed map refuses through `say`. `normalize` drops the components' own parent links and adds or fills the `LayerComponent` (`mapLayer`, depth, sort layer, z order). `describe` is what the `PlacementChip` shows. `PrefabDefinition.depth` fixes a prefab's depth whatever depth is active. With the designer shut, a dropped image is a top-level entity.
- **The hierarchy.** `EntitySpec` carries `parentName` and `siblingIndex` (`EntitySpec.of(e, codec, world:)` captures them); `CreateEntitiesCommand` puts each entity back under its parent by name and detaches it on undo, and `EntitySpec.applyTo` never replaces a `ParentComponent` or `ChildrenComponent`, so redo and a state undo keep the tree. Duplicate, array and Alt+drag copies go beside the original, under the same parent. `ReparentCommand(..., mapLayer:)` / `EntityOps.reparentAll(..., mapLayer:)`: moved into a map with a layer id, entities go on that layer (given a `LayerComponent` if they have none); moved anywhere else they leave it, and undo restores each one's old layer. `carriedWith(moving, world:)` (`just_editor_core/lib/src/model/hierarchy_commands.dart`) is everything under the moving entities that is not moving itself. A transform is a world position, so a parent moved alone would leave its children behind: the Select tool's move and rotate (not its resize), `SelectionOps.nudge`, `rotateQuarter` and `moveTo`, and the align bar take it along; `setRotation` does not.
- **Undo** is the editor-wide `scope.history`. A stroke writes cells as it goes (`TileStroke`) and ends as one `TileEditCommand` (before/after per cell, never merged). Layer and map settings are `MapStructureCommand`s (`tile_commands.dart`), which keep layer objects across undo and fold a dragged value by `mergeKey`. Placing on a new layer, duplicating or deleting a layer with what is on it, and cutting tiles into an entity are each one `CompositeCommand` of a map change and an entity command. A map the provision made is recorded with `CreateEntitiesCommand.adopting` as it stands at the end, so one Ctrl+Z takes the map and the first stroke together and a redo brings both back. A redone entity has a new id, so `LevelMapDocuments.dataFor` takes a ref whose entity is gone to mean the scene's Level Map (`LevelMaps.primaryEntity`) — there is one — and the steps recorded against the old id still apply.
- **Shared state** is `TileEditState` (`tile_edit_state.dart`, `scope.tiles`), made eagerly with the scope so it follows the selection (a selected map becomes the one painted, never a piece cut from one — `LevelMaps.isPiece`): the map and layer being painted, the brush (`TileStamp`, in the map's stable coordinates so a block keeps its shape on staggered and hexagonal maps), the terrain, the tool modes, the selection and what the tools are showing. Tools are rebuilt on every reload, so none of this lives in them. Widgets read it through `peek` / `peekLayer`, which choose nothing while they build.
- **Tools.** The strip (`ToolPalette`, `panels/tool_palette.dart`, 56 px) puts each tool under the caption of its `LevelToolHandler.group`: `ToolGroups.builtIn` (SELECT, SHAPES, TILES, MEASURE), then any `ToolGroup` a module adds through `EditorModule.toolGroups`. The tile tools (`tools/tiles/`) are TILES: Stamp (S), Fill (G: bucket, rectangle, ellipse), Terrain (T), Erase (D), Select tiles (V: box, wand, same tile; move, copy, cut; the Move gizmo's arrows and the Rotate ring, which turns the block a quarter at a time through `TileTurn`). `TileTool` gives them all the right-drag pick-up, hover preview, X / Y / Z to mirror and turn the brush, and `aim(create: true)`, which asks the provision for a map on a first stroke. They rely on the tool API's hover, right button, `onKey` (asked before the designer's commands) and activation. The terrain tool uses the engine's `WangFiller` and refuses hexagonal maps. The Select tool carries children (above); its marquee never takes the Level Map itself (a piece it does), and a double-click on empty ground selects it. Paint's eraser deletes what it covers but never a map. A right press goes to a tool that `acceptsSecondaryButton` only without Shift (`LevelDesignerSession.claimsSecondary`), so Shift+right-click always opens the viewport menu. The built-in tools are 2-D only.
- **Tiles into an entity.** `TilesToEntity.cut` (`tiles_to_entity.dart`). What can be done with a tile selection — make an entity, copy, cut, delete, deselect — is `TileSelectionOps` (`tile_selection_ops.dart`), called by Select tiles' keys and *Make entity* option, by the tile selection's right-click menu (`showTileSelectionMenu`, `ui/overlay/viewport_menu.dart`; Select tiles gives up the right button while it has a selection), and by the inspector's card for the selected tiles (`EntityInspectorPanel`). `TilesToEntity.cut` clears the tiles from their layer with a `TileStroke` and makes a child of the map, `Tiles_N`, holding an inline `LevelMapData` with the same grid and tileset list and one copy of the layer, on the source layer (`mapLayer`). Its origin is placed so every tile stays put; on a staggered or hexagonal map the piece starts on an even row (or column) to keep the stagger's parity. One `CompositeCommand`. It refuses a locked layer, a layer with parallax, a Tiled map and an unnamed map. `BuiltInValidators.levelMaps` does not count a piece as a second map. Moving a piece at runtime is not supported yet.
- **The tool's options.** A tool's settings are its `buildOptions(context, ToolOptionsContext)`, shown by `ToolOptionsBar` (`panels/tool_options_bar.dart`), an inline widget at the left of `DesignerStatusBar`, before snapping and the overlay switches. There is no options bar above the viewport, so it keeps the whole height; a tool with none shows its description. The controls they are built from — `SignalToggle`, `ChoicePicker`, `BrushSizePicker`, `ActivePrefabChip`, `PlacementChip` (where Draw and Paint put things, from `MapPlacement.describe`), `MapLayerPicker` — are in `controls/designer_controls.dart`. `designer_status_bar.dart` keeps snap, grid, overlay toggles, module controls, the cell under the pointer while a tile tool is in hand, and the status message.
- **Overlays**: `TileGridOverlay` (the map's own grid while a tile tool is in hand; the collision view, coloured by kind) and `TileBrushOverlay` (ghost tiles, erase preview, drag area, selection outline, tiles being moved), in `overlays/tile_overlays.dart`. Fading the other layers is `TileEditState.syncHighlight`, called by the plugin each frame, not by an overlay, so it is off in Play.
- **Panels.** The side panel's sections collapse and follow the tool group (`LevelDesignerController.sectionsOpen`): PREFABS for the select and shape tools, TILESET for the tile tools, and LAYERS for all of them. TILESET (`TilesetPalettePanel`, `panels/tileset_palette_panel.dart`) is one scrolling list with a section per tileset, no tabs: the engine's built-in tilesets (`BuiltInTilesets.all`, today *Basic shapes*) first, whether or not the map has them — marked "built in · not on the map" until it does — then the map's own. Each section has a header (a chevron that folds it, kept in `TileEditState.collapsedTilesets`; its name; a ⋮ menu with *Edit tileset…* and *Remove from the map*) and its tiles or terrains below at full height. Tiles / Terrains and **+** sit at the top, the zoom at the bottom. Picking a tile of a built-in the map lacks adds it to the map, and makes the Level Map in a scene with none, in one undo step. LAYERS (`LevelLayersPanel`, `panels/level_layers_panel.dart`) is one list grouped by depth, front first: under each depth the map's layers (eye, lock and collision saved with the map; how many entities are on it; a button that moves the selection onto it; an expander for the layer's look) and a row for the entities at that depth on no map layer (editor-only eye and lock, and moving the selection there, one undo step, via `SelectionOps.moveToLayer`, skipping map members). Duplicating a layer copies what is on it and deleting it deletes what is on it, each one step. Its `createLevelMap` backs *Create Level Map*. Designer lists, the strip and the scene tree scroll inside `EditorScrollbar` (`just_editor_core/lib/src/look/widgets/`), whose bar always shows.
- **The tree.** `SceneTreeModel.build` (given `mapOf` and `expandedLayers`) opens the Level Map to `MapLayerTreeItem` rows, front first and shut until opened, each over the entities on that layer, which are ordinary entity rows; the map's children on no layer follow the layer rows. `MapItemRow` (`ui/scene_tree/map_item_row.dart`) draws a layer row: a click paints it, a double-click renames it, eye and lock are map edits (undoable), the detail says "N entities", the menu renames or deletes the layer with what is on it, and it is a drop target that calls `EntityOps.reparentAll(..., mapLayer:)`. Dropping beside a member puts the dragged entities on its layer. `SceneTreeController` opens a selected member's layer. Search matches entities and layer names. Double-clicking the map is `JustGameEditorPlugin.designLevelMap`. A member is hidden and locked in the viewport by its map layer's eye and lock (`LevelDesignerController.mapLayerOf`), not by its depth's.
- **Tileset Editor** (`ui/tileset/`, `BuiltInWorkspaces.tileset`): a `.tileset.json` — or a new one cut from an image — in a dialog workspace with its own undo (`TilesetSession`, JSON snapshots): collision (kinds, presets, a shape canvas), animation, properties (`PropertyTableEditor`, `ui/inspector/`), and terrain sets (a Terrain mode that paints corners and edges, templates, coverage). Saving calls `reloadAssets`, and every map drawing the tileset reads it again. A built-in tileset is drawn in code and is not opened here.
- **Tiled.** `TiledImporter(files, {tilesetFolder})` / `TiledExporter` (`core/level_map/` `tiled_import.dart`, `tiled_export.dart`) over a `TiledFiles` seam: a `.tmx` / `.tmj` into the scene (one undo step) or as a `.map.json`; `.tsx` / `.tsj` to `.tileset.json`; any map out to `.tmx` / `.tmj` with its tilesets beside it (a built-in's picture written as `<name>.png` beside its `.tsx`). Export writes tiles only: the entities on the map are not written as objects. On import each object group becomes an empty map layer, and `TiledImporter.entities` makes every object an entity on it (`parentName` the map, a `LayerComponent.mapLayer`): the first mapper (`EditorModule.tiledObjectMappers`) that takes it, else the prefab its class names — by id, name or one of its `aliases` — else a plain entity where it was. A map converted to a `.map.json` keeps its layers, not its objects. The Assets dock knows the kinds, offers the conversions, and drops tilesets and maps onto the viewport.
- **Play.** Map collision is off while authoring and built at Play; the generated body entities are excluded from saving, the tree, picking and play snapshots. The tile animation clock runs on wall time while authoring.
- **Checks.** `BuiltInValidators.levelMaps` (a second map — a piece is not one — missing tilesets, tiles past a tileset's end, unknown kinds, a turned map, incomplete terrains, an entity that names a map layer but is not under a map, and one on a layer its map no longer has) and `unshippedTileAssets` (files the pubspec does not ship). Built-in and virtual tileset paths (`TileAssets.isVirtual`) are never looked for as files.
