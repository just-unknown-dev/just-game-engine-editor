# Changelog

## 0.1.0-dev.1

First release: a level editor that runs inside a `just_game_engine` game. It needs a desktop (Windows, macOS, Linux) in a debug build; `JustGameEditorPlugin.register` returns null in a profile or release build and on Android, iOS and the web (`supportsPlatform` says which).

### The module contract is a package of its own

- **`just_editor_core`** holds what a module builds on — `EditorModule` and its contributions, `EditorScope` and its services, undo and the entity commands, the inspector's rows and field editors, the Level Designer's tool and overlay API, the viewport's views and pickers, and the UI kit. A kit or an editor plugin depends on it alone; this package re-exports its library, so a game's editor entry point is unchanged.
- **The editor's own tools are a module**, `BuiltInEditorModule`: field editors, inspector extras, commands and keys, prefabs and palette, the Tileset Editor, markers, the camera, sound, tag, tile and 3-D physics tooling, the 3-D view and the timeline's key button. The plugin makes its scope with it, and adds it to a scope it is handed; a test making a scope passes `builtIns: const [BuiltInEditorModule.new]`.
- **The editor's own services** — the dock controller, `EntityOps`, the Level Map's documents, tile state and provision — are getters on the scope from `EditorScopeServices`, each made when first asked for.
- `EditorModule.saveEditorData`, `restoreEditorData`, `StatusBarControl` and `SidePanelSection` take a `DesignerSession`; `CommandContext.plugin` is `host`, and the editor's commands read the session and plugin through `EditorCommandContext`.
- New: `EditorModule.fieldAccessories` (`FieldAccessory`), `EditorScope.openDock`, `PrefabColours`, `AudioDrop` (in place of `BuiltInAudioContributions.dropAudio`). `BuiltInValidators` and `PlanarEntityPicker` are files of their own.

### Fixed

- **Dragging the transform gizmo in the viewport can be undone.** A drag outside the Level Designer moved the entity without recording anything; it is now one undo step (`ViewportInput.commitTransform`), labelled Move, Rotate or Scale, including a drag the system cancels.

### Sound

- **Sound plays only in a play-test.** The game's `AudioSystem` is off while the scene is edited (it would start every source on load, and mark it played in the scene), and stopping a play-test stops what it played.
- **Built in for every project, 2-D and 3-D** (`BuiltInAudioContributions`): a marker on every sound source and on the listener; a selected 3-D source's reach drawn round it — where it starts to fade, and where it falls silent (`AudioRangeOverlay`, three rings round the axes in 3-D, one circle in 2-D); an **Audio** group in the Add menu — *Sound*, *3D sound* and *Audio listener*, placed in pixels in 2-D and metres in 3-D; and an audio file dropped on the viewport becomes a looping source of it, in 3-D in a 3-D scene.
- The Audio Source's inspector shows its 3-D settings (full within, silent beyond, fade, doppler, muffle to) when it is 3D, its pan when it is not, and its channel; the Audio Listener can be added and is saved (from the engine's definitions).
- The viewport menu of a 3-D scene offers the built-in prefabs that place in 3-D, before the modules'.

### 2-D lighting and materials

- **Built in for every 2-D project** (`BuiltInLighting2DContributions`): a marker on every 2-D light and on the scene's lighting; a selected light's reach and a spot's cone drawn in the viewport, and a selected shadow caster's outline; a Lighting group in the Add menu (Point light, Spot light, Scene lighting); **Shift+L** shows the scene unlit and lit again.
- A check says when 2-D lights light nothing for want of Scene lighting, and adds it (or turns it on) as the fix.
- A Level Map layer's settings take a 2-D material, whether it casts shadows and how deep; undo puts them back too, and renaming a material renames it on the layers that use it.
- A changed material file is read again by the game — 2-D ones (and the normal maps they name) and 3-D ones — whichever tool wrote it.
- An entity's own material values (`material2DOverrides`, `material3DOverrides`) are edited in the inspector, each with an editor of its kind, a way to take it away and a list of what can be added ([below](#materials-built-in)).

### Materials, built in

