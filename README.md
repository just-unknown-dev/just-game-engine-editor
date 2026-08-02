# Just Game Engine Editor

A developer-only runtime level editor overlay for [`just_game_engine`](../just_game_engine/). Designed for JIT/debug workflows — hot reload, live ECS state edits, and scene authoring — with zero runtime cost in production builds.

---

## Features

- **Transform gizmos** — on-canvas translate, rotate, and scale handles with axis constraints and grid snapping
- **Scene tree** — hierarchical entity list with reparenting, renaming, and multi-select
- **Entity inspector** — dynamic property editor generated from registered component descriptors
- **Scene I/O** — saves a `.level.dart` (spawnable entity code) + `.scene.json` (editor sidecar) pair
- **Copy / paste entities** — clipboard-based entity duplication
- **Dock panels** — runtime logs, performance metrics, asset browser, and keyframe timeline
- **Hot-reload safe** — component descriptors refresh on `reassemble()` without restarting the app
- **Debug-gated** — all editor code is stripped in release/AOT builds via `kDebugMode`

---

## Install

Add as a `dev_dependency` so tree-shaking strips it from production builds:

```yaml
dev_dependencies:
  just_game_engine_editor:
    path: packages/just_game_engine_editor
```

---

## Quick Start

### 1. Register the plugin and wrap your game widget

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

### 2. Use the adapter shortcut (recommended)

`GameEditorAdapter` handles plugin creation, vsync ticking, and render overlay chaining automatically:

```dart
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

// Replace GameWidget with GameEditorAdapter during development:
return GameEditorAdapter(engine: engine);
```

Switch back to `GameWidget` for release or ship with `GameEditorAdapter` — it degrades to zero overhead in non-debug builds either way.

### 3. Register custom components

Call `registerProjectComponents` once (before the plugin initialises) so the inspector can generate UI for your game-specific components:

```dart
JustGameEditorPlugin.registerProjectComponents((registry) {
  registry.register<MyHealthComponent>(
    name: 'Health',
    category: 'Gameplay',
    factory: () => MyHealthComponent(),
    descriptors: [
      IntFieldDescriptor('maxHp', getter: (c) => c.maxHp, setter: (c, v) => c.maxHp = v),
      BoolFieldDescriptor('invincible', getter: (c) => c.invincible, setter: (c, v) => c.invincible = v),
    ],
  );
});
```

This registration survives hot-reload; new descriptors appear in the inspector without restarting the app.

### 4. Open the editor

Press **F1** at runtime to toggle the editor overlay. The game viewport shifts left; the right panel shows the scene tree, inspector, and scene picker.

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `F1` | Toggle editor visibility |
| `F2` | Toggle compact status dock (editor hidden) |
| `Ctrl+C` | Copy selected entity |
| `Ctrl+V` | Paste entity at camera centre |
| `Ctrl+S` | Save scene |

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

```
just_game_engine_editor/
└── lib/src/
    ├── core/
    │   ├── plugin/          ← JustGameEditorPlugin (main orchestrator)
    │   ├── state/           ← EditorSceneState (scene graph ↔ ECS bridge)
    │   ├── serialization/   ← SceneFileGenerator, EcsLevelMapper, EditorSerializationService
    │   ├── services/        ← EditorLogService, ColorHistoryService
    │   └── ecs/
    │       ├── components/  ← 60 editor component descriptors (by category)
    │       ├── systems/     ← editor-specific ECS systems
    │       └── registry/    ← ComponentRegistry (descriptor lookup)
    ├── ui/
    │   ├── overlay/         ← JustGameEditorOverlay + 11 .part.dart UI sections
    │   ├── panels/          ← EntityInspectorPanel, SceneTreePanel, ScenePickerPanel
    │   ├── dialogs/         ← AddComponentPickerDialog, CreateSceneOverlay
    │   ├── widgets/         ← ScrubableNumberField and shared widgets
    │   └── theme/           ← EditorTheme (colour palette)
    ├── integration/         ← GameEditorAdapter (drop-in GameWidget replacement)
    └── debugger/            ← EngineDebugger bridge
```

### Core Layer

#### `JustGameEditorPlugin`
The central orchestrator (`lib/src/core/plugin/editor_plugin.dart`). Implements `EnginePlugin` and wires together all editor subsystems.

