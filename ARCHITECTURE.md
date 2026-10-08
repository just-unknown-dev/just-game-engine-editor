# Just Game Engine Editor - Architecture

```
just_game_engine_editor/
└── lib/src/
    ├── core/
    │   ├── plugin/          ← JustGameEditorPlugin (main orchestrator)
    │   ├── state/           ← EditorSceneState (scene graph ↔ ECS bridge)
    │   ├── scope/           ← EditorScope (per-editor just_di container) + EditorScopeProvider
    │   ├── entity/          ← EntityOps, hierarchy commands (ReparentCommand, carriedWith, …)
    │   ├── level_map/       ← the Level Map: documents, provision, tile commands, TilesToEntity, Tiled import/export
    │   ├── serialization/   ← SceneCodec, SceneStore, SceneManager, EcsLevelMapper, EditorSerializationService, SceneNameValidator
    │   ├── services/        ← EditorLogService
    │   ├── prefs/, theme/   ← EditorPrefs + SettingPref, EditorThemeData + ThemeController
    │   └── ecs/
    │       ├── systems/     ← editor-specific ECS systems
    │       └── registry/    ← ComponentEntry catalogue for the "Add Component" picker
    ├── ui/
    │   ├── overlay/         ← JustGameEditorOverlay split into chrome/, docks/, settings/, right_panel/, shared/
    │   ├── inspector/       ← DefinitionSection, FieldEditorRegistry, ComponentExtrasRegistry, PropertyTableEditor
    │   ├── panels/          ← EntityInspectorPanel, ScenePickerPanel + SceneRow
    │   ├── scene_tree/      ← SceneTreePanel, SceneTreeModel, MapItemRow (a Level Map's layer rows)
    │   ├── level_designer/  ← the Level Designer: tools/, panels/, controls/, overlays/, state/
    │   ├── dialogs/         ← AddComponentPicker, CreateSceneOverlay
    │   ├── widgets/         ← ScrubbableNumberField and shared widgets
    │   └── theme/           ← EditorTheme (colour palette)
    ├── integration/         ← JustGameEngineEditor (drop-in GameWidget replacement)
    └── debugger/            ← EngineDebugger bridge
```

## Core Layer

### `JustGameEditorPlugin`
The central orchestrator (`lib/src/core/plugin/editor_plugin.dart`). Implements `EnginePlugin` and wires together all editor subsystems.

