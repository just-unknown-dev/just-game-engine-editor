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

## 3. Register custom components

Describe each game-specific component as an `EditorComponent` and register it with `CustomComponentRegistry.instance`. Wrap your registrations in a function and pass that function to `JustGameEditorPlugin.registerProjectComponents` once at startup — it's re-run automatically on every hot-reload so newly generated descriptors show up without restarting the app:

```dart
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void registerCustomComponents() {
  CustomComponentRegistry.instance.register(
    EditorComponent(
      id: 'my_health_component',
      name: 'Health',
      type: 'MyHealthComponent',
      group: 'Gameplay',
      componentType: ComponentType.editor,
      factory: () => MyHealthComponent(),
      fields: [
        EditorComponentField(
          name: 'maxHp',
          kind: EditorFieldKind.integer,
          scrubConfig: const NumberScrubConfig(step: 1, integer: true, min: 0),
          read: (c) => (c as MyHealthComponent).maxHp,
          write: (c, v) => (c as MyHealthComponent).maxHp = v as int,
        ),
        EditorComponentField(
          name: 'invincible',
          kind: EditorFieldKind.boolean,
          read: (c) => (c as MyHealthComponent).invincible,
          write: (c, v) => (c as MyHealthComponent).invincible = v as bool,
        ),
      ],
    ),
  );
}

// Call once at app startup:
JustGameEditorPlugin.registerProjectComponents(registerCustomComponents);
```

`CustomComponentRegistry.instance` is cleared and rebuilt on every hot-reload (built-in components first, then every registered project callback), so keep registration idempotent — calling `register` again with the same `id` simply replaces the previous descriptor.

## 4. Open the editor

Press **F1** at runtime to toggle the editor overlay. The game viewport shifts left; the right panel shows the scene tree, inspector, and scene picker.

See the main [README](README.md) for keyboard shortcuts and the scene file format, and [ARCHITECTURE.md](ARCHITECTURE.md) for how the package is structured internally.
