# Changelog

## 0.1.0

First release: a level editor that runs inside a `just_game_engine` game. It needs a desktop (Windows, macOS, Linux) in a debug build; `JustGameEditorPlugin.register` returns null in a profile or release build and on Android, iOS and the web (`supportsPlatform` says which).

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
- **Play-testing**: Play, Pause, Restart, Step and speed (F5, F6, Shift+F5, F10), a game-camera preview, and the level put back exactly as authored on Stop.
- **Autosave and backups** to `.editor_backups/`, with recovery of unsaved changes on open, and the last session reopened on start.

### Viewport and scene tree

- **Transform tools** All, Move, Scale and Rotate (Q, W, E, R); moving a parent carries its children.
- **Snapping**: one switch for the whole editor, a move step, rotation and scale steps, smart snapping to other entities and guides; Ctrl suspends it mid-drag.
- **Right-click menu** on the level, and assets dragged from the Assets dock become entities where they land.
- **Scene tree** on one editor-wide undo: re-parent, reorder, group, rename, enable, hide, lock, isolate, colour labels, and filters by component, tag, layer or problem.

### Inspector

- **Components can be rearranged**: drag a card by the grip at the left of its header — a line shows where it will land, and the inspector scrolls when held at its edge — or use the ⋮ on its header (Move up, Move down, Move to top, Move to bottom). Transform stays first. Each move is one undo step, and the order is the entity's (`Entity.reorderComponents`), so the scene saves it; a component added goes last, and one removed comes back in its place on undo. Before, the cards came in whatever order the engine happened to store the types. `ReorderComponentsCommand`; `ComponentDragGrip`, `ComponentDropZone`, `ComponentPlaceMenu` in `inspector/component_reorder.dart`.
- **A typed value is kept when the field is left** — Enter, Tab, or a click anywhere else (another field, the viewport, the scene tree) — in every field, numbers included. Number fields (`ScrubbableNumberField`: every number and X·Y·Z row, a Physics Body's collider among them) and the compact `MiniNumberField` / `MiniTextField` used to keep it on Enter alone, leaving the typed number on screen and the component as it was. Esc puts back what was there; text that is not a number does too, rather than writing 0; Enter writes once, not twice; and Save from inside a field (Ctrl+S) keeps what was typed first (`PendingFieldEdits`). `CommitTextField` takes an `accept` check. Beyond the inspector: the Tileset Editor's fields (tile class and probability, offsets, terrain names and colours — the same compact fields), the Timeline's fields (which kept on leaving already, and now take Esc and Save too), and a map layer's rename in the scene tree (now kept on Tab as well). Dialogs, search boxes, "add" boxes and the console keep Enter as their action.
- **Built from the game's `ComponentDefinition`s**, with an editor for every field type: vectors and related numbers in one row, lists and maps as rows, entity references as pickers, enums as dropdowns.
- **Colour picker** beside the field, live in the scene, with gradients, project palettes and an eyedropper.
- **Tags** from the project's `assets/project/tags.json`: tag and target pickers, a header with the entity's tags as chips, and spawners the game registers.
- **Physics Body**: body type, grouped settings, material presets, Fit to visual, collider editing in the viewport, named collision layers and a collision grid (`assets/project/physics.json`), and live state while playing.
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
- **3-D seams**: `EditorView`, `EntityPicker` and `GizmoDragSolver`. 3-D scenes are behind `--dart-define=JGE_EDITOR_ALLOW_3D_SCENES=true`.
- The interface editor is `just_ui_editor` and the input actions editor is `just_input_editor`; add each as a module.
- `registerExtension`, `unregisterExtension` and `spawnRegistry:` are deprecated: pass `modules:` and `spawners:` instead.
