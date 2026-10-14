# Changelog

## 0.1.0

First release: a level editor that runs inside a `just_game_engine` game. It needs a desktop (Windows, macOS, Linux) in a debug build; `JustGameEditorPlugin.register` returns null in a profile or release build and on Android, iOS and the web (`supportsPlatform` says which).

### Fixed

- **Dragging the transform gizmo in the viewport can be undone.** A drag outside the Level Designer moved the entity without recording anything; it is now one undo step (`ViewportInput.commitTransform`), labelled Move, Rotate or Scale, including a drag the system cancels.

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