**Lifecycle:**
- `register(engine)` — debug-gated factory; returns `null` in profile and release builds
- `onInitialize()` — registers ECS systems, attaches debugger, loads component registry
- `onUpdate(dt)` — ticks editor state each frame
- `onRender(canvas)` — draws gizmos and grid overlay
- `reassemble()` — called by the overlay's `State.reassemble` on a hot reload: the app's `onReassemble`, the component definitions (`EngineContext.refreshDefinitions`), the scope's registries (`EditorScope.reassemble`), the designer's tools, the built-in docks, and live components a changed definition no longer fits (see the README's *Hot reload and hot restart*)

**Entity operations:** `createEntity`, `deleteEntity`, `createGroup`, `reparentEntity`, `copyEntity`, `pasteEntity`

**Scene operations:** `openScene(name)`, `saveScene()`

**Gizmo interaction:** `onPointerDown`, `onPointerMove`, `onPointerUp` — handles translate/rotate/scale handle hit-testing and dragging

### `EditorSceneState`
Keeps the authoring scene graph in sync with the live ECS world (`lib/src/core/state/editor_scene_state.dart`). Every piece of it is a `Signal` — `activeScene`, `selectedEntity`, `multiSelectedIds`, `isDirty`, `gridSize`, `clipboard` — plus `revision`, bumped by any edit no other signal captures (a transform drag, a rename, a component added). A panel watches only what it reads.

### Level designer switch
Module designers are opt-in per scene. `EditorScope.designers` lists every module with `providesLevelDesigner`; `activeDesigner` (a signal, null for the built-in designer) and `selectDesigner()` choose one, and `_rebuildDesigner()` recomputes prefabs, layers, grid, palette categories, status controls and side-panel sections from the built-ins plus that module. `LevelDesignerSession` watches the signal and reloads its tools, overlays, snap providers and module state; the palette, tool strip, layers panel, status bar and side panel rebuild through it. `DesignerSwitch` (`panels/designer_switch.dart`) is the header control, shown only when there is something to switch to. The session writes the choice as `editor.designer` and restores it before the module data.

### Cameras
The engine's virtual cameras are ordinary entities with ordinary definitions, so the inspector, picker, prefabs and save format need nothing camera-specific. What the editor adds: `EditorScope.cameraBrain`; the hand-over in `JustGameEditorPlugin._syncCameraOwnership` (authoring: `brain.driveOutput = false`, the output camera *is* the editor view; Play: the brain drives it and the view is restored on Stop) plus a `snap` evaluation on the unscaled tick; `CameraRigPainter` / `CameraRigOverlay` (`lib/src/ui/overlay/camera_rig_painter.dart`) for frames, framing zones, triggers, bounds and tracks; the game preview in `onRender`, which re-renders the world with the output camera briefly showing `brain.liveState`; and `BuiltInCameraContributions` (`lib/src/extension/`), which adds Solo and the LIVE badge through the same scene-tree and inspector seams a module uses. Every system that draws captures the one output camera object, which is why ownership is a flag on the brain rather than a second camera.

### State management
All editor state is `just_signals`: `Signal` fields on the services (`PlayController.state`, `DockController.openId`, `ThemeController.current`, `EditorLogService.entries`, `EditorPrefs.settings`, `EditorChromeState`, `EditorSnackBarController`) and on the plugin (`isVisible`, `isStatusPanelVisible`, `designer`, `gridSize`, `showGrid`), with `Computed` for what derives from them (`isAuthoring`, `isGridVisible`). Widgets read `.value` and rebuild through `SignalBuilder` (one signal), `SignalBuilder2` or `SignalConsumer` (several); `batch()` groups the writes of one operation into one notification. Nothing in the editor extends `ChangeNotifier`; the only listenables left are Flutter's own controllers and the debugger's `JustDebuggerController`.

- **Selection:** `selectEntity`, `toggleMultiSelect`, `selectRange`, `clearSelection`
- **Transform sync:** `applyTranslation`, `applyRotation`, `applyScale` → mutate ECS, then `syncEntityNode` pulls state back into the scene graph
- **Dirty tracking:** `markDirty` / `markClean` — drives the unsaved-changes indicator
- **Grid snapping:** configurable grid size with automatic position/scale quantization

### `EditorScope`
Everything one editor owns — component definitions, the `SceneCodec` and `SceneStore`, the field-editor, extras, prefab, layer, command and module registries, the log and the `EditorSceneState` — in a `just_di` container (`lib/src/core/scope/editor_scope.dart`). There are no process-wide registries: two scopes share nothing, and `reload()` rebuilds every registry from the built-ins and the registered `EditorModule`s, so nothing accumulates across hot reloads; a module's `onRegister` runs on its first pass only, and `reassemble()` (a hot reload) runs each module's `onReassemble` and remakes the theme presets before rebuilding. `EditorScopeProvider` makes it available to a widget subtree.

### The Level Designer's contribution points
An `EditorModule` (`lib/src/extension/editor_module.dart`) declares what it adds and the scope folds it in on every `reload()`: prefabs and `prefabCategories` (what a prefab builds is placed under the Level Map, and `PrefabDefinition.depth` fixes the depth it goes to — see below), per-session `createTools` and the `toolGroups` they stand under, `overlays` (an `InteractiveOverlay` also takes pointer input, offered topmost-first before any tool — the rulers and minimap are two), `createSnapProviders` (resolved by priority against the entity and grid providers), `createSessionState` (reached from a tool through `ToolContext.stateOf<T>()`, kept across reloads), `saveEditorData`/`restoreEditorData` (namespaced by module id in the scene file's `editor` section), `commands` and `keyBindings` (a `CommandRegistry` per scope; the session and the plugin dispatch keys through it, and a module's chord beats a built-in's), `statusControls` and `designerPanels`. `prefabs` count only while their module is the Level Designer (`providesLevelDesigner`, picked with the designer switch); `sharedPrefabs` are offered by every Level Designer, whichever module is designing, and do not make their module a designer — the Interface module's Text is one. `DesignerConfig` and `SelectionHandleLayout` are scope services for what used to be literals. The designer's cells are a `GridTopology` (`lib/src/ui/level_designer/grid/`): `SquareGrid` by default, `HexGrid` when a module's `gridTopology` says so (`HexGridModule` ships in the package); tools reach it as `context.grid`.

### The overlay's seams (semi-modular)
`lib/src/ui/overlay/` is one library per concern: `editor_overlay.dart` (the root, which provides `EditorScopeProvider` and `EditorThemeScope` to everything under it, portal children included), `chrome/` (compact and full chrome), `docks/` (the compact dock, one file per built-in dock, `DockController`), `settings/` (`OverlayUiSettings`, the store, the dialog), `right_panel/`, `shared/` (play toolbar, snackbar), `chrome_state.dart`. Modules append to the built-ins through the `EditorModule` members `docks`, `toolbarButtons`, `sceneTreeActions`, `rowDecorations`, `protectionRule`, `inspectorSections`, `settingsSections` and `themePresets`; the built-in docks, the right panel's order and the settings tabs are not replaceable from outside — that is the deliberate cut. Preferences are `EditorPrefs` (`core/prefs/`), the palette is `ThemeController` + `EditorThemeData` (`core/theme/`).

### Module seams
What a module that owns its own files and documents hears from the editor, all on `EditorModule`:

- `onAssetChanged(path)` — called from the plugin's asset reload when a file in the project changed (saved by a tool, dropped in from outside). Whatever the module shows from it should show the new one.
- `onPlayStateChanged(playing)` — a play-test started or stopped. The Interface module switches the game's screens' layer (`engine.layers`) on for a play-test and off again after.
- `dataFileSuffixes` — endings of the JSON files the module owns (`.ui.json`). `EditorScope.reload` collects them into `ModuleDataFiles`, which the checks read, so a module's JSON is never taken for a sprite atlas (what the editor assumes of any `.json` it does not recognise).
- `inheritedColors` — what an unset colour field falls back to for the module's components. They land in `FieldEditorRegistry.inheritedColors`; `inheritedColor(component, field)` asks each in turn, so the inspector can show the colour and where it comes from rather than a blank.
- `sharedPrefabs` — see the Level Designer's contribution points above.

A workspace that edits a document of its own — with its own world and its own undo — builds its inspector with `buildComponentSections(history:, world:)` and adds components with `AddComponentPicker(history:)`; left out, both are the level's. `EditorHistory.dirty` (a `Signal`, clean again when undone back to the save), `markSaved()` and `breakMerge()` let such a document show whether it is saved.

The in-game interface is such a module: `UiEditorModule`, in the `just_ui_editor` package. The editor has no interface editor, Theme dock, UI mode or interface tree of its own.

### `JustGameEditorPlugin` and its services
The plugin (`lib/src/core/plugin/editor_plugin.dart`) is an `EnginePlugin`: `JustGameEngineEditor` registers it with `engine.plugins`, which ticks it once per frame, and adds its gizmo pass to `RenderingEngine.overlayHooks`. It owns visibility, keyboard dispatch, the grid and the Level Designer session, and delegates everything else to services that take only what they need: `PlayController` (`core/play/`), `SceneIO` (`core/scene/`), `EntityOps` (`core/entity/`) and `ViewportInput` (`core/input/`). Panels take the service they need — `plugin.playController`, `plugin.entities`, `plugin.viewport` — rather than the plugin.

### The inspector: definitions, field editors, extras

Every row is a label of `InspectorField.labelWidth` and then its control, and every control is the same box — `InspectorField` (`ui/inspector/field_style.dart`) holds the fill, border, corner, padding, type size and height, and hands out the `InputDecoration` for text fields and a `BoxDecoration` for what is not one. A new kind of field takes its look from there; `inspector_look_test.dart` measures a real panel and fails if the boxes stop agreeing. A component's inspector section is built from its runtime `ComponentDefinition` (`lib/src/ui/inspector/definition_section.dart`): the fields from the schema, the name, icon, labels, groups and scrub feel from its `ComponentHints`. There is no second, design-time description. `FieldEditorRegistry` (`field_editor.dart`) maps each `FieldType` id to a control — the built-ins in `built_in_field_editors.dart` (including the compound physics-shape editor), a module's `fieldEditors` over them. `ComponentExtrasRegistry` (`component_extras.dart`) holds what the editor adds beyond fields: header actions, a custom section, a replacement editor for one field. There is no design-time descriptor model any more. A component a scene names but no registered definition reads is kept, not dropped — see *Unknown components* below — and shows as a card of its own (`UnknownComponentsCard`).

### Component picker registry
`getComponentRegistryEntries(scope)` (`lib/src/core/ecs/registry/component_registry.dart`) adapts every definition the scope knows into a lightweight `ComponentEntry` (name, group, description, factory, `allowMultiple`), grouped by `ComponentHints.group`. This is the catalogue `AddComponentPicker` renders — it owns no state; it is a view over `scope.definitions`.

### `EditorSerializationService`
Runs serialization in a `compute()` isolate so large scenes don't jank the main thread. File I/O is the scope's `SceneStore`.

### Scene format
Files are scene format v1: `{version, name, root, entities, editor}`, every component as `{type, fields}` encoded by its `ComponentDefinition`. `SceneIO.open` migrates an older file in memory through the engine's `SceneFormat.migrate` and logs "migrated ... Save to persist"; the file itself changes only when the author saves, and `SceneStore` stamps `version` on every write. The shipped game reads the same files through `SceneLoader`, which migrates the same way.

### Unknown components
A scene can name a component no registered definition can read — a module not registered this session, or one that moved to another package (the interface components did, to `just_ui_editor`). `SceneCodec.decodeAll` collects every such entry on an entity into one `UnknownComponents` (`core/serialization/unknown_components.dart`), exactly as the file had it, and `encodeAll` writes them back unchanged. `BuiltInValidators.unknownComponents` lists each entity that holds one as an error in Problems — the game will not load the scene until the module is registered — and the inspector shows a card for it. Before, such components vanished on load and the next save deleted them. `SceneCodec.inTreeOrder` (parents first, the order a file wants) and `encodeInOrder` are public for callers that need records paired with entities, such as the play-test snapshot.

### The play-test snapshot
`PlaySnapshot` (`core/state/play_snapshot.dart`) captures the authored scene when play starts and puts it back when it stops. It takes the entities in tree order and encodes them in that same order, so record *i* belongs to entity *i*; each record also keeps its parent as an index into the records, not an id. Restoring applies each record to its own entity in place (ids, selection, undo and bound physics bodies stay valid), recreates only what play destroyed and removes only what play made, then rebuilds every parent and child link from the records' indices. Before, the entities were taken in world order and the records in file order; once an entity made later sat earlier in the file, every record after it went to a neighbour and parents were re-linked wrongly.

## UI Layer

### `JustGameEditorOverlay`
Top-level Flutter widget that wraps the game canvas (`lib/src/ui/overlay/editor_overlay.dart`). It provides the `EditorScope`, the theme (`EditorThemeScope`) and the messenger to everything below, and is split into libraries by responsibility:

| Library | Responsibility |
|---------|----------------|
| `chrome/editor_chrome.dart` | The full chrome: toolbar, viewport, right panel, status bar |
| `docks/compact_dock.dart` + one file per dock | Minimised dock strip; `DockController` opens one dock at a time, built-ins first, then module `DockDefinition`s |
| `settings/settings_dialog.dart`, `settings_catalog.dart`, `shortcut_row.dart`, `overlay_settings_store.dart` | The settings dialog — a page per subject, search over all of them, in the sprite editor's frame (`EditorDialogFrame`) — opened by the gear at the viewport's foot or Ctrl+,; each module `SettingsSection` gets a page under MODULES. The catalog lists every built-in setting; the store's `encode`/`decode` is the one table a save, a load, an export and an import all use |
| `right_panel/right_panel.dart` | Right sidebar host (scene picker, or scene tree and inspector); while the Level Designer is open, Inspector \| Level tabs (`EditorChromeState.rightPanelTab`) |
| `start/start_card.dart` | `EditorStartCover` + `EditorStartCard`: what `GameCanvasArea` shows over the game while no scene is open (steps, live keys, module tools and `GettingStartedTip`s) |
| `shared/shared_widgets.dart`, `shared/snackbar.dart` | Play toolbar (transport, view and mode, then module `ToolbarButton`s), stacked messages |
| `chrome_state.dart` | `EditorChromeState`: transient widths and open dialogs, a scope service |

Modules *append* to the built-in set — docks, toolbar buttons, settings sections, scene-tree actions and row decorations, inspector sections, theme presets. The built-in docks, the right panel's order and the play toolbar's own buttons are private and cannot be replaced or reordered from outside; that is the deliberate cut.

### Theme, sizes and the kit
`EditorThemeData` (`lib/src/core/theme/editor_theme_data.dart`) holds the palette — accent, surfaces, borders, text, and error, warning, success and info; `ThemeController` (a scope service) holds the current one and the presets — five built-in accents, plus any a module contributes. The overlay root keeps it in step with the settings and applies it to `EditorTheme`, whose getters every widget reads (`EditorTheme.accent`, `EditorTheme.surfaceBg`…), and builds the chrome again when it changes; `EditorTheme.of(context)` reads the same palette through the tree. `EditorMetrics` (`core/theme/editor_metrics.dart`) is the same for sizes: radii from the corner radius, gaps from the density, durations from the animation speed. Text needs neither: `EditorLook` (kit) scales it with a `TextScaler`, so a font size is written as it reads at 100%. The accessibility settings sit over all three: high contrast and the colour-blind safe colours are variants of the palette the overlay applies (`highContrast()`, `colourBlindSafe()`); bigger targets, no motion and longer timings are `EditorMetrics`; bold text, reduced motion and tooltip timing are `EditorLook`'s, which the chrome, and every dialog and menu the editor opens, sit under.

Who follows which setting: the scope, from the first time its prefs are read, keeps its services in step — `EditorHistory.capacity`, `EditorLogService.maxEntries`, the scene state's snap steps, and the changed keys laid over the command registry (`applyShortcuts`, again after every `reload()`). The plugin keeps the painting and the play-test in step — `ViewportLook` (grid colour and strength, handle size, selection colour, read by the painters), the backdrop while authoring, pause on error, autosave on its update tick, and where the session was left. The overlay supplies the questions only a window can ask (`plugin.askToRecover`, `EntityOps.confirmDelete`), reopens the last session once the settings load, and steps aside for the game while a play-test runs if asked.

Build UI from the kit (`lib/src/ui/kit/`, exported): `EditorIconButton`, `EditorToolButton`, `EditorButton`, `EditorSearchField`, `CommitTextField`, `EditorToggle`, `EditorSegmented`, `EditorSlider`, `EditorChip`, `EditorBadge`, `EditorToolbar`, `EditorSectionHeader`, `EditorCard`, `EditorEmptyState`, `EditorAlert`, `showEditorConfirm`, `askToSaveChanges`, `EditorDialogFrame`, and a workspace's frame (`WorkspaceHeader`, `WorkspaceFullScreenButton`, `WorkspaceKeyScope`, `mayLeaveUnsaved`; see *Workspaces*) — and `editorMenuItem(shortcut:)` for menus. They take their colours and sizes from the above, so they follow the settings; every target is at least 24 px. The sprite editor's and input editor's own palettes (`StudioPalette`, `InputEditorPalette`) are handed the editor's by the modules that open them.

### `GizmoPainter`
Draws the selected entity's gizmo on the canvas (`lib/src/ui/overlay/gizmo_painter.dart`): one of Move, Scale or Rotate, as `scope.view.transformMode` and the floating `TransformToolbar` say, through `TransformGizmo` (`lib/src/ui/overlay/transform_gizmo.dart`), which the Level Designer's select tools draw and hit-test with too. `GizmoHitTester.hitTest(mode:)` answers only that mode's handles.

### `ScrubbableNumberField`
Number input that supports mouse-drag scrubbing in addition to keyboard entry (`lib/src/ui/widgets/scrubbable_number_field.dart`). Driven by a `NumberScrubConfig` (declared beside it, derived from a field's `ScrubHint`) and used throughout the inspector for numeric component fields.

## Integration Layer

### `JustGameEngineEditor`
Drop-in replacement for `GameWidget` during development (`lib/src/integration/just_game_editor_adapter.dart`). Registers the plugin with `engine.plugins`, which ticks it and draws its overlay, and lays `JustGameEditorOverlay` over the game. With no plugin — a profile or release build, where `register` returns null — it is a plain `GameWidget`.

## ECS Systems (editor-only)

| System | Purpose |
|--------|---------|
| `PhysicsBodyBindingSystem` | Syncs physics body state while editor is open |
| `PhysicsJointBindingSystem` | Syncs physics joint state |
| `SimpleMovementSystem` | WASD/controller movement for `SimpleMovementComponent` |
| `EditorLogCaptureSystem` | Captures ECS system logs into `EditorLogService` |
| `EditorSpriteSystem` | Sprite rendering inside the editor viewport |
| `EditorAnimatedSpriteSystem` | Animated sprite support in the editor |
| `EditorAnimationControllerSystem` | Animation controller state handling |

These systems are only registered when the editor plugin is active and are never present in production builds.

## Workspaces

A module can open a large tool of its own over the editor, as a dialog with the level dimmed behind it (`WorkspaceHost`; `presentation: fullScreen` to fill instead) — `WorkspaceDefinition` in `EditorModule.workspaces`, opened with `EditorScope.openWorkspace(id, {path})` or, for a file, `openInWorkspace(path)` (the longest matching file ending wins). `activeWorkspace` is the one that is open; the chrome mounts it over everything, and while it is there `_onHardwareKey` hands the level's commands nothing, so the workspace's own `Focus` owns Ctrl+S and the letter keys. It is built with a `WorkspaceContext` whose `reloadAssets(path)` is how a tool tells the running level a file changed (`JustGameEditorPlugin .reloadAsset` → the engine's sprite and animator systems). `AssetAction` (`EditorModule.assetActions`) puts buttons on Assets-dock rows. The Sprite Studio (`packages/just_sprite_editor`) is the first user of both.

The editor brings one workspace of its own, the Tileset Editor (`BuiltInWorkspaces`, `ui/tileset/built_in_workspaces.dart`). The interface editor is `UiEditorModule`'s, from `just_ui_editor`.

**Close guards.** A workspace with unsaved work registers what to ask before it goes through `WorkspaceContext.setCloseGuard` — the chrome passes it on to `EditorScope.setWorkspaceCloseGuard(guard, of: open)`. `openWorkspace` asks the open workspace's guard before opening another over it, and opens only if the guard agrees; `requestCloseWorkspace()` asks it before closing. Clearing a guard (`null`) only clears the asker's own, so a workspace let go after another opened in its place leaves the new one's question in place. A workspace that asks for itself calls `closeWorkspace()` once it has.

**The frame** (`ui/kit/workspace.dart`, in the kit) is what every workspace is built with, so they read as one editor's windows: `WorkspaceHeader` (icon, title, the open file, a dot while it is not saved, Save, Undo and Redo — `showHistory: false` hides the last two — the workspace's tools, full screen and close), `WorkspaceFullScreenButton`, `WorkspaceKeyScope` (keys go to the workspace except while typing in a field; a click on anything that is not a field takes them back; focus is asked for after the first frame, since a route that finishes opening later would otherwise take it) and `mayLeaveUnsaved` (asks Save / Don't save / Cancel and does it; false if the save failed). The Tileset Editor is built with them, and its close guard is `mayLeaveUnsaved`.

Sprites in the viewport are drawn by the engine's own `SpriteLoadSystem`, `SpriteAnimationSystem` and `AnimatorSystem` — the editor only points the edited engine's loaders (`engine.context.overrideLoaders(...)`: sprites, animator graphs, timelines, tile text) at `FileSpriteAssetLoader`, which reads the project's files instead of the build's asset bundle, and restores them when it detaches. Another engine in the process is not affected.

## The dock panel

The foot of the editor is a status strip and, above it, one tabbed panel (`ui/overlay/docks/`). `CompactStatusDock` is the host the chrome mounts — in the Level Designer too, where the order bottom up is the status strip, any open panel, then the designer's status bar standing on them, with the designer inset by `DockController.panelHeight`. `DockPanel` is the tab bar (a right-click on a tab: pop out, maximise, take off the bar; `+` lists every dock not on the bar, popped-out ones included), header and active dock; `DockStatusStrip` is the status bar — a line of facts, each a button to where it came from (errors to the Console on its errors, the frame rate to the Profiler, a module's readout to its dock with `DockReadout.openArgs`), and the rest of the bar opens or shuts the panel (F2); `DockPopouts` floats the docks that were popped out, which reopen where they were left. `DockController` holds what is open, tab order, pins, heights, maximise, pop-outs and each dock's memory, and persists all of it as one JSON preference (`editor.docks`).

Every dock is a `DockDefinition` — the editor's own are in `shell/built_in_docks.dart`, registered exactly as a module's are:

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

Build a dock from the kit (`EditorToolbar`, `EditorSearchField`, `EditorChip`, `EditorIconButton`, `EditorEmptyState`) and `DockTable` from `docks/shared/dock_widgets.dart`, and it looks like the rest. Two rules keep the panel cheap: a readout and a tab badge are polled a few times a second, so they must be cheap to compute (cache, as `ProblemScan` and `AssetIndex` do); and a dock listens to what it needs itself — the panel does not rebuild it on a timer.

A module can also add scene checks to the Problems dock (`EditorModule.validators`).

## The Timeline

`lib/src/ui/timeline/`. The runtime is the engine's (`subsystems/timeline/`); the editor adds a session and views of it.

- **`TimelineSession`** (`TimelineSession.of(scope)`, one per editor) holds the open `TimelineAsset` — a file, or the inline timeline of the selected entity's player — as an immutable value, so undo is a list of assets and a drag is one step (`beginDrag` / `dragItems` / `endDrag`). Things on tracks are addressed as `TimelineItemRef(track, index)`; every edit that re-sorts items returns where they went. An inline edit is written into the player and marks the scene dirty; a file is saved on request and on leaving it.
- **Preview** drives a `TimelinePlayback(isPreview: true)` against the live world. The engine calls `onWillWrite(component, field)` before a track first writes a field; the session keeps the field's saved form and `endPreview()` decodes it back. `EditorScope.authoredStateGuards` / `restoreAuthoredState()` is the general seam: `SceneIO.save` and `PlayController.play` call it before they read the scene, and the plugin switches `TimelineSystem.isActive` off while authoring, so nothing but the session moves a timeline in the editor.
- **Record** compares every animatable field of the watched entities (the owner, and whoever a track is bound to) with what it held when the timeline was last shown; a difference is an edit, keyed at the playhead, and the field's pre-edit value is what `endPreview()` restores. The inspector calls `captureEdits()` on every change and the dock polls it for gizmo drags.
- **Two ranges, deliberately different.** The **work range** is the editor's: a stretch to loop while working, not saved. The **play range** lives on the entity's `TimelinePlayerComponent` (`from` / `to`) and is what the game plays. `applyWorkRangeToPlayer` is the one place the first becomes the second, and the ruler draws them apart — the play range dims what is never played and carries a grip at each end; the work range is a tinted band with a bar along the foot.
- **Scrolling** is the session's: `viewWidth` (published by the dock's layout), `visibleSpan`, `scrollEnd` and `maxScroll` bound it, and every gesture — wheel, trackpad, middle-drag, the bar's thumb — goes through `scrollTo` / `scrollBy` / `scrollByPixels`, so none of them can leave the timeline behind. `revealTime` is what keeps the playhead on screen.
- **Views**: `TimelineDock` (focus, keys, menus), `TimelineHeader`, `TimelineItemBar`, `TrackTree`, `TimelineRuler` + `DopeSheet` (one `Listener` for the whole sheet, so a box crosses rows), `CurveView`, `FieldKeyButton` (the inspector's diamond), `TimelineScrollBar` and `MotionPathOverlay` (a built-in designer overlay). A new engine track kind shows up as rows of `UnknownTrack` until it subclasses `BlockTrack`, which the sheet and the item bar already edit.

## The Level Map

The runtime is the engine's (`subsystems/level_map/`: data, geometry for all four orientations, collision, drawing, the built-in tilesets, Tiled interop); the editor paints it, inside the Level Designer, with no mode of its own. A scene has one map, the entity named `LevelMaps.primaryName` ("Level Map"; its `LevelMapComponent` shows as *Map*). Its layers hold tiles. Everything else in the level is an ordinary entity: what the designer places is a child of the map that names one of its layers with `LayerComponent.mapLayer` (the layer's id). The engine's `LevelMapSystem` draws such a member at its layer's depth, just above the layer's tiles and below the next layer's, and hides it while the layer is hidden; `LevelMaps.ownerOf` and `memberLayer` find a member's map and layer. The editor's half is `core/level_map/`, the hierarchy commands in `core/entity/`, and the designer's panels, tools and overlays.

- **Documents, not objects.** `LevelMapDocuments` (`level_map_documents.dart`, `scope.mapDocs`) resolves an entity to its map — the component's `inline` data, or a `.map.json` (an old `.tilemap.json` is still read) loaded once into `TileAssets` and edited in place — as a `LevelMapTarget`. Editor code never keeps a `LevelMapComponent` or `LevelMapData`: Stop and a state undo replace them, so everything looks the map up by entity id or path (`LevelMapRef`) each time, and a layer by its id. Map files are written by `saveDirty()` on Ctrl+S with the scene, and the scene's unsaved mark covers them.
- **Made on demand.** `LevelMapProvision` (`level_map_provision.dart`, `scope.mapProvision`). `ensure` puts an empty map in the scene (one collidable `Ground` layer, cells the grid's size) for the gesture that needs one — the first tile, the first thing placed, a dropped tileset, a built-in tile picked — and `commit` / `keep` records its making *and* what was drawn as one step, or `cancel`s it when the gesture drew nothing. `keepWith(label, edit)` does the same for an edit to the scene's tree rather than the map's data (entities placed under it): a redo makes the map first, an undo takes the edit back first, so one Ctrl+Z removes the map, its new layer and what was placed. *Create Level Map* is `ensure` + `keep`. A dropped `.map.json` and a Tiled *Import into this scene* make the map, take the place of an empty one (`LevelMapProvision.isBlank`), or are refused; `BuiltInValidators.levelMaps` warns of a second map.
- **Placement.** `MapPlacement` (`ui/level_designer/state/map_placement.dart`) is where Draw, Paint, a point prefab and a dropped image or atlas put things while designing. `place(scope, world, [(name, components)], depth:, label:, say:, select:)` makes an entity of each, `parentName` the map, on its layer at `depth`: the layer being painted if it draws there, else the frontmost there, else a new layer named after the depth (a `MapStructureCommand`). The whole is one `CompositeCommand`, or goes through `keepWith` when the map is new too. A locked or hidden layer, a Tiled map or an unnamed map refuses through `say`. `normalize` drops the components' own parent links and adds or fills the `LayerComponent` (`mapLayer`, depth, sort layer, z order). `describe` is what the `PlacementChip` shows. `PrefabDefinition.depth` fixes a prefab's depth whatever depth is active. With the designer shut, a dropped image is a top-level entity.
- **The hierarchy.** `EntitySpec` carries `parentName` and `siblingIndex` (`EntitySpec.of(e, codec, world:)` captures them); `CreateEntitiesCommand` puts each entity back under its parent by name and detaches it on undo, and `EntitySpec.applyTo` never replaces a `ParentComponent` or `ChildrenComponent`, so redo and a state undo keep the tree. Duplicate, array and Alt+drag copies go beside the original, under the same parent. `ReparentCommand(..., mapLayer:)` / `EntityOps.reparentAll(..., mapLayer:)`: moved into a map with a layer id, entities go on that layer (given a `LayerComponent` if they have none); moved anywhere else they leave it, and undo restores each one's old layer. `carriedWith(moving, world:)` (`core/entity/hierarchy_commands.dart`) is everything under the moving entities that is not moving itself. A transform is a world position, so a parent moved alone would leave its children behind: the Select tool's move and rotate (not its resize), `SelectionOps.nudge`, `rotateQuarter` and `moveTo`, and the align bar take it along; `setRotation` does not.
- **Undo** is the editor-wide `scope.history`. A stroke writes cells as it goes (`TileStroke`) and ends as one `TileEditCommand` (before/after per cell, never merged). Layer and map settings are `MapStructureCommand`s (`tile_commands.dart`), which keep layer objects across undo and fold a dragged value by `mergeKey`. Placing on a new layer, duplicating or deleting a layer with what is on it, and cutting tiles into an entity are each one `CompositeCommand` of a map change and an entity command. A map the provision made is recorded with `CreateEntitiesCommand.adopting` as it stands at the end, so one Ctrl+Z takes the map and the first stroke together and a redo brings both back. A redone entity has a new id, so `LevelMapDocuments.dataFor` takes a ref whose entity is gone to mean the scene's Level Map (`LevelMaps.primaryEntity`) — there is one — and the steps recorded against the old id still apply.
- **Shared state** is `TileEditState` (`tile_edit_state.dart`, `scope.tiles`), made eagerly with the scope so it follows the selection (a selected map becomes the one painted, never a piece cut from one — `LevelMaps.isPiece`): the map and layer being painted, the brush (`TileStamp`, in the map's stable coordinates so a block keeps its shape on staggered and hexagonal maps), the terrain, the tool modes, the selection and what the tools are showing. Tools are rebuilt on every reload, so none of this lives in them. Widgets read it through `peek` / `peekLayer`, which choose nothing while they build.
- **Tools.** The strip (`ToolPalette`, `panels/tool_palette.dart`, 56 px) puts each tool under the caption of its `LevelToolHandler.group`: `ToolGroups.builtIn` (SELECT, SHAPES, TILES, MEASURE), then any `ToolGroup` a module adds through `EditorModule.toolGroups`. The tile tools (`tools/tiles/`) are TILES: Stamp (S), Fill (G: bucket, rectangle, ellipse), Terrain (T), Erase (D), Select tiles (V: box, wand, same tile; move, copy, cut; the Move gizmo's arrows and the Rotate ring, which turns the block a quarter at a time through `TileTurn`). `TileTool` gives them all the right-drag pick-up, hover preview, X / Y / Z to mirror and turn the brush, and `aim(create: true)`, which asks the provision for a map on a first stroke. They rely on the tool API's hover, right button, `onKey` (asked before the designer's commands) and activation. The terrain tool uses the engine's `WangFiller` and refuses hexagonal maps. The Select tool carries children (above); its marquee never takes the Level Map itself (a piece it does), and a double-click on empty ground selects it. Paint's eraser deletes what it covers but never a map. A right press goes to a tool that `acceptsSecondaryButton` only without Shift (`LevelDesignerSession.claimsSecondary`), so Shift+right-click always opens the viewport menu.
- **Tiles into an entity.** `TilesToEntity.cut` (`tiles_to_entity.dart`). What can be done with a tile selection — make an entity, copy, cut, delete, deselect — is `TileSelectionOps` (`tile_selection_ops.dart`), called by Select tiles' keys and *Make entity* option, by the tile selection's right-click menu (`showTileSelectionMenu`, `ui/overlay/viewport_menu.dart`; Select tiles gives up the right button while it has a selection), and by the inspector's card for the selected tiles (`EntityInspectorPanel`). `TilesToEntity.cut` clears the tiles from their layer with a `TileStroke` and makes a child of the map, `Tiles_N`, holding an inline `LevelMapData` with the same grid and tileset list and one copy of the layer, on the source layer (`mapLayer`). Its origin is placed so every tile stays put; on a staggered or hexagonal map the piece starts on an even row (or column) to keep the stagger's parity. One `CompositeCommand`. It refuses a locked layer, a layer with parallax, a Tiled map and an unnamed map. `BuiltInValidators.levelMaps` does not count a piece as a second map. Moving a piece at runtime is not supported yet.
- **The tool's options.** A tool's settings are its `buildOptions(context, ToolOptionsContext)`, shown by `ToolOptionsBar` (`panels/tool_options_bar.dart`), an inline widget at the left of `DesignerStatusBar`, before snapping and the overlay switches. There is no options bar above the viewport, so it keeps the whole height; a tool with none shows its description. The controls they are built from — `SignalToggle`, `ChoicePicker`, `BrushSizePicker`, `ActivePrefabChip`, `PlacementChip` (where Draw and Paint put things, from `MapPlacement.describe`), `MapLayerPicker` — are in `controls/designer_controls.dart`. `designer_status_bar.dart` keeps snap, grid, overlay toggles, module controls, the cell under the pointer while a tile tool is in hand, and the status message.
- **Overlays**: `TileGridOverlay` (the map's own grid while a tile tool is in hand; the collision view, coloured by kind) and `TileBrushOverlay` (ghost tiles, erase preview, drag area, selection outline, tiles being moved), in `overlays/tile_overlays.dart`. Fading the other layers is `TileEditState.syncHighlight`, called by the plugin each frame, not by an overlay, so it is off in Play.
- **Panels.** The side panel's sections collapse and follow the tool group (`LevelDesignerController.sectionsOpen`): PREFABS for the select and shape tools, TILESET for the tile tools, and LAYERS for all of them. TILESET (`TilesetPalettePanel`, `panels/tileset_palette_panel.dart`) is one scrolling list with a section per tileset, no tabs: the engine's built-in tilesets (`BuiltInTilesets.all`, today *Basic shapes*) first, whether or not the map has them — marked "built in · not on the map" until it does — then the map's own. Each section has a header (a chevron that folds it, kept in `TileEditState.collapsedTilesets`; its name; a ⋮ menu with *Edit tileset…* and *Remove from the map*) and its tiles or terrains below at full height. Tiles / Terrains and **+** sit at the top, the zoom at the bottom. Picking a tile of a built-in the map lacks adds it to the map, and makes the Level Map in a scene with none, in one undo step. LAYERS (`LevelLayersPanel`, `panels/level_layers_panel.dart`) is one list grouped by depth, front first: under each depth the map's layers (eye, lock and collision saved with the map; how many entities are on it; a button that moves the selection onto it; an expander for the layer's look) and a row for the entities at that depth on no map layer (editor-only eye and lock, and moving the selection there, one undo step, via `SelectionOps.moveToLayer`, skipping map members). Duplicating a layer copies what is on it and deleting it deletes what is on it, each one step. Its `createLevelMap` backs *Create Level Map*. Designer lists, the strip and the scene tree scroll inside `EditorScrollbar` (`ui/widgets/`), whose bar always shows.
- **The tree.** `SceneTreeModel.build` (given `mapOf` and `expandedLayers`) opens the Level Map to `MapLayerTreeItem` rows, front first and shut until opened, each over the entities on that layer, which are ordinary entity rows; the map's children on no layer follow the layer rows. `MapItemRow` (`ui/scene_tree/map_item_row.dart`) draws a layer row: a click paints it, a double-click renames it, eye and lock are map edits (undoable), the detail says "N entities", the menu renames or deletes the layer with what is on it, and it is a drop target that calls `EntityOps.reparentAll(..., mapLayer:)`. Dropping beside a member puts the dragged entities on its layer. `SceneTreeController` opens a selected member's layer. Search matches entities and layer names. Double-clicking the map is `JustGameEditorPlugin.designLevelMap`. A member is hidden and locked in the viewport by its map layer's eye and lock (`LevelDesignerController.mapLayerOf`), not by its depth's.
- **Tileset Editor** (`ui/tileset/`, `BuiltInWorkspaces.tileset`): a `.tileset.json` — or a new one cut from an image — in a dialog workspace with its own undo (`TilesetSession`, JSON snapshots): collision (kinds, presets, a shape canvas), animation, properties (`PropertyTableEditor`, `ui/inspector/`), and terrain sets (a Terrain mode that paints corners and edges, templates, coverage). Saving calls `reloadAssets`, and every map drawing the tileset reads it again. A built-in tileset is drawn in code and is not opened here.
- **Tiled.** `TiledImporter(files, {tilesetFolder})` / `TiledExporter` (`core/level_map/` `tiled_import.dart`, `tiled_export.dart`) over a `TiledFiles` seam: a `.tmx` / `.tmj` into the scene (one undo step) or as a `.map.json`; `.tsx` / `.tsj` to `.tileset.json`; any map out to `.tmx` / `.tmj` with its tilesets beside it (a built-in's picture written as `<name>.png` beside its `.tsx`). Export writes tiles only: the entities on the map are not written as objects. On import each object group becomes an empty map layer, and `TiledImporter.entities` makes every object an entity on it (`parentName` the map, a `LayerComponent.mapLayer`): the first mapper (`EditorModule.tiledObjectMappers`) that takes it, else the prefab its class names — by id, name or one of its `aliases` — else a plain entity where it was. A map converted to a `.map.json` keeps its layers, not its objects. The Assets dock knows the kinds, offers the conversions, and drops tilesets and maps onto the viewport.
- **Play.** Map collision is off while authoring and built at Play; the generated body entities are excluded from saving, the tree, picking and play snapshots. The tile animation clock runs on wall time while authoring.
- **Checks.** `BuiltInValidators.levelMaps` (a second map — a piece is not one — missing tilesets, tiles past a tileset's end, unknown kinds, a turned map, incomplete terrains, an entity that names a map layer but is not under a map, and one on a layer its map no longer has) and `unshippedTileAssets` (files the pubspec does not ship). Built-in and virtual tileset paths (`TileAssets.isVirtual`) are never looked for as files.

