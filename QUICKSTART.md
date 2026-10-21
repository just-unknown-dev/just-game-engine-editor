# Just Game Engine Editor - Quick Start Guide

From an empty `just_game_engine` game to a level saved by the editor. On macOS read Cmd wherever this guide says Ctrl (Cmd+S, Cmd+Z).

## Install

The editor is a dev dependency: only your editor entry point imports it, so it never ships, and a release build also leaves out the native plugins only the editor brings.

```bash
flutter pub add --dev just_game_engine_editor
```

A project made with `just create` has it already, with its editor entry point.

The editor edits the project's files, so it runs in a debug build on Windows, macOS or Linux, started from the project folder. On macOS, set `com.apple.security.app-sandbox` to `false` in `macos/Runner/DebugProfile.entitlements`: a sandboxed app cannot write the project.

## 1. An editor entry point

Keep the game's `lib/main.dart` free of the editor, and give the editor an entry point of its own, `lib/main_editor.dart`, run with `flutter run -t lib/main_editor.dart -d windows` (or `macos`, `linux`):

```dart
// The editor is a dev dependency, imported by this entry point alone.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'main.dart' show MyGame; // the game, as lib/main.dart runs it

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // kDebugMode is a compile-time constant: a profile or release build keeps
  // only the else branch, so it holds no editor.
  if (kDebugMode) {
    await _runEditor();
  } else {
    runApp(const MyGame());
  }
}

Future<void> _runEditor() async {
  final engine = Engine();
  await engine.initialize(); // boot the game's world here, as main.dart does
  final plugin = await JustGameEditorPlugin.register(
    engine: engine,
    modules: [MyGameModule()], // see 3.
    onReassemble: (plugin) => rewire(engine, plugin), // see 2.
  );
  engine.start();
  runApp(
    MaterialApp(
      home: JustGameEngineEditor(engine: engine, plugin: plugin),
    ),
  );
}
```

`JustGameEngineEditor` registers the plugin with the engine and lays the editor over a `GameWidget`; with a null plugin — not a debug build, or not a desktop (`JustGameEditorPlugin.supportsPlatform`) — it is the plain `GameWidget`. Because `kDebugMode` is a constant, the compiler keeps one branch of that `if` and drops the other: a release build of this file holds no editor. An early `if (!kDebugMode) { ...; return; }` does not do the same: code after a `return` is still compiled in.

The `ignore_for_file` line is there because `flutter_lints` reports a `lib/` import of a package that is only a dev dependency.

## 2. Hot reload

A hot reload (**r**) runs nothing again — not `main`, not a constructor. The editor brings itself and your modules up to date; what your `main` handed it from code, do again in `onReassemble`:

```dart
void rewire(Engine engine, JustGameEditorPlugin plugin) {
  plugin.syncModules([MyGameModule()]); // a module added since launch joins
  plugin.scope.spawners.value = mySpawners; // read at the next Play
}
```

Write what is built from code as a getter, not a `static final`: component definitions, prefabs, styles. Register your components from an engine extension that is a `RefreshableExtension` (below), and a field added to a component shows in the inspector after **r**. See the README's *Hot reload and hot restart*.

## 3. Register your components

A component is described **once, in the game**, by a `ComponentDefinition`. That one description is what saves it, what loads it in the shipped game, and what the inspector edits:

```dart
// lib/game/health.dart — the game's own code, in both entry points.
class MyHealthComponent extends Component {
  int maxHp = 3;
  bool invincible = false;
}

// A getter, so a hot reload builds it again from the code.
ComponentDefinition<MyHealthComponent> get myHealthDefinition =>
    ComponentDefinition(
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
      // What the inspector shows. The game ignores it.
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

// Registers the game's components on the engine it is given, and again,
// as the code now makes them, after a hot reload.
class MyGameExtension implements RefreshableExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) =>
      context.definitions.register(myHealthDefinition);

  @override
  void refresh(EngineContext context) =>
      context.definitions.refresh([myHealthDefinition]);
}

// Each engine has its own definitions: give the extension to the one the
// game runs, in both entry points.
final engine = Engine(
  config: const EngineConfig(extensions: [MyGameExtension()]),
);
```

That is the whole description: the inspector's section for `MyHealthComponent` is built from it. (The engine has a `HealthComponent` of its own; a game's component needs a type name of its own.) A component with no registered definition is not shown and is **left out of the save**, with a warning in the log — the shipped game could not have loaded it.