- **Materials are the editor's own** (`BuiltInMaterialsModule`, registered beside `BuiltInEditorModule`; its windows, pictures and tools in `package:just_game_engine_editor/materials.dart`), with or without `just_material_editor`: 3-D and 2-D material files pictured in the Assets dock (kept in `.dart_tool/just_game_engine_editor/material_pictures`); the 3-D Material window (sections, presets, variants, a live preview on five shapes in six lights) and the 2-D one (its effects in a panel on the right, each with what it does, a reset and a solo, more from an Add effect menu; presets; variants; a preview the engine draws, on the game's own sprite that uses it or what fits the material, zoomed and panned, tiled 3 × 3, with and without, its normals, a light to drag, a time bar, keys and chips); New material, New 2D material, New screen material and New variant; live in the scene while edited; dropped on what it draws as one undo step; Problems checks with fixes; texture sets and a model's materials made into material files; normal maps made from a picture.
- **The two Material windows look and work alike**: the material on the left (preset, kind, parent; its values in cards that fold, each with what it holds and a reset), the preview under one toolbar (subject, view, light, background, zoom, a keys sheet) with chips over its foot, the same keys (F, + and −, C, Space, B, Ctrl+S/Z/Y), and panels sized by their edge (`material_window_kit.dart`: `MaterialCard`, `MaterialCardFolds`, `PanelResizeHandle`, `PreviewChip`, `ZoomControls`, `ShortcutsHint`, `showPickMenu`). The 2-D window's effects are in a panel on the right, added from an **Add effect** menu, grouped and searched (`openAddEffect`, `addEffect`), and taken out — values and all — with the × on their card (`removeEffect`); an effect a variant switches off itself is listed with a way back. The 3-D window's shapes are chips, its background is the sky or plain dark or light (`PreviewBackdrop`, `MaterialPictures.render(background:)`), it zooms with buttons and Fit, and compares with a plain grey material (`setCompare`, Space held); a card resets what it holds (`cardKeys`, `resetCard`).
- **A module adds to another's window** through `EditorModule.workspaceContributions` (`just_editor_core`): a tool on its toolbar (`WorkspaceTool`), a section in its panel (`WorkspaceSection`) or an overlay over its preview (`WorkspaceOverlay`), by the window's id. The material windows (`WorkspaceIds.material`, `WorkspaceIds.material2D`) hand them a view of themselves (`Material3DWorkspaceView`, `Material2DWorkspaceView`): the material, what the preview shows, `change` as one undo step and `preview` for a value being dragged.

### The Assets dock opens every file

- **A scene** double-clicked in the scenes folder opens as the scene, as from the Scenes panel.
- **A JSON file no installed window opens** — a screen without `just_ui_editor`, an animator without `just_sprite_editor` — opens in the read-only JSON window (`BuiltInWorkspaces.json`) instead of the system's app: pretty-printed, its lines numbered, searched (Ctrl+F; Enter for the next match), copied; a file that is not valid JSON is shown as written, with why; Open in system app hands it on. A module's own window for a file comes first.

### 3-D scenes

A 3-D scene opens in the editor; the `JGE_EDITOR_ALLOW_3D_SCENES` gate is gone. The editor itself draws no model: a renderer package (`just_graphics_engine`, with `just_graphics_editor`) does, through the engine's scene renderers.

