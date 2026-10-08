# Just Game Engine Editor

A developer-only runtime level editor overlay for [`just_game_engine`](../just_game_engine/). It runs in a debug (JIT) build — hot reload and hot restart included, live ECS state edits, and scene authoring — and a profile or release (AOT) build of the game holds none of it.

## 📚 Documentation

- **[Quick Start Guide](QUICKSTART.md)** — install the package, wrap your game widget, and register custom components
- **[Architecture](ARCHITECTURE.md)** — package layout and how the core/UI/integration layers fit together

---

## Features

- **Transform gizmos** — All (Q), Move (W), Scale (E) and Rotate (R), one at a time, picked from a floating toolbar at the top right of the viewport, in the editor and the Level Designer alike
- **Settings** — the gear at the foot of the viewport (or Ctrl+,): the accent — it recolours everything, the sprite and input editors included — density, corners, motion, the grid and how the viewport draws, snapping steps, undo depth, what asks first, autosave and backups, reopening where you left off, the play-test, the Console and how chatty messages are, the target frame rate, every command's keys, and each module's own page; all searchable, and exported or imported as one file
- **Quick snapping** — a magnet and a grid button on the settings gear while editing: one snap switch for the viewport and the Level Designer; right-click the magnet for the move step (its own, or the grid's) and the grid button for the grid's size; the Snapping page in the settings has every step
- **Accessibility** — text size and bolder text, high contrast, colour-blind safe status colours, reduced motion, longer timings, bigger targets and always-visible keyboard focus
- **One look throughout** — a kit of buttons, fields, toolbars and dialogs (`lib/src/ui/kit/`, exported) that follows the settings, for a module's docks and panels too
- **Scene tree** — hierarchical entity list with reparenting, renaming, and multi-select; the Level Map opens to its layers, and each layer to the entities on it
- **Entity inspector** — property editor generated from each component's runtime definition and its hints
- **Physics bodies** — one Body type, only the settings that apply, material presets, Fit to visual, collider handles in the viewport, named collision layers with a Physics Layers dock, and a live readout while playing ([below](#physics-bodies))
- **Level Designer** — a grouped tool strip with each tool's settings in the status bar, its panel as the right panel's Level tab, and the scene's **Level Map**: its tiles, and everything placed in the designer as an entity under the map, on one of its layers
- **Scene I/O** — saves a `.level.dart` (spawnable entity code) + `.scene.json` (editor sidecar) pair
- **Copy / paste entities** — clipboard-based entity duplication
- **Dock panels** — console, assets, profiler, world, problems, history, search, and a **Timeline**: reusable timelines that animate any component field, with a dope sheet, curve editor, record mode and viewport motion paths
- **Workspaces** — the Tileset Editor, and any a module brings, open over the editor in one frame (`WorkspaceHeader`): the file, whether it is saved, Save, Undo, Redo, full screen and close. A workspace with unsaved work is asked before another opens over it
- **The in-game interface is a module** — the editor has no interface editor of its own. Add `UiEditorModule()` from the `just_ui_editor` package to the modules for the game's screens (`assets/ui/*.ui.json`) and themes, their checks in Problems, and a Text prefab in every Level Designer
- **Hot reload, all the way** — a hot reload (r) brings the registries, the modules' contributions, the component definitions, the built-in docks and the palette up to the code as it now is, and a hot restart (R) starts clean ([below](#hot-reload-and-hot-restart))
- **Debug only** — the editor runs in a debug (JIT) build; a profile or release (AOT) build of the game holds none of it ([below](#keeping-the-editor-out-of-a-release-build))

---

## Install

Add it as a `dev_dependency`, beside the modules you use: only the developer entry point imports them, and a release build then also leaves out the native plugins only they bring (on Windows and Linux; see [below](#keeping-the-editor-out-of-a-release-build)):

```yaml
dev_dependencies:
  just_game_engine_editor:
    path: packages/just_game_engine_editor
```

See the [Quick Start Guide](QUICKSTART.md) for wiring up the plugin, the `JustGameEngineEditor` widget, and registering custom components. Press **F1** at runtime to toggle the editor overlay.

---

## The scene tree

The tree is where a scene's *shape* is edited, and everything it does goes
through the editor's one undo stack — re-parenting, reordering, renaming,
grouping and deleting alike.

- **Selecting.** A click selects at once. `Ctrl` adds to the selection,
  `Shift` takes a range. Clicking the name of a row that is **already**
  selected renames it; **double-clicking** focuses the entity in the
  viewport (the Level Map opens the Level Designer instead).
- **Moving things.** Hold a row for a moment to pick it up. A drag carries
  the whole selection when the row is part of it; the line between two rows
  means *between*, the body of a row means *inside*, and a drag resting on a
  shut row opens it. Dropping past the last row moves to the top level.
- **What a row shows.** Its icon (a module's, if one claims the entity), a
  colour label if you have marked it, and at the end whatever the editor and
  the modules have to add: how many scene checks it fails, whether a timeline
  or an animator moves it, whether a camera is live.
- **Hiding and switching off are different things.** The eye hides a row in
  the viewport and is the editor's business alone — nothing about it is saved
  and the game never sees it. **Enabled**, in the inspector, is saved with the
  scene as `"enabled": false` and the game honours it; a switched-off entity
  stays in the tree, struck through. *Isolate* in the context menu hides
  everything except the selection and what is under it.
- **Finding things.** The search box matches a name *or* a component type, so
  "sprite" finds everything drawn. The chips under it filter by component,
  tag, layer, or "has problems", offering only what the open scene actually
  contains. A match keeps its parents, drawn faded, so you can still see where
  it lives.
- **While playing.** Entities the running game spawned are listed under a
  greyed *Runtime* divider and are never saved.
- **The Level Map's rows.** The *Level Map* opens to its layers, front
  first, each shut until you open it, and each layer to the entities on
  it. Those are ordinary entity rows: they select, drag and rename, and
  have the usual menu. Children of the map on none of its layers come
  after the layer rows. Selecting an entity on a layer opens that layer.
  A layer row says how many entities are on it. Click it to paint on it,
  double-click to rename it. Its eye and lock are the map's own, saved
  with it and undoable, and they hide and lock what is on the layer too.
  Its menu renames the layer, or deletes it with everything on it.
- **Putting entities on a layer.** Drop entities on a layer row and they
  go on that layer. Drop them beside an entity that is on a layer and they
  join its layer. Drag them out of the map and they leave its layers. Each
  is one undo step. Layer rows themselves do not drag: a map's layers are
  arranged in the Level Designer's LAYERS panel. Search matches entities
  and layer names; the arrow keys walk entities and skip layer rows.
  **Double-clicking** the *Level Map* opens the Level Designer on it, with
  the Stamp in hand (unless a tile tool already is) and the view on what is
  painted.

Which rows are open and how they are coloured are saved in the scene file's
`editor` section, by name, and are never read by the game.

### Teaching it about your game

A module says what its entities look like:

```dart
class MyModule extends EditorModule {
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

The first module to answer wins, lowest `order` asked first; the editor falls
back to its own icons. `rowDecorations` adds a badge at the end of a row and
`sceneTreeActions` adds an entry to its context menu.

---

### On the level itself

Right-clicking an entity in the viewport opens the same menu its row does —
focus, duplicate, delete, copy, group, hide, lock, isolate — and right-clicking
bare level offers *Paste here* and *New entity here*, which put the entity
where the pointer is rather than at the camera. While tiles are selected
with Select tiles (V), right-click opens their own menu instead: *Make the
N tiles an entity*, *Copy tiles*, *Cut tiles*, *Delete tiles*, *Select
none*. Otherwise a tile tool keeps the plain right button for picking
tiles up, so open the menu with **Shift**+right-click.

---

## The Level Designer

The map icon on the play toolbar opens it. Along the bottom of the window,
from the bottom up, are the docks' status strip, any dock panel that is
open, and the designer's own status bar: the tool's options at its left,
then snapping, the grid, overlay switches, module controls, the cell under
the pointer while a tile tool is in hand, and what the tool last said. Lists, the tool strip and the scene
tree always show their scroll bars.

- **The tool strip** floats at the top right of the level, under the
  transform column, and scrolls when the window is short. It groups tools
  under captions, each button with its key in the corner. SELECT: a
  module's own such as the platformer kit's Path (K), and Track (a dolly
  camera's track) — the select tool itself is the transform column. SHAPES: Draw (B),
  Paint (P), Sample (I). TILES: Stamp (S), Fill (G), Terrain (T), Erase (D),
  Select tiles (V). MEASURE: Measure (M). A module adds a group with
  `EditorModule.toolGroups`.
- **All, Move, Scale, Rotate (Q, W, E, R)** are a column at the top right
  of the viewport (`TransformToolbar`, in a `FloatingToolFrame`), in the
  editor and the designer; in the designer they are the select tool. All
  is the default and the gizmo as it always was. The mode is
  `scope.view.transformMode`; `TransformModes.forEntities` says what a
  selection can take (a level map only moves; a lone piece of one also
  turns, its tiles a quarter at a time, in the designer; tiles picked with
  Select tiles move and turn) and `TransformModes.shown` falls back to
  All, which leaves off what does not apply. The gizmos
  are drawn and hit-tested by `TransformGizmo` for the editor
  (`GizmoPainter`, `GizmoHitTester`) and the designer
  (`SelectionHandlesOverlay`, `SelectTool`, `TileSelectTool`) alike. The
  commands are `editor.transform.all/move/scale/rotate`; Replace moved to
  Shift+R.
- **The tool's options**, at the left of the designer's status bar along
  the bottom, are the settings of the tool in hand. There is no options
  bar at the top. For Paint, Brush / Rect / Erase / Fill and the brush
  size. For the tile tools, the layer being painted, Random, the fill
  shape, the eraser's size, the select mode (and, for Select tiles, *Make
  entity*), and switches to highlight the layer and show collision. For
  Draw and Paint, the prefab and where it will go: `→ Level Map ▸ Ground`,
  `→ Level Map ▸ a new Background layer`, `→ a new Level Map`. A tool puts
  its own there with `LevelToolHandler.buildOptions`.
- **TILESET** is one scrolling list with a section per tileset. Each
  section has a header (a chevron that folds it away, its name, and a ⋮
  menu with *Edit tileset…* and *Remove from the map*) and its tiles below
  at full height. The Tiles / Terrains switch and **+** (add a tileset) are
  at the top, the zoom at the bottom. The engine's built-in **Basic
  shapes** tileset is always listed first, marked "built in · not on the
  map" until you use it. Picking one of its tiles adds it to the map, and
  makes the Level Map in a scene with none, in one undo step. It has 24
  tiles of 32 px: a block, halves, quarters, a small block, a one-way
  plank, 45° slopes (floor and ceiling), 22.5° floor slopes, rounded
  corners, a circle, a triangle and a diamond, each colliding as drawn.
  A built-in tileset does not open in the Tileset Editor.
- **LAYERS** is one list, grouped by depth, front first: Foreground, Main,
  Background, and any other the scene uses. Under each depth are the Level
  Map's layers that draw there, and a row for the entities at that depth
  that are on no map layer. A map layer's eye and lock are saved with the
  map and hide and lock what is on it too. Its switch says whether its
  tiles collide. It shows how many entities are on it, and has a button
  that moves the selection onto it. Its expander holds opacity, tint,
  depth, z order, parallax, offset and class. The entities row's eye and
  lock are the editor's alone, and it can move the selection to its depth
  (one undo step), leaving alone anything on a map layer. **+** on a depth
  adds a map layer there. The toolbar has the map's settings (grid, tile
  size, stagger, hex side), duplicate and delete (both take what is on the
  layer too, one undo step each), raise and lower. Position, rotation and
  scale are in the inspector.
- **The Level Map.** A scene has one map, the entity *Level Map* (its
  component shows as *Map*). You do not place it. The first tile painted,
  thing placed or tileset dropped makes it, as does *Create Level Map* in
  LAYERS or TILESET, and one Ctrl+Z takes it away with what was drawn. It
  is kept in the scene, or in a `.map.json` of its own (older
  `.tilemap.json` files still load). A dropped `.map.json` becomes the Level
  Map, or replaces an empty one. It is refused if the scene's map already
  has something on it, and so is a Tiled *Import into this scene*. A second
  map in a scene is a warning in Problems; a piece of tiles cut out of it
  (below) is not.
- **Everything placed goes under the map.** Draw, Paint, a point prefab
  and an image or sprite dropped from Assets make entities, as each
  prefab's `build` says. Each is a child of the Level Map, on one of its
  layers (`LayerComponent.mapLayer`): the layer being painted if it draws
  at the depth you are placing at, else the frontmost layer at that depth,
  else a new layer named after the depth. The layer, and the map itself for
  the first thing placed, are made in the same undo step. A prefab can
  insist on a depth with `PrefabDefinition.depth` (the platformer kit's
  Decoration goes to the background). A locked or hidden layer refuses,
  and the status bar says why. On a map layer an entity draws at the
  layer's depth, just above its tiles, and is hidden and locked with the
  layer. With the designer shut, a dropped image becomes a top-level
  Sprite entity as before.
- **Moving a parent moves what is under it.** Select's move and rotate,
  the arrow-key nudges, quarter turns and the align bar take every
  descendant along. A resize does not. Duplicate, array and
  Alt+drag put each copy beside the original, under the same parent and on
  the same layer. A marquee never picks the Level Map itself; a click on
  it, a double-click on open ground or the tree does. Paint's eraser
  removes what it covers but never the map.
- **Tiles into an entity.** With Select tiles (V), *Make entity* in the
  tool's options, Enter, right-click → *Make the N tiles an entity*, or
  *Make them an entity* on the inspector's card for the selected tiles
  (which also copies, cuts, deletes and deselects them) cuts the selected
  tiles out of their layer into a new
  child entity of the map, `Tiles_N`. It holds a small map of its own (the
  same grid and tilesets, one copy of the layer) and sits on the layer the
  tiles came from. The tiles draw and collide exactly where they were;
  staggered and hexagonal maps keep their stagger. It is one undo step, and
  is refused on a locked layer or one with parallax. The tile tools keep
  painting the Level Map, never a piece. Moving a piece while the game
  runs (a moving platform made of tiles) is not supported yet.
- **Double-clicking** empty ground while designing selects the Level Map.

---

## Tags

Tags are what cameras, triggers and systems find entities by, and in this
editor you pick them rather than type them.

- **The tag list** lives in `assets/project/tags.json`: each tag's name,
  colour and description. The **Tags** dock shows every tag, who carries it,
  and which spawners give it. From there you can make a tag, recolour or
  describe it, select everything carrying it, or rename or delete it
  everywhere, with a preview first.
- **On an entity**, tags sit at the top of the inspector as chips. **Add**
  offers the project's tags, or makes a new one. A near duplicate
  (`Players` beside `player`) is refused.
- **Fields that point at an entity** — what a camera follows, what sets a
  trigger off — are one picker, with an Entity / Tag switch.
- **Spawn points** say what they spawn from the spawners the game passes to
  `JustGameEditorPlugin.register(spawners: …)`. A spawner also says what
  tags its entity carries, so `#player` counts as real before anything is
  spawned.
- **Typos show up** in the Problems dock, each with a one-click fix: a tag
  nobody declared, a spawn point with no spawner, a camera following a name
  nothing has. Pointing at a tag anywhere rings its entities in the
  viewport.

A module declares the tags its code relies on (`EditorModule.tags`). They
are listed as built in, and cannot be renamed or deleted from the editor.

---

## Physics bodies

- **Body type** is the one switch for how a body moves: Static, Kinematic
  or Dynamic. The card shows only what applies — no mass on a static body,
  no bounciness on a sensor — and folds its rarely needed settings under
  Advanced. Hover any setting to read what it does.
- **Material**: pick a preset (Character, Stone, Ice, Rubber, Bouncy …) or
  set Friction and Bounciness on their sliders. A hit bounces as much as
  the less bouncy of the two bodies; the level map's tiles have none.
- **The collider** follows the entity's scale and can sit off its origin
  (Offset). **Fit to visual** in the card's header matches it to the circle,
  box, capsule or polygon drawn, or to the sprite's box. **Edit collider**
  puts handles on it in the viewport: corners and sides of a box (Alt about
  its centre), a circle's edge, a capsule's ends, a polygon's or chain's
  points (○ between two adds one; Alt-click or Delete removes one) and a
  diamond that moves it. Esc finishes.
- **Collision layers** work like tags. A body is on one of sixteen
  layers, picked by name — type a new name in the picker to make one. Its
  **Collides with** shows a chip per layer: click one to stop or start
  colliding with it; by default they follow the project's grid, and a ⚠
  says when a layer you list does not collide back. The **Physics Layers**
  dock makes, recolours, describes, renames and deletes layers (deleting
  moves what is on one to another, in every scene, after a preview) and
  holds the grid of which pairs collide. Pointing at a layer anywhere rings
  its bodies in the viewport. It is all saved to
  `assets/project/physics.json`, which the game reads when `pubspec.yaml`
  ships it.
- **While playing**, the card shows the body's velocity, spin, whether it
  sleeps or stands on something.
- **Problems** flags a collider that does not match the shape drawn (with
  Fit to visual as the fix), unnamed layers, a body that collides with
  nothing, polygons the native physics would change, and an unshipped
  layer file.

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `F1` | Toggle editor visibility |
| `F2` | Toggle compact status dock (editor hidden) |
| `Ctrl+C` | Copy selected entity |
| `Ctrl+V` | Paste entity at camera centre |
| `Ctrl+S` | Save scene |
| `F2` / `Enter` | Rename the selected row in the scene tree |
| `↑` `↓` `←` `→` | Walk the scene tree |
| `Alt+↑` / `Alt+↓` | Move a row among its siblings |
| `Ctrl+G` / `Ctrl+Shift+G` | Group / ungroup the selection |

Keyboard input is automatically routed between the game and the editor based on which panel has focus.

---

## Scene File Format

Saving a scene (`Ctrl+S`) writes two files under `lib/game/scenes/{name}/`:

```
lib/game/scenes/level_01/
  level_01.level.dart    ← generated Dart code; call build(world) to spawn entities
  level_01.data.dart     ← level metadata (bounds, player start, etc.)
  level_01.scene.json    ← editor sidecar; not hand-edited
```

Load a saved scene at runtime:

```dart
await plugin.openScene('level_01');
```

The `.scene.json` sidecar rehydrates the entity hierarchy and editor-only state; `.level.dart` is what ships in production.

---

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full package layout — the `EditorScope`, the definition-driven inspector and the module contract are described there.

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
- **Check the build itself**: the template's `tool/check_release_build.dart --platform <windows|linux|macos|web>`, run right after `flutter build <platform> --release`, looks in the compiled snapshot for the editor's names and in the bundle for its plugins.

---

## Notes

- Scene file I/O (`SceneStore`) uses `dart:io` and is desktop/native only. Web is unsupported.
- The serialization service outputs JSON drafts. A Level Map exports to Tiled (`.tmx` / `.tmj`) with *Export for Tiled…*: its tile layers and tilesets, with a built-in tileset's picture written as a `.png` beside its `.tsx`. The entities on its layers are not exported.
- `just_game_engine` no longer embeds a debugger panel inside `GameWidget`; this package provides the dedicated development-time overlay.
- A scene can name a component nothing registered can read — a module left out this session, or one that moved to another package. The editor keeps it as the file had it and saves it back unchanged (`UnknownComponents`), lists it as an error in Problems and shows a card for it in the inspector. It no longer drops it.
- The package is published to `none` (internal monorepo only).
