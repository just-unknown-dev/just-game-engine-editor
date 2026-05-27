# Just Game Engine Editor

Developer-only runtime level editor scaffolding for `just_game_engine`.

This package is designed for JIT/dev workflows (hot reload + live state edits)
and should be consumed as a `dev_dependency` so production AOT builds can strip
editor code during tree shaking.

`JustGameEditorPlugin.register(...)` returns `null` outside debug mode, so
editor UI wiring remains opt-in for development builds only.

## What Is Included

- `EnginePlugin` contract scaffold with lifecycle hooks.
- `JustGameEditorPlugin` debug-gated registration helper.
- `JustGameEditorOverlay` with focus capture and split editor layout.
- `EditorSerializationService` with `compute()`-based draft serialization.

## Install

Add to your game app as a `dev_dependency`:

```yaml
dev_dependencies:
	just_game_engine_editor:
		path: packages/just_game_engine_editor
```

## Usage

```dart
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

final plugin = await JustGameEditorPlugin.register(engine: engine);

Widget gameView = GameWidget(engine: engine);
if (plugin != null) {
	gameView = JustGameEditorOverlay(plugin: plugin, gameChild: gameView);
}

return gameView;
```

## Keybinds

- `F1`: Toggle editor visibility.
- `F2`: Toggle status panel (when editor is visible).
- `Ctrl+C`: Copy selected entity.
- `Ctrl+V`: Paste entity.
- `Ctrl+S`: Save scene.

## Notes

- This package is intentionally debug-focused and not wired for production UX.
- The serialization service currently outputs JSON drafts and TMX TODO markers.
- `just_game_engine` no longer embeds the debugger panel in `GameWidget`; this
	package provides a separate development-time editor overlay.