- **3-D physics is built in** for a project whose engine has `Physics3D`: collider and character outlines in the viewport (`ColliderOverlay3D`, 3-D scenes), the rigid body's material presets, a Solid and a Trigger of every 3-D shape in the Add menu, and Problems checks (`Physics3DChecks`: a body with no collider, a shape its body type cannot have, a character with a body too, a mesh or hull with no model, a matched shape that is not there, a joint to nothing; 3-D scenes only, with fixes). A 2-D project gets none of it (`BuiltInPhysics3DContributions.appliesTo`).
- **Orbit view.** `OrbitFlyEditorView` sees a 3-D scene: Alt+drag orbits, the middle button pans, the wheel moves in and out, and holding the right button looks around while W/A/S/D/Q/E fly (Shift faster); a right-click that does not drag still opens the menu. F frames the selection, Shift+F everything; the pad's 1, 3 and 7 look from the front, the right and above (Ctrl for the other side). Each scene mode keeps its own view, and a module can bring another (`EditorModule.viewFactories`).
- **3-D gizmo.** Arrows, plane squares, rotation rings and scale boxes (`Gizmo3D`, `RayGizmoHitTester`, `RayGizmoDragSolver`), in the world's axes or the entity's own (X toggles), snapping in metres (`EditorSceneState.moveStep3D`), degrees and scale steps. A drag is one undo step, depth included.
- **Picking with rays.** `RayEntityPicker` tests each entity's 3-D box, then its real shape where a module knows it (`EditorModule.pickTests`, `EntityRayTest`).
- **Ground grid**, selection boxes and markers drawn in space. The camera and spawn-point icons come from a registry modules add to (`EditorMarker`, `EditorModule.markers`).
- **Kinds of file are a registry.** `AssetKind` is a class now, with its icon, colour, filter chip, an optional picture (`preview`) and what dropping one on the viewport makes (`drop`, given an `AssetDrop`); a module adds its own (`EditorModule.assetKinds`), a 3-D model's say.
- **Viewport overlays.** `EditorModule.viewportOverlays` draw over the viewport while authoring, with the Level Designer open or not, in the scene modes they name (`ViewportOverlay`); `EditorScope.hiddenOverlays` turns them off.
- **Placing in space.** New entity, Paste and dropped files land where the pointer meets the ground; the viewport menu offers the modules' 3-D prefabs on the surface under the pointer (`PrefabDefinition.buildAt`, `SurfacePoint`). Duplicate, group and paste keep an entity's depth.
- **Viewport handles.** A module offers points of the selection to drag in the viewport — a polygon's corners — through `EditorModule.viewportHandles` (`ViewportHandles`, `ViewportHandle`, `HandleDrag` with ray-on-plane and along-a-line helpers, `HandleClick`). The editor draws them, picks them before any tool or the gizmo, snaps with Ctrl, and records each drag or click as one undo step of whatever it changed in the handle's component (`HandleDragSession`).
- **Prefab variants.** `EditorModule.prefabVariants` offers the prefabs any module offers in space again with more to them (`PrefabVariant`): a physics module's Solid and Trigger of every shape. With more than eight prefabs, the viewport menu lists them by category, each opening a menu of its own.
- **The timeline's Add track menu** lists every kind of track the engine offers, a package's included (`TimelineTrackOffer`).
- **One chord, one command per mode.** A key bound to a 2-D and a 3-D command runs the one for the scene's mode, and a command of another dispatch scope no longer hides one bound earlier.
- The game preview draws the scene renderers too, so it shows a 3-D game's image.

### Shared with the `just` tool

- **New Scene writes the shared starters.** The 2-D and 3-D starter scenes, the play order in `scenes.json` and the naming rules come from `just_game_engine_formats` (`SceneStarters`, `SceneManifest`, `SceneNames`, re-exported by the engine), so a level made in the editor and one made by `just game scene new` are the same file. `test/scene_starters_parity_test.dart` checks the starters still match the live components, encoded.
- **The editor says it has the project open**: while it runs it touches `.dart_tool/just_core_cli/editor.lock` every few seconds (`EditorPresence`), and `just game scene` and `just upgrade` wait until it is closed rather than write scenes the editor would save over. Off under `flutter test`.

### Hot reload and hot restart

- **A hot reload reaches the editor.** The overlay's `State.reassemble` calls `JustGameEditorPlugin.reassemble`, which brings the game's wiring, the component definitions, every registry, the Level Designer's tools and the built-in docks up to the code as it now is — nothing called it before. A field added to a component shows in the inspector, and a live component that cannot read it is made again from what it holds.
- **`EditorModule.onRegister` runs once** per module, however often the registries are rebuilt; the new `onReassemble` runs after each hot reload. The Asset Store's install recovery, and the Interface module's font reload and screens-layer switch, no longer repeat on every rebuild.
- **`register(onReassemble:)`**: what the app does again after each hot reload — its interface bindings, new systems, spawners (`EditorScope.spawners`, read at Play) and modules (`JustGameEditorPlugin.syncModules`).
- **Built once, never again — fixed**: the built-in prefabs, the Tileset Editor workspace and the frozen inspector, timeline and tileset styles are getters now, so they follow a reload and a theme change; the built-in docks are made again (`BuiltInDocks.invalidate`); theme presets are made again and a module's dropped preset goes (`ThemeController.resetPresets`, `refreshCurrent`).
- `EditorScope(isDebug:)` follows the build (`kDebugMode`) unless given.

