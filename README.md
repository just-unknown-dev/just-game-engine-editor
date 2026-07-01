# Just Game Engine Editor

A developer-only runtime level editor overlay for [`just_game_engine`](../just_game_engine/). Designed for JIT/debug workflows — hot reload, live ECS state edits, and scene authoring — with zero runtime cost in production builds.

## 📚 Documentation

- **[Quick Start Guide](QUICKSTART.md)** — install the package, wrap your game widget, and register custom components
- **[Architecture](ARCHITECTURE.md)** — package layout and how the core/UI/integration layers fit together

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

See the [Quick Start Guide](QUICKSTART.md) for wiring up the plugin, the `GameEditorAdapter` shortcut, and registering custom components. Press **F1** at runtime to toggle the editor overlay.

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

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full package layout — the `EditorComponent`/`CustomComponentRegistry` descriptor model, the `JustGameEditorOverlay` UI layer, `GameEditorAdapter` integration, and the editor-only ECS systems.

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
