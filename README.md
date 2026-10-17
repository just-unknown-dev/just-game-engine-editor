# Just Game Engine Editor

A level editor that runs inside a [`just_game_engine`](../just_game_engine/) game. Start the game's editor entry point in a debug build on Windows, macOS or Linux and the running game is the scene you edit: 2-D and 3-D scenes, the Level Map, physics, cameras, timelines and play-testing, all on one undo stack. Press **F1** to show or hide it. A profile or release build of the game holds none of it.

## 📚 Documentation

- **[Quick Start Guide](QUICKSTART.md)**: an editor entry point, hot reload, your own components, a first level, cameras
- **[Architecture](ARCHITECTURE.md)**: how the package is put together, and the seams a module plugs into
- **[Changelog](CHANGELOG.md)**

---

## Features

- **2-D and 3-D scenes**. A scene is made 2-D or 3-D. A 3-D scene gets an orbit-and-fly view, a 3-D gizmo, picking by ray, a ground grid and placement on surfaces ([below](#3-d-scenes)). The editor draws no models itself: the game's renderer does (`just_graphics_engine`, with `just_graphics_editor` as a module).
- **Scenes are JSON** in `assets/scenes/`, the play order in `scenes.json`, and the game loads the same files. Autosave keeps backups and offers to recover unsaved changes ([below](#scenes-and-saving)).
- **Play-testing** in place: Play, Pause, Step, Restart and speed, a preview of what the game camera sees, and the level put back exactly as authored on Stop ([below](#play-testing)).
- **Transform tools**: All (Q), Move (W), Scale (E) and Rotate (R), from a floating toolbar at the top right of the viewport, in the editor and the Level Designer alike. Moving a parent carries its children.
- **Snapping**: one switch for the viewport and the Level Designer, a move step, rotation and scale steps, smart snapping to other entities and guides. Ctrl suspends it mid-drag. A magnet and a grid button on the settings gear switch it; right-click either for its steps.
- **Scene tree**: re-parent, reorder, group, rename, enable, hide, lock, isolate, colour labels, and filters by component, tag, layer or problem ([below](#the-scene-tree)).
- **Inspector**, built from each component's runtime definition: an editor for every field type, a colour picker, tag and entity pickers, and cards you can rearrange (Transform stays first; the order is saved with the scene).
- **Physics**: 2-D and 3-D bodies look and work alike. Body type, material presets, Fit to visual, collider handles in the viewport, named collision layers with a Physics Layers dock, and a live readout while playing ([below](#physics-bodies)).
- **Cameras**: the game's virtual cameras previewed while you work, their frames, zones and bounds drawn in the viewport, and Solo camera in the scene tree.
- **Level Designer**: a grouped tool strip, the scene's **Level Map** (tiles on square, isometric, staggered and hexagonal grids, a built-in *Basic shapes* tileset, a Tileset Editor), and everything placed as an entity under the map, on one of its layers. Tiled maps import and export ([below](#the-level-designer)).
- **Timeline**: reusable timelines that animate any component field, with a dope sheet, curve editor, record mode and motion paths in the viewport.
- **Docks**: Console, Assets, Timeline, Profiler, World, Problems, Tags, Physics Layers, History, Animator and Search, in one tabbed panel whose layout is remembered ([below](#docks)).
- **Problems** lists what is wrong with the open scene, many with a one-click fix.
- **Settings** (the gear at the foot of the viewport, or Ctrl+,): appearance, accessibility, editing, snapping, viewport, saving, play-testing, the Console, performance and every command's keys, all searchable, and exported or imported as one file.
- **Accessibility**: text size, bolder text, high contrast, colour-blind safe status colours, reduced motion, longer timings, bigger targets and a visible focus ring.
- **Modules**: a game, a kit or a tool adds what it needs through one class, `EditorModule`: prefabs, tools, docks, inspector sections, checks, workspaces, asset kinds, views and more ([below](#extending-the-editor)). The in-game interface editor (`just_ui_editor`), the sprite studio (`just_sprite_editor`) and the input actions editor (`just_input_editor`) are modules.
- **Hot reload, all the way**: **r** brings the registries, the modules, the component definitions and the docks up to the code as it now is; **R** starts clean ([below](#hot-reload-and-hot-restart)).
- **Debug and desktop only** ([below](#keeping-the-editor-out-of-a-release-build)).

---

## Install

The editor is a dev dependency, beside the modules you use:

```yaml
dev_dependencies:
  just_game_engine_editor: ^0.1.0-dev.1
```

It comes from the Asset Store, not pub.dev. A project made with `just create` has it already; otherwise `just add just_game_engine_editor` (short for `just store install`). The store puts it in `packages/core/just_game_engine_editor` and points the dependency there in `pubspec_overrides.yaml`.

Only the editor's entry point imports it, so a release build leaves it out, and also the native plugins only the editor packages bring (on Windows and Linux; see [below](#keeping-the-editor-out-of-a-release-build)). The [Quick Start Guide](QUICKSTART.md) wires it up:

```dart
final plugin = await JustGameEditorPlugin.register(
  engine: engine,                 // the engine the game booted
  modules: [MyGameModule()],      // what your game adds to the editor
  spawners: mySpawners,           // what spawn points make at Play
  onReassemble: (plugin) => rewire(engine, plugin), // after each hot reload
);
engine.start();
runApp(MaterialApp(home: JustGameEngineEditor(engine: engine, plugin: plugin)));
```

`register` returns null outside a debug build and off the desktop (`JustGameEditorPlugin.supportsPlatform`), and `JustGameEngineEditor` is then a plain `GameWidget`.

---

## Scenes and saving

A scene is one file, `assets/scenes/<name>.scene.json`. The game loads the same file through the engine's `SceneLoader`; there is no code generation and nothing between saving here and the level shipping.

```
assets/scenes/
  scenes.json            ← the play order: {"scenes": ["level_01", "level_02"]}
  level_01.scene.json    ← {version, name, mode, entities, editor}
```

- **The file.** `version` is the scene format (9 today), `mode` is `2d` or `3d`, and each entity is its name, its parent's name, and its components as `{type, fields}`, written by each component's definition. The `editor` section holds what only the editor reads (the Level Designer in use, guides, view bookmarks, each module's own data); the game ignores it. A Level Map is kept in the scene or in a `.map.json` of its own, saved with the scene.
- **Older files** are migrated as they open. The file changes only when you save; the Console says so.
- **Components the editor cannot read** (a module left out this session, say) are kept as the file had them and saved back unchanged, listed in Problems and shown as a card in the inspector.
- **New scene** asks for a name and whether the scene is 2-D or 3-D, and writes the same starter scene `just game scene new` does: a camera and the player's spawn point, and in 2-D the bounds the camera keeps to. The first scene in the play order is where the game starts.
- **With no scene open**, the viewport shows a start card: New scene, Reopen the last one (or Open the first), the steps to a saved level with their keys, the tools that need no scene, and the modules' tips. The **Scenes** panel on the right searches, sorts (play order, name, recently opened), reorders the play order by dragging or Alt+↑/↓, and renames, duplicates and deletes. A scene the game protects (`register(protectedSceneNames:)`) cannot be renamed or deleted.
- **Saving.** Ctrl+S saves the scene, and any map files it uses. Saving during a play-test saves the level as authored, not as the game left it.
- **Autosave** runs every 2 minutes by default and, unless set to save the scene itself, keeps a backup in `.editor_backups/<scene>/`, the newest 10 by default. Opening a scene whose newest backup holds changes the file lacks asks whether to recover them; *Open saved* sets the backup aside.
- **The editor's log** is kept in `.editor_logs/editor_runtime.jsonl`, so the Console shows the last session too. While it runs, the editor touches `.dart_tool/just_core_cli/editor.lock`, and `just game scene` and `just upgrade` wait for it to close rather than write scenes it would save over.

---

## Play-testing

| Key | |
|-----|---|
| `F5` | Play, or Stop |
| `Shift+F5` | Restart |
| `F6` | Pause, or resume |
| `F10` | Step one frame (pausing first) |

Play spawns at every spawn point through the spawners the game passes to `register(spawners: …)`, so the editor spawns exactly the player the shipped game does; a spawn point naming no spawner is a warning. While playing, the game's camera brain drives the view, map collision and timelines run, and entities the game makes are listed under a *Runtime* divider in the scene tree. **Stop** puts every authored entity back as it was, in place (selection and undo stay valid), removes what play made and remakes what play destroyed. The speed control runs the game at a quarter, half, normal or double speed.

A game that looks with the mouse (`engine.input.lockPointerOnClick`, Windows) holds it on a click on the game while it plays, as it does outside the editor: the cursor hides and stays in the window. Escape lets go, and so do Pause and Stop, so the editor has the mouse back.

While authoring, **F4** shows what the game camera frames as a picture in the viewport. The Play-testing settings can pause the game when an error is logged, and hide the editor while playing.

---

## The scene tree

The tree is where a scene's *shape* is edited, and everything it does goes through the editor's one undo stack — re-parenting, reordering, renaming, grouping and deleting alike.

- **Selecting.** A click selects at once. `Ctrl` adds to the selection, `Shift` takes a range. Clicking the name of a row that is **already** selected renames it; **double-clicking** focuses the entity in the viewport (the Level Map opens the Level Designer instead).
- **Keys.** While the tree has the focus, its keys are its own: the arrows walk it (Alt+↑/↓ moves a row among its siblings), F2 or Enter renames, Delete deletes, Ctrl+D duplicates, Ctrl+G groups and Ctrl+Shift+G ungroups, Esc clears the selection, and a letter jumps to the next row starting with it. Ctrl+S still saves.
- **Moving things.** Hold a row for a moment to pick it up. A drag carries the whole selection when the row is part of it; the line between two rows means *between*, the body of a row means *inside*, and a drag resting on a shut row opens it. Dropping past the last row moves to the top level.
- **What a row shows.** Its icon (a module's, if one claims the entity), a colour label if you have marked it, and at the end whatever the editor and the modules have to add: how many scene checks it fails, whether a timeline or an animator moves it, whether a camera is live.
- **Hiding and switching off are different things.** The eye hides a row in the viewport and is the editor's business alone — nothing about it is saved and the game never sees it. **Enabled**, in the inspector, is saved with the scene as `"enabled": false` and the game honours it; a switched-off entity stays in the tree, struck through. *Isolate* in the context menu hides everything except the selection and what is under it.
- **Finding things.** The search box matches a name *or* a component type, so "sprite" finds everything drawn. The chips under it filter by component, tag, layer, or "has problems", offering only what the open scene actually contains. A match keeps its parents, drawn faded, so you can still see where it lives.
- **While playing.** Entities the running game spawned are listed under a greyed *Runtime* divider and are never saved.
- **The Level Map's rows.** The *Level Map* opens to its layers, front first, each shut until you open it, and each layer to the entities on it. Those are ordinary entity rows: they select, drag and rename, and have the usual menu. Children of the map on none of its layers come after the layer rows. Selecting an entity on a layer opens that layer. A layer row says how many entities are on it. Click it to paint on it, double-click to rename it. Its eye and lock are the map's own, saved with it and undoable, and they hide and lock what is on the layer too. Its menu renames the layer, or deletes it with everything on it.
- **Putting entities on a layer.** Drop entities on a layer row and they go on that layer. Drop them beside an entity that is on a layer and they join its layer. Drag them out of the map and they leave its layers. Each is one undo step. Layer rows themselves do not drag: a map's layers are arranged in the Level Designer's LAYERS panel. Search matches entities and layer names; the arrow keys walk entities and skip layer rows. **Double-clicking** the *Level Map* opens the Level Designer on it, with the Stamp in hand (unless a tile tool already is) and the view on what is painted.

Which rows are open and how they are coloured are saved in the scene file's `editor` section, by name, and are never read by the game.

### On the level itself

Right-clicking an entity in the viewport opens the same menu its row does — focus, duplicate, delete, copy, group, hide, lock, isolate — and right-clicking bare level offers *Paste here* and *New entity here*, which put the entity where the pointer is rather than at the camera. While tiles are selected with Select tiles (V), right-click opens their own menu instead: *Make the N tiles an entity*, *Copy tiles*, *Cut tiles*, *Delete tiles*, *Select none*. Otherwise a tile tool keeps the plain right button for picking tiles up, so open the menu with **Shift**+right-click.

Files dragged from the Assets dock become entities where they land: an image a sprite, a sprite sheet an animated sprite, a tileset or a map file the scene's Level Map, a Tiled map an import. A module's kinds of file make what the module says (a 3-D model, with `just_graphics_editor`).

---

## 3-D scenes

A scene made 3-D (*New scene → 3D*, or a file with `"mode": "3d"`) is seen through an orbiting camera of the editor's own, never the game's:

| Do | To |
|----|----|
| Alt+drag | Orbit around the point you look at |
| Middle-drag | Pan |
| Wheel | Move in and out |
| Hold the right button | Look around; W/A/S/D fly, E/Q rise and sink, Shift goes faster |
| Right-click without dragging | The viewport menu |
| `F` / `Shift+F` | Frame the selection / everything |
| Numpad `1` / `3` / `7` | Look from the front, the right, above (with Ctrl, the other side) |
| `X` | The gizmo in the world's axes or the entity's own |

- **The gizmo** has arrows, plane squares, rotation rings and scale boxes. It snaps in metres, degrees and scale steps while snapping is on. A second press on the selected entity drags it along the ground. Each drag is one undo step.
- **Picking** casts a ray at each entity's box, then at its real shape where a module knows it (a model, a 3-D shape).
- **The ground grid** is drawn at y = 0 around where you look, the X axis red and the Z axis blue. Cameras and spawn points are drawn as markers.
- **Placing.** New entity, Paste and dropped files land where the pointer meets the ground, or the face of what is under it. The viewport menu offers the 3-D prefabs on that surface, grouped by category when there are many: the editor's eleven 3-D shapes, and a Solid and a Trigger of each when the game has 3-D physics, then the modules' own.
- **Handles.** A module can put points of the selection in the viewport to drag (a 3-D polygon's corners); Ctrl snaps them, and each drag is one undo step.
- **3-D physics** shows itself when the game's engine has `Physics3D`: collider and character outlines, the rigid body's material presets, the Solid and Trigger variants, and Problems checks with fixes. A 2-D project gets none of it.

The game preview (F4) shows the game's own 3-D image.

### The 3-D Level Designer

In a 3-D scene, F3 opens the Level Designer in 3-D, with the editor's built-in **Default 3D kit**. Kits plug in beside it as in 2-D: the switch at the top of the side panel lists the designers for the scene's mode (Default, World Builder, Third Person in 3-D), one at a time, and the default kit's tools stay in every one. The 2-D Level Map, its layers and tilesets are not part of a 3-D scene.

- **Select** takes what is clicked, or what a marquee dragged over empty space covers (Shift or Ctrl add); Shift+G selects similar things. The gizmo moves, turns and sizes the whole selection about its centre, its pivot or its base, takes typed values while dragging (digits, Enter keeps, Esc restores), has a view ring, and snaps to surfaces, to bounds and, holding V, to vertices.
- **The working plane** is where tools aim when nothing is under the pointer: a metre grid, raised and lowered with Page Up and Page Down (Shift ten times as far), turned with `\`, brought to the selection with Shift+`\`. The move step is in the status bar.
- **Place** (the palette's shapes, models, prefabs and prefab files) shows a ghost before it is made, on the surface under the pointer or the plane; drag to aim it, Shift+wheel to spin it. It can stand upright or lean with the surface, turn and size at random, or stamp a stroke of copies. End drops the selection onto what is under it. ARRAY copies the selection in a line, a grid or a circle; Ctrl+D repeats the last copy's offset.
- **Size handles** on a shape's faces (all eleven shapes) and on a collider: the far face stays, one undo step a drag. **Groups** are empty parent entities: Ctrl+G, Ctrl+Shift+G, and a GROUPS section with eye and lock.
- **VIEW**: lit, unlit, wireframe and collision; the selection's outline; orthographic views (numpad 5) and a view cube; bookmarks that keep the whole pose; a slice plane; four views at once (Ctrl+Alt+Q). F and Shift+F frame.
- **MATERIALS** lists the project's material files; the paint tool (P) draws what it is dragged over with one, Alt picks one up.
- **Prefab files**: make one from the selection, open it in place (the rest of the level dims, a banner offers Apply and leave), keep an instance's changes as overrides — marked in the inspector, each revertable or applied to the file — or unpack an instance into plain entities.
- **Aids**: the ruler (M), level checks in Problems (a spawn with nothing under it, a solid over the void, things below the kill height), a performance meter in the status bar (draws against a budget of 100, triangles, instances), and *Play from here* in the viewport menu. A genre kit adds its own aids (`LevelAids`): the third-person kit draws how far the hero jumps and how steep it walks.

---

## The Level Designer

**F3**, or the map icon on the play toolbar, opens it. Along the bottom of the window, from the bottom up, are the docks' status strip, any dock panel that is open, and the designer's own status bar: the tool's options at its left, then snapping, the grid, overlay switches, module controls, the cell under the pointer while a tile tool is in hand, and what the tool last said. Lists, the tool strip and the scene tree always show their scroll bars.

- **The tool strip** floats at the top right of the level, under the transform column, and scrolls when the window is short. It groups tools under captions, each button with its key in the corner. SELECT: a module's own such as the platformer kit's Path (K), and Track (a dolly camera's track) — the select tool itself is the transform column. SHAPES: Draw (B), Paint (P), Sample (I). TILES: Stamp (S), Fill (G), Terrain (T), Erase (D), Select tiles (V). MEASURE: Measure (M). A module adds a group with `EditorModule.toolGroups`.
- **All, Move, Scale, Rotate (Q, W, E, R)** are a column at the top right of the viewport (`TransformToolbar`, in a `FloatingToolFrame`), in the editor and the designer; in the designer they are the select tool. All is the default and the gizmo as it always was. The mode is `scope.view.transformMode`; `TransformModes.forEntities` says what a selection can take (a level map only moves; a lone piece of one also turns, its tiles a quarter at a time, in the designer; tiles picked with Select tiles move and turn) and `TransformModes.shown` falls back to All, which leaves off what does not apply. The gizmos are drawn and hit-tested by `TransformGizmo` for the editor (`GizmoPainter`, `GizmoHitTester`) and the designer (`SelectionHandlesOverlay`, `SelectTool`, `TileSelectTool`) alike. The commands are `editor.transform.all/move/scale/rotate`; Replace moved to Shift+R.
- **The tool's options**, at the left of the designer's status bar along the bottom, are the settings of the tool in hand. There is no options bar at the top. For Paint, Brush / Rect / Erase / Fill and the brush size. For the tile tools, the layer being painted, Random, the fill shape, the eraser's size, the select mode (and, for Select tiles, *Make entity*), and switches to highlight the layer and show collision. For Draw and Paint, the prefab and where it will go: `→ Level Map ▸ Ground`, `→ Level Map ▸ a new Background layer`, `→ a new Level Map`. A tool puts its own there with `LevelToolHandler.buildOptions`.
- **TILESET** is one scrolling list with a section per tileset. Each section has a header (a chevron that folds it away, its name, and a ⋮ menu with *Edit tileset…* and *Remove from the map*) and its tiles below at full height. The Tiles / Terrains switch and **+** (add a tileset) are at the top, the zoom at the bottom. The engine's built-in **Basic shapes** tileset is always listed first, marked "built in · not on the map" until you use it. Picking one of its tiles adds it to the map, and makes the Level Map in a scene with none, in one undo step. It has 24 tiles of 32 px: a block, halves, quarters, a small block, a one-way plank, 45° slopes (floor and ceiling), 22.5° floor slopes, rounded corners, a circle, a triangle and a diamond, each colliding as drawn. A built-in tileset does not open in the Tileset Editor.
- **LAYERS** is one list, grouped by depth, front first: Foreground, Main, Background, and any other the scene uses. Under each depth are the Level Map's layers that draw there, and a row for the entities at that depth that are on no map layer. A map layer's eye and lock are saved with the map and hide and lock what is on it too. Its switch says whether its tiles collide. It shows how many entities are on it, and has a button that moves the selection onto it. Its expander holds opacity, tint, depth, z order, parallax, offset and class. The entities row's eye and lock are the editor's alone, and it can move the selection to its depth (one undo step), leaving alone anything on a map layer. **+** on a depth adds a map layer there. The toolbar has the map's settings (grid, tile size, stagger, hex side), duplicate and delete (both take what is on the layer too, one undo step each), raise and lower. Position, rotation and scale are in the inspector.
- **The Level Map.** A scene has one map, the entity *Level Map* (its component shows as *Map*). You do not place it. The first tile painted, thing placed or tileset dropped makes it, as does *Create Level Map* in LAYERS or TILESET, and one Ctrl+Z takes it away with what was drawn. It is kept in the scene, or in a `.map.json` of its own (older `.tilemap.json` files still load). A dropped `.map.json` becomes the Level Map, or replaces an empty one. It is refused if the scene's map already has something on it, and so is a Tiled *Import into this scene*. A second map in a scene is a warning in Problems; a piece of tiles cut out of it (below) is not.
- **Everything placed goes under the map.** Draw, Paint, a point prefab and an image or sprite dropped from Assets make entities, as each prefab's `build` says. Each is a child of the Level Map, on one of its layers (`LayerComponent.mapLayer`): the layer being painted if it draws at the depth you are placing at, else the frontmost layer at that depth, else a new layer named after the depth. The layer, and the map itself for the first thing placed, are made in the same undo step. A prefab can insist on a depth with `PrefabDefinition.depth` (the platformer kit's Decoration goes to the background). A locked or hidden layer refuses, and the status bar says why. On a map layer an entity draws at the layer's depth, just above its tiles, and is hidden and locked with the layer. With the designer shut, a dropped image becomes a top-level Sprite entity as before.
- **Moving a parent moves what is under it.** Select's move and rotate, the arrow-key nudges, quarter turns and the align bar take every descendant along. A resize does not. Duplicate, array and Alt+drag put each copy beside the original, under the same parent and on the same layer. A marquee never picks the Level Map itself; a click on it, a double-click on open ground or the tree does. Paint's eraser removes what it covers but never the map.
- **Tiles into an entity.** With Select tiles (V), *Make entity* in the tool's options, Enter, right-click → *Make the N tiles an entity*, or *Make them an entity* on the inspector's card for the selected tiles (which also copies, cuts, deletes and deselects them) cuts the selected tiles out of their layer into a new child entity of the map, `Tiles_N`. It holds a small map of its own (the same grid and tilesets, one copy of the layer) and sits on the layer the tiles came from. The tiles draw and collide exactly where they were; staggered and hexagonal maps keep their stagger. It is one undo step, and is refused on a locked layer or one with parallax. The tile tools keep painting the Level Map, never a piece. Moving a piece while the game runs (a moving platform made of tiles) is not supported yet.
- **Tiled.** A `.tmx` / `.tmj` from the Assets dock imports into the scene or converts to a `.map.json`; a `.tsx` / `.tsj` converts to a tileset; *Export for Tiled…* writes any map out as `.tmx` or `.tmj` with its tilesets (a built-in tileset's picture as a `.png` beside its `.tsx`). Export writes tiles only, not the entities on the map. On import each object becomes an entity on its layer, made by a module's mapper or by the prefab its class names.
- **Double-clicking** empty ground while designing selects the Level Map.
- **The designer switch.** A module can bring a Level Designer of its own (its prefabs, tools, layers and grid; `providesLevelDesigner`). The switch in the designer's header picks one per scene, and the choice is saved with the scene.

---

## Tags

Tags are what cameras, triggers and systems find entities by, and in this editor you pick them rather than type them.

- **The tag list** lives in `assets/project/tags.json`: each tag's name, colour and description. The **Tags** dock shows every tag, who carries it, and which spawners give it. From there you can make a tag, recolour or describe it, select everything carrying it, or rename or delete it everywhere, with a preview first.
- **On an entity**, tags sit at the top of the inspector as chips. **Add** offers the project's tags, or makes a new one. A near duplicate (`Players` beside `player`) is refused.
- **Fields that point at an entity** — what a camera follows, what sets a trigger off — are one picker, with an Entity / Tag switch.
- **Spawn points** say what they spawn from the spawners the game passes to `JustGameEditorPlugin.register(spawners: …)`. A spawner also says what tags its entity carries, so `#player` counts as real before anything is spawned.
- **Typos show up** in the Problems dock, each with a one-click fix: a tag nobody declared, a spawn point with no spawner, a camera following a name nothing has. Pointing at a tag anywhere rings its entities in the viewport.

A module declares the tags its code relies on (`EditorModule.tags`). They are listed as built in, and cannot be renamed or deleted from the editor.

---

## Physics bodies

2-D and 3-D bodies are inspected alike: a rigid body (how it moves) and a collider (its shape), in the same groups, in the same words.

- **Body type** is the one switch for how a body moves: Static, Kinematic or Dynamic. The card shows only what applies — no mass on a static body, no bounciness on a sensor — and folds its rarely needed settings under Advanced. Hover any setting to read what it does. A mass of 0 is worked out from the collider, as the engine does.
- **Material**: pick a preset (Default, Character, Stone, Wood, Metal, Ice, Rubber, Bouncy, Sticky) or set Friction and Bounciness on their sliders; a preset is one undo step. A hit bounces as much as the less bouncy of the two bodies; the level map's tiles have none.
- **The collider** follows the entity's scale and can sit off its origin (Offset). *Match what is drawn* keeps it the shape of the sprite or shape on the entity. **Fit to visual** in the card's header matches it once to the circle, box, capsule or polygon drawn, or to the sprite's box. **Edit collider** (2-D) puts handles on it in the viewport: corners and sides of a box (Alt about its centre), a circle's edge, a capsule's ends, a polygon's or chain's points (○ between two adds one; Alt-click or Delete removes one) and a diamond that moves it. Esc finishes.
- **Characters.** A `CharacterBody2D` is inspected like 3-D's `CharacterBody3D`, and its shape is drawn in the viewport. A character that is also a rigid body, or has a collider, is a problem with a one-step fix.
- **Collision layers** work like tags. A body is on one of sixteen layers, picked by name — type a new name in the picker to make one. Its **Collides with** shows a chip per layer: click one to stop or start colliding with it; by default they follow the project's grid, and a ⚠ says when a layer you list does not collide back. The **Physics Layers** dock makes, recolours, describes, renames and deletes layers (deleting moves what is on one to another, in every scene, after a preview) and holds the grid of which pairs collide. Pointing at a layer anywhere rings its bodies in the viewport. It is all saved to `assets/project/physics.json`, which the game reads when `pubspec.yaml` ships it; a change reaches a running play-test.
- **While playing**, the card shows the body's velocity, speed, spin, whether it sleeps and what it stands on.
- **Problems** flags a body with no collider, a collider that does not match the shape drawn (with Fit to visual as the fix), unnamed layers, a body that collides with nothing, polygons the native physics would change, and an unshipped layer file. In 3-D: a body with no collider, a dynamic body with a shape only a static one can have, a character that is also a rigid body, a mesh or hull collider with no model, and a joint to nothing.

---

## Docks

The foot of the editor is a status strip and, above it, one tabbed panel (**F2** or Ctrl+` opens and shuts it). Each fact on the strip is a button to where it came from: errors to the Console, the frame rate to the Profiler. Tabs reorder, a right-click pops a dock out, maximises it or takes it off the bar, and **+** brings back any dock. The layout, each dock's filters and the popped-out windows are remembered.

| Dock | Key | What it shows |
|------|-----|---------------|
| Console | Ctrl+Shift+C | The log, the last session's too: search (text or `/regex/`), levels, sources, repeats folded, pause, export, and a line for the editor's commands. Clicking a line selects the entity it names |
| Assets | Ctrl+Shift+A | The project's files with thumbnails, filters by kind, drag to the viewport or onto a field, rename (references follow), duplicate, find references, delete (undoable) and each kind's conversions; package assets read-only |
| Timeline | Ctrl+Shift+T | The selected entity's timeline, or a `.timeline.json` |
| Profiler | Ctrl+Shift+P | Frame times against the target, and what each system took |
| World | Ctrl+Shift+W | The live entities, systems (with timings) and component types |
| Search | Ctrl+Shift+F | Finds by name, tag (`#tag`) or field (`Health.health < 3`) and selects what it finds |
| History | Ctrl+Shift+H | The undo stack; click a step to go back to it |
| Problems | Ctrl+Shift+E | What is wrong with the open scene, errors first, with fixes |
| Tags | | The project's tags ([above](#tags)) |
| Physics Layers | | The collision layers and grid ([above](#physics-bodies)) |
| Animator | | The selected entity's animator while the game runs |

A module adds docks of its own (`EditorModule.docks`).

---

## Keyboard shortcuts

Every command's keys can be changed in **Settings → Keyboard** (Ctrl+,); these are the defaults. F1 and F2 are the editor's own and are set with `register(toggleKey:, statusPanelToggleKey:)`.

**Anywhere** — these work even while typing in a field:

| Key | Action |
|-----|--------|
| `F1` | Show or hide the editor |
| `F2` | Open or shut the dock panel |
| `F3` | Open or close the Level Designer |
| `F4` | The game camera preview |
| `F5` / `Shift+F5` | Play or stop / restart |
| `F6` | Pause or resume |
| `F10` | Step one frame |
| `Ctrl+S` | Save the scene (keeping what is typed in a field) |
| `Ctrl+,` | Settings |
| `` Ctrl+` `` | Show or hide the dock panel |
| `Ctrl+Shift+C` `A` `T` `P` `W` `F` `H` `E` | Console, Assets, Timeline, Profiler, World, Search, History, Problems |
| `Ctrl+Alt+PgDn` / `PgUp` | Next / previous dock |
| `Ctrl+Shift+M` | Maximise the dock panel |

**Editing** — not while typing:

| Key | Action |
|-----|--------|
| `Ctrl+Z` / `Ctrl+Shift+Z`, `Ctrl+Y` | Undo / redo |
| `Ctrl+C` / `Ctrl+V` | Copy / paste entities |
| `Ctrl+D` | Duplicate |
| `Delete` | Delete the selection |
| `Q` `W` `E` `R` | All, Move, Scale, Rotate |
| `F` / `Shift+F` | Frame the selection / everything (3-D) |
| Numpad `1` `3` `7` (Ctrl for the other side) | Look from the front, right, above (3-D) |
| `X` | World or local gizmo (3-D) |

**In the Level Designer:**

| Key | Action |
|-----|--------|
| `B` `P` `I` `M` | Draw, Paint, Sample, Measure |
| `S` `G` `T` `D` `V` | Stamp, Fill, Terrain, Erase, Select tiles |
| Arrows (Shift for 1 unit) | Nudge the selection |
| `Z` / `Shift+Z` | Turn a quarter clockwise / back |
| `X` / `Y` | Flip horizontally / vertically |
| `F` / `Shift+F` | Frame the selection / everything |
| `H` / `Shift+H` / `Alt+H` | Hide / isolate / show everything |
| `L` / `Alt+L` | Lock / unlock everything |
| `Shift+R` | Replace with the active prefab |
| `Ctrl+A` | Select all |
| `[` / `]` | Smaller / larger brush |
| `Ctrl+1`…`9` / `1`…`9` | Store / recall a view bookmark |
| `Esc` | Cancel the gesture, or clear the selection |

With a tile tool in hand, X and Y mirror the brush and Z turns it, Ctrl+V puts copied tiles in it, and the right button picks tiles up; G cycles Fill's shape. With Select tiles, V cycles box, wand and same tile; Ctrl+C, Ctrl+X and Delete copy, cut and delete the tiles; Enter makes them an entity. A module's tools bring their own letters (the platformer kit's Path is K).

**Panels.** A panel with the focus keeps its keys from the shortcuts above (Ctrl+S and the rest of *Anywhere* still work): the scene tree ([above](#the-scene-tree)), the Scenes panel (arrows, Enter opens, F2, Ctrl+D, Delete, typing searches), the Timeline (Space plays, K keys, R records, M marks, `[` `]` set the work range, `,` `.` step a frame, Ctrl+Z its own undo) and the colour picker.

---

## Extending the editor

A game, a kit or a tool adds to the editor with an `EditorModule`, passed to `register(modules: …)`. A module builds on [`just_editor_core`](../just_editor_core/) — the module contract, the scope and its services, undo, the inspector's rows and the UI kit — and needs nothing else of the editor, so a kit depends on that package alone:

```yaml
dependencies:
  just_editor_core: ^0.1.0-dev.1
```

```dart
import 'package:just_editor_core/just_editor_core.dart';
```


```dart
class MyGameModule extends EditorModule {
  @override
  String get id => 'my_game';

  @override
  String get name => 'My Game';

  @override
  List<PrefabDefinition> get prefabs => [/* what the Level Designer places */];

  @override
  List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'mygame.icons',
      of: (entity) =>
          entity.hasComponent<CoinComponent>() ? Icons.monetization_on : null,
    ),
  ];
}
```

A module can bring prefabs and tools, overlays, snap providers and a grid to the Level Designer; docks, toolbar buttons, settings pages, theme presets and full-screen workspaces to the chrome; field editors, inspector sections and component extras to the inspector; scene-tree actions, row badges and icons; commands and key bindings; checks for Problems; kinds of file and actions on them for Assets; tags its code relies on; and, for 3-D, a view, markers, exact pick tests, viewport overlays, handles and prefab variants. The first module to answer wins where only one answer counts (an entity's icon), lowest `order` first; lists are added together. See [ARCHITECTURE.md](ARCHITECTURE.md#the-module-contract) for every member.

Everything a module contributes is rebuilt from the modules on every reload of the editor's registries, so nothing piles up across hot reloads. `onRegister` runs once; `onReassemble` after each hot reload.

The first-party modules:

| Module | Package | What it adds |
|--------|---------|--------------|
| `PlatformerModule` | `just_platformer_kit` | The platformer's prefabs and icons, and the Path tool |
| `ThirdPersonModule` | `just_third_person_kit` | The third-person kit's 3-D prefabs and markers |
| `GraphicsEditorModule` | `just_graphics_editor` | 3-D models (thumbnails, drop, cooking), lights, 3-D shapes and their handles |
| `UiEditorModule` | `just_ui_editor` | The game's screens (`assets/ui/*.ui.json`) and themes |
| `SpriteStudioModule` | `just_sprite_editor` | Sprite sheets, atlases and animator graphs |
| `InputEditorModule` | `just_input_editor` | The input actions asset |
| `AssetStoreModule` | `just_asset_store_editor` | The Asset Store window |
| `HexGridModule` | built in | A hexagonal grid for the Level Designer |

The editor's own tools arrive the same way: `BuiltInEditorModule` holds its field editors, commands, prefabs, workspaces and the rest, registered ahead of every other module, so a module replaces any of it by reusing an id.

A project made with `just create` lists the modules of the store items it has in a generated `lib/editor/store_modules.g.dart`.

---

## Hot reload and hot restart

The editor runs in a debug (JIT) build, so a hot reload (**r**) and a hot restart (**R**) work on the running editor.

A hot reload swaps the code but runs nothing again — not `main`, not a constructor, not a static initializer. So the overlay's `State.reassemble` calls `JustGameEditorPlugin.reassemble`, which in turn:

1. calls the app's `onReassemble` (`register(onReassemble: ...)`), for what its `main` did once: register its interface bindings, add systems declared since launch, hand over its spawners (`scope.spawners.value = ...`) and its modules (`plugin.syncModules(...)`);
2. puts the component definitions in place again (`EngineContext.refreshDefinitions`: the engine's, and each `RefreshableExtension`'s), so a field added to a component shows in the inspector and is saved;
3. rebuilds every registry from the built-ins and the modules (`EditorScope.reassemble`): docks, commands and keys, toolbar buttons, prefabs, inspector sections, validators, settings pages, theme presets;
4. reloads the Level Designer's tools, makes the built-in docks again, and re-checks the scene;
5. brings live components up to a definition that changed — one that cannot read a new field is made again from what it holds; one that can is kept, as undo holds it (not during a play-test: Stop restores through the new definitions) — and puts the systems back in priority order.

Each step stands alone: one that throws is logged in the Console, and the rest still run. The Console says what changed ("Hot reload: the editor is up to date. Changed: PatrolEnemyComponent.").

For this to work, write what is built from code as a getter, not a `static final` (which is built once and kept): component definitions, prefabs, workspaces, styles that read `EditorTheme`. `EditorModule.onRegister` runs once per module — loading files, installing into the engine; `onReassemble` runs after each reload. Tests in the engine and here fail on a `static final` definition or style.

Still a hot restart: a changed argument of a module or system that is already running, taking away an interface binding, and the engine's configuration. A hot restart starts the app afresh — the native physics, audio and gamepad plugins put themselves back as new, so it does not crash or leave the last session's sounds playing.

---

## Keeping the editor out of a release build

A profile or release (AOT) build of the game holds no editor:

- **The game's entry point never imports it** (`lib/main.dart` in the template; its `test/release_imports_test.dart` walks the import graph).
- **The editor's entry point is the game outside a debug build.** Make `main` one constant branch, so the compiler drops the other entirely — an early `return` is not enough, since code after it is still compiled in:

  ```dart
  Future<void> main() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kDebugMode) {
      await _runEditor(); // boot, register the plugin, runApp(editor)
    } else {
      runApp(const MyGame());
    }
  }
  ```

  `JustGameEditorPlugin.register` also returns null outside a debug build, and `JustGameEngineEditor` then renders a plain `GameWidget`.
- **The editor packages are dev dependencies**, so a Windows or Linux release build leaves out the native plugins only they bring (the Sprite Studio's file dialogs). macOS links every plugin whatever the build (flutter/flutter#163874). A package that is only a dev dependency also has its own assets left out, even under `flutter run`; none of the editor packages has any.
- **Check the build itself**: `just game build <platform>` builds and checks in one go; or run the template's `tool/check_release_build.dart <windows|linux|macos|web>` right after `flutter build <platform> --release`. It looks in the compiled snapshot for the editor's names and in the bundle for its plugins.

---

## Notes

- The editor needs a desktop: scenes, backups and logs are written through `dart:io` relative to the working directory, so start it from the project root. On a phone, a tablet or the web, `register` returns null; the template then offers the game instead.
- A Level Map exports to Tiled (`.tmx` / `.tmj`) with *Export for Tiled…*: its tile layers and tilesets, with a built-in tileset's picture written as a `.png` beside its `.tsx`. The entities on its layers are not exported.
- `just_game_engine` has no debugger panel of its own inside `GameWidget`; this package is the development-time overlay.
- The package is not published to pub.dev (`publish_to: none`); it reaches a project through the Asset Store.
