# Changelog

## 0.1.0

First release: a level editor that runs inside a `just_game_engine` game. It needs a desktop (Windows, macOS, Linux) in a debug or profile build; `JustGameEditorPlugin.register` returns null in a release build and on Android, iOS and the web (`supportsPlatform` says which).

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
