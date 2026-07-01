# Just Game Engine Editor - Architecture

```
just_game_engine_editor/
└── lib/src/
    ├── core/
    │   ├── plugin/          ← JustGameEditorPlugin (main orchestrator)
    │   ├── state/           ← EditorSceneState (scene graph ↔ ECS bridge)
    │   ├── serialization/   ← SceneFileGenerator, EcsLevelMapper, EditorSerializationService, SceneNameValidator
    │   ├── services/        ← EditorLogService, ColorHistoryService
    │   └── ecs/
    │       ├── generator/   ← EditorComponent/EditorComponentField model + CustomComponentRegistry
    │       ├── components/  ← 42 built-in editor component descriptors (by category)
    │       ├── systems/     ← editor-specific ECS systems
    │       └── registry/    ← ComponentEntry catalogue for the "Add Component" picker
    ├── ui/
    │   ├── overlay/         ← JustGameEditorOverlay + 11 .part.dart UI sections
    │   ├── panels/          ← EntityInspectorPanel, CustomComponentSection, SceneTreePanel, ScenePickerPanel
    │   ├── dialogs/         ← AddComponentPicker, CreateSceneOverlay
    │   ├── widgets/         ← ScrubbableNumberField and shared widgets
    │   └── theme/           ← EditorTheme (colour palette)
    ├── integration/         ← GameEditorAdapter (drop-in GameWidget replacement)
    └── debugger/            ← EngineDebugger bridge
```

## Core Layer

### `JustGameEditorPlugin`
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

### `EditorSceneState`
Keeps the authoring scene graph in sync with the live ECS world (`lib/src/core/state/editor_scene_state.dart`). Both `JustGameEditorPlugin` and the UI listen to it as a `ChangeNotifier`.

- **Selection:** `selectEntity`, `toggleMultiSelect`, `selectRange`, `clearSelection`
- **Transform sync:** `applyTranslation`, `applyRotation`, `applyScale` → mutate ECS, then `syncEntityNode` pulls state back into the scene graph
- **Dirty tracking:** `markDirty` / `markClean` — drives the unsaved-changes indicator
- **Grid snapping:** configurable grid size with automatic position/scale quantization

### `CustomComponentRegistry`
Singleton descriptor store (`lib/src/core/ecs/generator/component_registry.dart`). Each component type is described by an `EditorComponent` (id, name, factory, icon/colour) holding a list of `EditorComponentField`s — typed field descriptors (`EditorFieldKind`) with `read`/`write` accessors, optional `NumberScrubConfig`, and JSON encode/decode logic. `EntityInspectorPanel` and `CustomComponentSection` query `descriptorForComponent` to generate property-editor UI dynamically; `EditorSerializationService` uses `componentToJson` / `componentFromJson` for scene persistence.

`registerAllEditorComponents()` (`lib/src/core/ecs/components/editor_components_registrant.dart`) registers the 42 built-in descriptors covering transform, physics bodies/joints, sprite, animated sprite, audio, camera follow, input, effects, health, lifetime, tags, and more. Project-specific components are added the same way via `JustGameEditorPlugin.registerProjectComponents` (see [QUICKSTART.md](QUICKSTART.md) step 3).

### Component picker registry
`getComponentRegistryEntries()` (`lib/src/core/ecs/registry/component_registry.dart`) adapts every registered `EditorComponent` into a lightweight `ComponentEntry` (name, group, description, factory) grouped by `kComponentGroups`. This is the catalogue `AddComponentPicker` renders — it doesn't own any state of its own, it's purely a view over `CustomComponentRegistry`.

### `EditorSerializationService`
Runs serialization in a `compute()` isolate so large scenes don't jank the main thread. Delegates file I/O to `SceneFileGenerator`.

## UI Layer

### `JustGameEditorOverlay`
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

### `GizmoPainter`
`CustomPainter` that draws translate/rotate/scale handles on the canvas (`lib/src/ui/overlay/gizmo_painter.dart`). `JustGameEditorPlugin` owns the handle geometry; `GizmoPainter` only handles rendering.

### `ScrubbableNumberField`
Number input that supports mouse-drag scrubbing in addition to keyboard entry (`lib/src/ui/widgets/scrubbable_number_field.dart`). Driven by a field's `NumberScrubConfig` and used throughout the inspector for numeric component fields.

### `CustomComponentSection`
Renders the field editors for one `EditorComponent` inside the inspector (`lib/src/ui/panels/custom_component_section.dart`), dispatching each `EditorComponentField` to a row widget based on its `EditorFieldKind` (bool, text, enum, color, asset ref, scrubbable number, etc).

## Integration Layer

### `GameEditorAdapter`
Drop-in replacement for `GameWidget` during development (`lib/src/integration/game_editor_adapter.dart`). Internally creates the plugin, drives `onUpdate` via a `Ticker`, and pipes `onRender` into the rendering engine's overlay hook. In non-debug builds it becomes a plain `GameWidget` at compile time.

## ECS Systems (editor-only)

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