### Scenes and play-testing

- **Scenes are JSON** in `assets/scenes/`, with the play order in `scenes.json`, and load in the game through the engine's `SceneLoader`. Older scene formats are migrated on open; components no definition reads are kept and written back unchanged.
- **Start card** when no scene is open: New scene, Reopen or Open, a short how-to, and the modules' tools and tips.
- **Scenes panel**: search, sort (play order, name, recent), play order by drag or Alt+↑/↓, rename, duplicate, delete, and keyboard control.
- **Play-testing**: Play, Pause, Restart, Step and speed (F5, F6, Shift+F5, F10), a game-camera preview, and the level put back exactly as authored on Stop. A game that looks with the mouse (`engine.input.lockPointerOnClick`) holds it on a click on the play-test, as it does outside the editor; Escape, Pause and Stop let go.
- **Autosave and backups** to `.editor_backups/`, with recovery of unsaved changes on open, and the last session reopened on start.

### Viewport and scene tree

- **Transform tools** All, Move, Scale and Rotate (Q, W, E, R); moving a parent carries its children.
- **Snapping**: one switch for the whole editor, a move step, rotation and scale steps, smart snapping to other entities and guides; Ctrl suspends it mid-drag.
- **Right-click menu** on the level, and assets dragged from the Assets dock become entities where they land.
- **Scene tree** on one editor-wide undo: re-parent, reorder, group, rename, enable, hide, lock, isolate, colour labels, and filters by component, tag, layer or problem.

### Inspector