**Lifecycle:**
- `register(engine)` — debug-gated factory; returns `null` in release builds
- `onInitialize()` — registers ECS systems, attaches debugger, loads component registry
- `onUpdate(dt)` — ticks editor state each frame
- `onRender(canvas)` — draws gizmos and grid overlay
- `reassemble()` — refreshes component descriptors on hot-reload

**Entity operations:** `createEntity`, `deleteEntity`, `createGroup`, `reparentEntity`, `copyEntity`, `pasteEntity`

**Scene operations:** `openScene(name)`, `saveScene()`

**Gizmo interaction:** `onPointerDown`, `onPointerMove`, `onPointerUp` — handles translate/rotate/scale handle hit-testing and dragging

#### `EditorSceneState`
Keeps the authoring scene graph in sync with the live ECS world (`lib/src/core/state/editor_scene_state.dart`). Both `JustGameEditorPlugin` and the UI listen to it as a `ChangeNotifier`.

- **Selection:** `selectEntity`, `toggleMultiSelect`, `selectRange`, `clearSelection`
- **Transform sync:** `applyTranslation`, `applyRotation`, `applyScale` → mutate ECS, then `syncEntityNode` pulls state back into the scene graph
- **Dirty tracking:** `markDirty` / `markClean` — drives the unsaved-changes indicator
- **Grid snapping:** configurable grid size with automatic position/scale quantization

#### `ComponentRegistry`
Maps component types to `ComponentDescriptor` instances (`lib/src/core/ecs/registry/component_registry.dart`). The inspector queries it to generate property-editor UI dynamically — no codegen required.

Built-in descriptors cover all engine components: transform, physics bodies/joints, sprite, animated sprite, audio, camera follow, input, effects, health, lifetime, tags, and more.

#### `EditorSerializationService`
Runs serialization in a `compute()` isolate so large scenes don't jank the main thread. Delegates file I/O to `SceneFileGenerator`.

### UI Layer

#### `JustGameEditorOverlay`
Top-level Flutter widget that wraps the game canvas (`lib/src/ui/overlay/editor_overlay.dart`). Implemented as a single class split across 11 `.part.dart` files:

| Part file | Responsibility |
|-----------|----------------|
| `overlay_settings_store` | Persisted overlay settings (panel sizes, snap, grid) |
| `overlay_compact_dock` | Minimised status dock shown when editor is hidden |
| `overlay_dock_metrics` | FPS, entity count, memory metrics panel |
| `overlay_dock_logs_panel` | Runtime log viewer with filtering |
| `overlay_dock_assets_panel` | Asset browser |
| `overlay_dock_timeline_panel` | Animation/keyframe timeline |
| `overlay_right_panel` | Right sidebar host (inspector / scene tree / scene picker) |
| `overlay_detail_cards` | Entity detail cards |
| `overlay_settings_dialog` | Editor settings UI |
| `overlay_shared_widgets` | Shared decorators and utilities |
| `overlay_snackbar` | Toast notification layer |

#### `GizmoPainter`
`CustomPainter` that draws translate/rotate/scale handles on the canvas (`lib/src/ui/overlay/gizmo_painter.dart`). `JustGameEditorPlugin` owns the handle geometry; `GizmoPainter` only handles rendering.

#### `ScrubableNumberField`
Number input that supports mouse-drag scrubbing in addition to keyboard entry (`lib/src/ui/widgets/scrubbable_number_field.dart`). Used throughout the inspector for numeric component fields.

### Integration Layer

#### `GameEditorAdapter`
Drop-in replacement for `GameWidget` during development (`lib/src/integration/game_editor_adapter.dart`). Internally creates the plugin, drives `onUpdate` via a `Ticker`, and pipes `onRender` into the rendering engine's overlay hook. In non-debug builds it becomes a plain `GameWidget` at compile time.

### ECS Systems (editor-only)

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

---

## Debug Gating

Every public entry point that touches editor state is guarded:

```dart
// In JustGameEditorPlugin.register():
if (!kDebugMode) return null;
```

Flutter's tree shaker removes all dead branches in AOT/release builds. As long as you use `GameEditorAdapter` or guard `JustGameEditorOverlay` behind the null-check on `plugin`, the editor contributes zero code or overhead to shipping builds.

---

## Notes

- Scene file I/O (`SceneFileGenerator`) uses `dart:io` and is desktop/native only. Web is unsupported.
- The serialization service outputs JSON drafts; TMX export is planned but not yet implemented.
- `just_game_engine` no longer embeds a debugger panel inside `GameWidget`; this package provides the dedicated development-time overlay.
- The package is published to `none` (internal monorepo only).
