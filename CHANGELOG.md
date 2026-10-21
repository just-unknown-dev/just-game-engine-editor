# Changelog

## 0.1.0-dev.1

First release: a level editor that runs inside a `just_game_engine` game in a debug build. The package compiles on every Flutter platform (web and wasm too); editing runs on Windows, macOS and Linux. Elsewhere, and in a profile or release build, `JustGameEditorPlugin.register` returns null (`supportsPlatform` says why) and the game runs on its own. Needs `just_game_engine` ^2.0.0-dev.2, Flutter 3.47.1 and Dart 3.11.

### Getting started

- `JustGameEditorPlugin.register` makes the editor for a game's engine, with the game's modules, spawners and hot reload hook; `JustGameEngineEditor` shows the game with the editor over it, and is a plain `GameWidget` when there is no editor.
- Built on `just_editor_core` (the module contract, the scope, undo, the inspector's rows, the UI kit), re-exported by the package's library.
- The editor's own tools come as modules, `BuiltInEditorModule`, `BuiltInMaterialsModule` and, for a game with 3-D graphics, `BuiltInGraphicsModule`, registered ahead of the game's (`JustGameEditorPlugin.builtInsFor`).

### Scenes and play-testing

- Scenes are JSON files in `assets/scenes/`, with the play order in `scenes.json`; the game loads the same files through the engine's `SceneLoader`.
- Files of an earlier scene format are migrated as they open; components no registered definition reads are kept and written back unchanged.
- New scene (2-D or 3-D) writes the same starter scenes as `just game scene new` (`just_game_engine_formats`).
- A start card when no scene is open, and a Scenes panel: search, sort, play order by drag or Alt+↑/↓, rename, duplicate, delete, keyboard control.
- Autosave with backups in `.editor_backups/`, recovery of unsaved changes on open, and the last session reopened on start.
- Play-testing in place: Play, Pause, Step, Restart and speed, a game-camera preview (F4), and the authored level put back exactly on Stop.
- The editor tells the `just` tool it has the project open (`.dart_tool/just_core_cli/editor.lock`), so `just game scene` and `just upgrade` wait for it.

### Viewport and scene tree

- All, Move, Scale and Rotate (Q, W, E, R); moving a parent carries its children; each gizmo drag is one undo step.
- Snapping: one switch, move, rotation and scale steps, smart snapping to entities and guides; Ctrl (Cmd on macOS) suspends it mid-drag.
- Gizmos shown or hidden per mode (editor, Level Designer, play-test), each kind on its own.
- The scene tree on the editor's one undo stack: re-parent, reorder, group, rename, enable, hide, lock, isolate, colour labels, and filters by component, tag, layer or problem.
- A right-click menu on the level; files dragged from the Assets dock become entities where they land. One that goes in the other kind of scene — a model in a 2-D scene, a sprite in a 3-D one — is turned away with a message saying where it goes.

### 3-D scenes

- An orbit-and-fly view, a 3-D gizmo (in world or local axes), picking by ray, a grid on the working plane, and placement on surfaces.
- A 3-D Level Designer with a built-in Default 3D kit: marquee select, a working plane, Place with a ghost, arrays, size handles for the eleven built-in 3-D shapes and for colliders, groups, view modes and a view cube, bookmarks, a slice plane, four views, a material paint tool, prefab files with overrides, and level aids (ruler, level checks, a performance meter, Play from here).
- 3-D physics when the engine has `Physics3D`: collider and character outlines, material presets, Solid and Trigger variants of every shape, and Problems checks.
- 3-D graphics when the engine has `Graphics3D` (`BuiltInGraphicsModule`, in `graphics.dart`): models (`.glb`, `.gltf`) in the Assets dock with rendered pictures, dropped into 3-D scenes, opened in a Model window of their import settings and cooked (`ModelCooking`), or placed with their lights and sockets as entities; picking by triangles; light markers, a selected light's reach and a selected camera's frustum; Model, Light and Environment inspector sections with sky presets.

### Inspector

- Built from each component's runtime `ComponentDefinition`, with an editor for every field type; vectors and related numbers in one row, lists and maps as rows, references as pickers.
- Cards that can be rearranged (Transform first), saved with the entity's component order.
- A typed value is kept when a field is left (Enter, Tab or a click elsewhere); Esc puts back what was there.
- A colour picker beside the field, live in the scene, with gradients, project palettes and an eyedropper.
- Tags from `assets/project/tags.json`, with tag and target pickers.
- Physics, 2-D and 3-D alike: body type, material presets, Fit to visual, collider editing in the viewport, named collision layers and a collision grid (`assets/project/physics.json`), a live readout while playing.
- Virtual cameras: previewed while authoring, frames, zones and confiners drawn in the viewport, Solo camera, and a dolly track tool.

### Level Designer

- Tools: Select, Draw, Paint, Sample and Measure, with rulers and guides, a minimap, view bookmarks, align, distribute, duplicate and array.
- The Level Map: one tile map per scene, painted with Stamp, Terrain, Fill, Erase and Select tiles, on orthogonal, isometric, staggered and hexagonal maps; placed entities go on its layers.
- LAYERS and TILESET panels, a built-in Basic shapes tileset, and a Tileset Editor for collision, animation, properties and terrains.
- Tiled: import `.tmx` and `.tmj`, convert `.tsx` and `.tsj`, export any map.
- A designer switch: a module can bring a Level Designer of its own (prefabs, tools, layers, grid).

### Sound and 2-D lighting

- Sound sources and the listener as markers, a selected source's reach drawn in the viewport, an Audio group in the Add menu, and an audio file dropped on the viewport becomes a source. Sound plays only in a play-test.
- 2-D lights and the scene's lighting as markers, a light's reach and a spot's cone drawn, a Lighting group in the Add menu, Shift+L to see the scene unlit, and a check for lights with no Scene lighting.

### Materials

- 3-D and 2-D material files pictured in the Assets dock; New material, New 2D material, New screen material and New variant.
- The 3-D and 2-D Material windows, alike in layout and keys: the material's values in cards on the left, a live preview under one toolbar, presets and variants. The 2-D window adds effects from a grouped, searchable Add effect menu.
- A material being edited is drawn live in the open scene; a material dropped on what it draws is one undo step; Level Map layers take a 2-D material.
- Problems checks for materials, with fixes; materials made from texture sets and from a model's own; normal maps made from a picture (`NormalMaps`, in `materials.dart`).

### Docks and settings

- One tabbed dock panel: Console (with a command line), Assets, Timeline, Profiler, World, Problems, History, Animator, Search, Tags and Physics Layers. Tabs reorder, docks pop out, and the layout is remembered.
- The Assets dock opens every file: a scene as the scene, a file in its module's window, and any other JSON file in a read-only JSON window.
- Timeline: dope sheet, curve editor, Record, markers, work and play ranges, motion paths in the viewport, and a preview that never reaches a save.
- Problems: what is wrong with the open scene, many with one-click fixes.
- Settings (Ctrl+,): appearance, accessibility, editing, snapping, viewport, saving, play-testing, Console, performance and every command's keys, searchable, exported and imported as one file.
- Accessibility: text size, bolder text, high contrast, colour-blind safe colours, reduced motion, longer timings, bigger targets and a visible focus ring.
- On macOS the shortcuts use Cmd, and Backspace deletes.

### Hot reload

- A hot reload brings the game's wiring (`register(onReassemble:)`), the component definitions, every registry, the Level Designer's tools and the built-in docks up to the code; a field added to a component shows in the inspector.
- `EditorModule.onRegister` runs once per module, `onReassemble` after each hot reload; definitions, prefabs and styles are getters, so a reload updates them.
- A hot restart starts the editor clean.