- **Components can be rearranged**: drag a card by the grip at the left of its header — a line shows where it will land, and the inspector scrolls when held at its edge — or use the ⋮ on its header (Move up, Move down, Move to top, Move to bottom). Transform stays first. Each move is one undo step, and the order is the entity's (`Entity.reorderComponents`), so the scene saves it; a component added goes last, and one removed comes back in its place on undo. Before, the cards came in whatever order the engine happened to store the types. `ReorderComponentsCommand`; `ComponentDragGrip`, `ComponentDropZone`, `ComponentPlaceMenu` in `inspector/component_reorder.dart`.
- **A typed value is kept when the field is left** — Enter, Tab, or a click anywhere else (another field, the viewport, the scene tree) — in every field, numbers included. Number fields (`ScrubbableNumberField`: every number and X·Y·Z row, a collider's size among them) and the compact `MiniNumberField` / `MiniTextField` used to keep it on Enter alone, leaving the typed number on screen and the component as it was. Esc puts back what was there; text that is not a number does too, rather than writing 0; Enter writes once, not twice; and Save from inside a field (Ctrl+S) keeps what was typed first (`PendingFieldEdits`). `CommitTextField` takes an `accept` check. Beyond the inspector: the Tileset Editor's fields (tile class and probability, offsets, terrain names and colours — the same compact fields), the Timeline's fields (which kept on leaving already, and now take Esc and Save too), and a map layer's rename in the scene tree (now kept on Tab as well). Dialogs, search boxes, "add" boxes and the console keep Enter as their action.
- **Built from the game's `ComponentDefinition`s**, with an editor for every field type: vectors and related numbers in one row, lists and maps as rows, entity references as pickers, enums as dropdowns.
- **Colour picker** beside the field, live in the scene, with gradients, project palettes and an eyedropper.
- **Tags** from the project's `assets/project/tags.json`: tag and target pickers, a header with the entity's tags as chips, and spawners the game registers.
- **Physics**: 2-D and 3-D bodies look and work alike — a rigid body (body type, grouped settings in the same order and words, material presets) and a collider (its shape, Match what is drawn, Fit to visual, editing in the viewport), named collision layers and a collision grid (`assets/project/physics.json`), live state while playing, and Problems checks with fixes (a body with no collider, a collider matching nothing drawn, one that disagrees with what is drawn). The Level Designer's Solid and Trigger are a static body whose collider matches the drawn rectangle. A `CharacterBody2D` is inspected like 3-D's `CharacterBody3D`, its shape is drawn in the viewport, and a character that is also a rigid body or has a collider is a problem with a one-step fix.
- **Virtual cameras**: the brain previewed while authoring, frames, zones and confiners drawn in the viewport, Solo camera, and camera prefabs with a dolly track tool.

### Level Designer

- **Tools**: Select, Draw, Paint (brushes, eraser, bucket fill), Measure and Sample, with rulers and guides, a minimap, view bookmarks, and align, distribute, duplicate and array.
- **Level Map**: a tile map per scene with Stamp, Terrain, Fill, Erase and Select tiles, for orthogonal, isometric, staggered and hexagonal maps. Placed entities go on the map's layers.
- **LAYERS and TILESET panels**, a built-in Basic shapes tileset, and a Tileset Editor for collision, animation, properties and terrains.
- **Tiled**: import `.tmx`/`.tmj`, convert `.tsx`/`.tsj`, and export any map.
- **Designer switch**: a module can bring its own prefabs, tools, layers and grid.
- The designer's side panel scrolls when its open sections don't fit; a palette or list keeps a share of the height (at least 220 px).

### A 3-D Level Designer

In a 3-D scene the Level Designer is a 3-D one, with a built-in **Default 3D kit**; kits plug in beside it, as in 2-D. The switch lists the designers for the open scene's mode: Default and Platformer in 2-D; Default, World Builder and Third Person in 3-D.

- **Select**: marquee, select similar (Shift+G); the gizmo moves, turns and sizes the whole selection about its centre, pivot or base, takes typed values, has a view ring, and snaps to surfaces, bounds and vertices (V).
- **Working plane** with a metre grid, raised and lowered with Page Up and Page Down.
- **Placing**: a ghost before it is made, aimed by dragging, spun with Shift+wheel, standing on surfaces or leaning with them, turned and sized at random, stamped in strokes; End drops the selection to the ground; arrays in a line, a grid or a circle; Ctrl+D repeats the last offset.
- **Size handles** for all 11 shapes and for colliders; **groups** (Ctrl+G, Ctrl+Shift+G) and a Groups panel.
- **Views**: lit, unlit, wireframe and collision; outline; orthographic with a view cube; 3-D bookmarks; a slice plane; four views at once.
- **Materials**: a panel and a paint tool for material files.
- **Prefab files**: make one from the selection, edit it in place, keep an instance's changes as overrides (revert or apply them), unpack one; prefabs in the palette in 2-D and 3-D.
- **Aids**: a 3-D ruler, level checks (spawns over nothing, solids over the void, things below the kill height), a performance meter, play from here.
- The 3-D side panel's sections follow the tools in hand: MATERIALS with the shape tools, GROUPS and ARRAY with select and the shape tools, a module's sections with the groups they name.
- The 11 basic shapes moved here from just_graphics_editor.

### Docks and settings

- **A tabbed dock panel**: Console (with a command line), Assets browser, Timeline, Profiler, World, Problems, History, Animator, Search, Tags and Physics Layers. Tabs reorder, docks pop out, and the layout is remembered.
- **Timeline**: dope sheet, curve editor, Record, markers, work and play ranges, motion paths in the viewport, and a preview that never leaks into a save.
- **Problems** lists what is wrong with the open scene, many with one-click fixes.
- **Settings** (Ctrl+,): editing, saving, snapping, viewport, play-testing, console, performance, rebindable shortcuts, and export and import.
- **Accessibility**: text size, bolder text, high contrast, colour-blind safe colours, reduced motion, longer timings, bigger targets and a visible focus ring.

### For modules

- **`EditorScope`** holds one editor's registries and services; two scopes share nothing. State is on `just_signals`.
- **`EditorModule`** contributes field editors, component extras, prefabs, tools, overlays, layers, grid topologies (`SquareGrid`, `HexGrid`), commands and key bindings, snap providers, docks, toolbar buttons, scene-tree actions, inspector and settings sections, themes, checks, workspaces, asset actions, Tiled object mappers, tags and tips.
- **The kit** (`lib/src/ui/kit/`): buttons, fields, dropdowns, dialogs, the workspace frame and `EditorKeyClaim`, so a module looks like the rest of the editor.
- **3-D seams**: `EditorView`, `EntityPicker` and `GizmoDragSolver`.
- The interface editor is `just_ui_editor` and the input actions editor is `just_input_editor`; add each as a module.
- `registerExtension`, `unregisterExtension` and `spawnRegistry:` are deprecated: pass `modules:` and `spawners:` instead.
- A module hears of a scene save before the file is written (`onSceneSaving`); one that fails is reported and the scene saved.
