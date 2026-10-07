# Just Game Engine Editor - Quick Start Guide

## Install

Add as a `dev_dependency` so tree-shaking strips it from production builds:

```yaml
dev_dependencies:
  just_game_engine_editor:
    path: packages/just_game_engine_editor
```

## 1. Register the plugin and wrap your game widget

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

// Inside your widget build / initState:
final plugin = await JustGameEditorPlugin.register(engine: engine);

Widget gameView = GameWidget(engine: engine);
if (plugin != null) {
  gameView = JustGameEditorOverlay(plugin: plugin, gameChild: gameView);
}

return gameView;
```

`JustGameEditorPlugin.register()` returns `null` outside debug mode — production builds keep the plain `GameWidget` with no editor overhead.

## 2. Use the adapter shortcut (recommended)

`GameEditorAdapter` handles plugin creation, vsync ticking, and render overlay chaining automatically:

```dart
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

// Replace GameWidget with GameEditorAdapter during development:
return GameEditorAdapter(engine: engine);
```

Switch back to `GameWidget` for release or ship with `GameEditorAdapter` — it degrades to zero overhead in non-debug builds either way.

## 3. Register your components

A component is described **once, in the game**, as a `ComponentSchema`. That one description is what saves it, what loads it in the shipped game, and what the inspector edits. Register it at boot, in both entry points:

```dart
// lib/game/boot.dart — runs in the game and in the editor.
final healthSchema = ComponentSchema<MyHealthComponent>(
  id: 'my_health',
  type: 'MyHealthComponent',
  create: MyHealthComponent.new,
  fields: [
    SchemaField(
      name: 'maxHp',
      kind: FieldTypes.integer,
      min: 0,
      read: (c) => (c as MyHealthComponent).maxHp,
      write: (c, v) => (c as MyHealthComponent).maxHp = v as int,
    ),
    SchemaField(
      name: 'invincible',
      kind: FieldTypes.boolean,
      read: (c) => (c as MyHealthComponent).invincible,
      write: (c, v) => (c as MyHealthComponent).invincible = v as bool,
    ),
  ],
  // What the inspector shows. A few constants; the game ignores them.
  hints: const ComponentHints(
    name: 'Health',
    group: 'Gameplay',
    icon: Icons.favorite,
    fields: {
      'maxHp': FieldHint(label: 'Max HP', scrub: ScrubHint(integer: true)),
      'invincible': FieldHint(label: 'Invincible'),
    },
  ),
);

ComponentDefinitionRegistry.instance.register(healthSchema);
```

That is the whole description: the inspector's section for `MyHealthComponent` is built from it. An `EditorModule` is where prefabs, viewport tools, overlays and — if you add your own `FieldType` — its editor go:

```dart
// lib/main_editor.dart only. Never imported by lib/main.dart.
class MyGameModule extends EditorModule {
  @override
  String get id => 'my_game';

  @override
  String get name => 'My Game';

  @override
  List<PrefabDefinition> get prefabs => [/* ... */];
}

final plugin = await JustGameEditorPlugin.register(
  engine: engine,
  modules: [MyGameModule()],
);
```

Everything a module contributes lives in the plugin's `EditorScope` and is rebuilt from the modules on every hot reload, so an edited module takes effect without restarting. A component with no registered schema is not shown and is **left out of the save**, with a warning in the log — the shipped game could not have loaded it.

## 4. Open the editor

Press **F1** at runtime to toggle the editor overlay. The game viewport shifts left; the right panel shows the scene tree, inspector, and scene picker.

With no scene open, the viewport shows a start card rather than the game: New scene, Reopen the scene last worked on, the steps to a saved level with their keys, and the tools that need no scene. The Scenes list on the right searches, sorts (play order, name, recently opened) and reorders: dragging a scene's number, or Alt+↑/↓, sets the order the game plays scenes in (`scenes.json`); the first is where the game starts.

See the main [README](README.md) for keyboard shortcuts and the scene file format, and [ARCHITECTURE.md](ARCHITECTURE.md) for how the package is structured internally.

## 5. Build a level

Open the Level Designer with the map icon on the play toolbar. At the top right of the level, All, Move, Scale and Rotate (Q, W, E, R) are the select tool; the other tools hang below them under SELECT, SHAPES, TILES and MEASURE, each with its key on the button. The settings for the tool in hand are at the left of the status bar along the bottom.

1. **Ground.** Press **S** and pick a tile in TILESET. The engine's built-in *Basic shapes* (blocks, slopes, a one-way plank) are always listed first; picking one adds that tileset to the map and, the first time, makes the scene's **Level Map** (a scene has one) with a `Ground` layer whose tiles collide. Or drop your own `.tileset.json` from the Assets dock onto the level, or add one with the **+** in TILESET. Then paint. **G** fills, **T** paints terrain, **D** erases and **W** selects tiles. Right-drag picks tiles up into the brush.
2. **Platforms, scenery, things that act.** Pick a prefab in PREFABS, then drag one out with **B** or paint several with **P**. Each is an entity, placed under the Level Map on one of its layers. The status bar says where it will go, e.g. `→ Level Map ▸ Ground`. If the scene has no map yet, the first thing placed makes it, and one Ctrl+Z takes both away.
3. **Tiles as one thing.** Select painted tiles with **W** and press Enter (or right-click them, or use *Make them an entity* in the inspector). They are cut out into an entity of their own under the map, drawn and colliding exactly where they were.
4. **Arrange.** LAYERS lists the depths front first. Under each depth are the map's layers, each saying how many entities are on it, and the entities at that depth that are on no map layer. **+** adds a map layer at a depth, and each layer has a switch for whether its tiles collide. **Q** selects and moves; moving an entity moves what is under it. The scene tree lists the Level Map's layers under it and, under each layer, the entities on it. Drag an entity onto a layer row to put it there.
5. **Save** with Ctrl+S (the scene, and the map's `.map.json` if it is kept in one) and press Play.

To get back to painting later, double-click *Level Map* in the scene tree. The designer opens on it with the Stamp in hand.

## 6. Cameras

Register the engine's camera systems where you register your others:

```dart
registerCameraSystems(engine.world, engine.cameraSystem);
```

In the Level Designer, place a **Virtual camera** from the *Camera* palette group and name what it follows (an entity, or a tag your game gives the player it spawns). Add stages from *Add Component → Camera*: Framing, Confiner (name a **Camera bounds** entity), Noise, Impulse Listener. A **Camera zone** is a shot of its own while its target is inside. The overlay draws every camera's frame; select one to see its dead and soft zones. The picture-in-picture shows what the live camera frames while you work, and **Solo camera** in the scene tree looks through one shot whatever its priority. Press Play to see blends and damping; Stop returns your view.