An `EditorModule` is where the editor's side of your game goes: prefabs, viewport tools, overlays, icons, checks and — for a `FieldType` of your own — its inspector editor. It lives in the editor entry point (or a file only it imports), never in `lib/main.dart`'s imports:

```dart
class MyGameModule extends EditorModule {
  @override
  String get id => 'my_game';

  @override
  String get name => 'My Game';

  // In every Level Designer, beside the editor's own shapes.
  @override
  List<PrefabDefinition> get sharedPrefabs => [/* PrefabDefinition(...) */];
}
```

Everything a module contributes lives in the plugin's `EditorScope` and is rebuilt from the modules on every hot reload, so an edited module takes effect without restarting. Its `onRegister` runs once; put what must be done again after a reload in `onReassemble`. A module whose prefabs are in `prefabs` rather than `sharedPrefabs` is a Level Designer of its own, picked in the designer switch. The `just_editor_core` package has [a complete small module](https://github.com/just-unknown-dev/just-editor-core/blob/main/example/example.dart): a prefab and a field editor.

## 4. Open the editor

Press **F1** at runtime to show or hide the editor. The game viewport shifts left; the right panel shows the scene tree, the inspector and the Scenes list.

With no scene open, the viewport shows a start card rather than the game: New scene, Reopen the scene last worked on, the steps to a saved level with their keys, and the tools that need no scene. The Scenes list on the right searches, sorts (play order, name, recently opened) and reorders: dragging a scene's number, or Alt+↑/↓, sets the order the game plays scenes in (`scenes.json`); the first is where the game starts.

See the [README](https://github.com/just-unknown-dev/just-game-engine-editor/blob/main/README.md) for the keyboard shortcuts and the scene file, and [ARCHITECTURE.md](https://github.com/just-unknown-dev/just-game-engine-editor/blob/main/ARCHITECTURE.md) for how the package is put together.

## 5. Build a level

Open the Level Designer with **F3** or the map icon on the play toolbar. At the top right of the level, All, Move, Scale and Rotate (Q, W, E, R) are the select tool; the other tools hang below them under SELECT, SHAPES, TILES and MEASURE, each with its key on the button. The settings for the tool in hand are at the left of the status bar along the bottom.

1. **Ground.** Press **S** and pick a tile in TILESET. The engine's built-in *Basic shapes* (blocks, slopes, a one-way plank) are always listed first; picking one adds that tileset to the map and, the first time, makes the scene's **Level Map** (a scene has one) with a `Ground` layer whose tiles collide. Or drop your own `.tileset.json` from the Assets dock onto the level, or add one with the **+** in TILESET. Then paint. **G** fills, **T** paints terrain, **D** erases and **V** selects tiles. Right-drag picks tiles up into the brush.
2. **Platforms, scenery, things that act.** Pick a prefab in PREFABS, then drag one out with **B** or paint several with **P**. Each is an entity, placed under the Level Map on one of its layers. The status bar says where it will go, e.g. `→ Level Map ▸ Ground`. If the scene has no map yet, the first thing placed makes it, and one Ctrl+Z takes both away.
3. **Tiles as one thing.** Select painted tiles with **V** and press Enter (or right-click them, or use *Make them an entity* in the inspector). They are cut out into an entity of their own under the map, drawn and colliding exactly where they were.
4. **Arrange.** LAYERS lists the depths front first. Under each depth are the map's layers, each saying how many entities are on it, and the entities at that depth that are on no map layer. **+** adds a map layer at a depth, and each layer has a switch for whether its tiles collide. **Q** selects and moves; moving an entity moves what is under it. The scene tree lists the Level Map's layers under it and, under each layer, the entities on it. Drag an entity onto a layer row to put it there.
5. **Save** with Ctrl+S (the scene, and the map's `.map.json` if it is kept in one) and press Play (F5).

To get back to painting later, double-click *Level Map* in the scene tree. The designer opens on it with the Stamp in hand.

## 6. Cameras

Register the engine's camera systems where you register your others:

```dart
registerCameraSystems(engine.world, engine.cameraSystem);
```

In the Level Designer, place a **Virtual camera** from the *Camera* palette group and name what it follows (an entity, or a tag your game gives the player it spawns). Add stages from *Add Component → Camera*: Framing, Confiner (name a **Camera bounds** entity), Noise, Impulse Listener. A **Camera zone** is a shot of its own while its target is inside. The overlay draws every camera's frame; select one to see its dead and soft zones. The picture-in-picture (F4) shows what the live camera frames while you work, and **Solo camera** in the scene tree looks through one shot whatever its priority. Press Play to see blends and damping; Stop returns your view.
