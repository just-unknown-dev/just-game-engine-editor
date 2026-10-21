# Contributing to Just Game Engine Editor

Thank you for your interest in contributing to **Just Game Engine Editor**. Bug fixes, features, tests and documentation are all welcome.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Reporting Bugs and Suggesting Features](#reporting-bugs-and-suggesting-features)
- [Development Setup](#development-setup)
- [Working Against Unpublished Dependencies](#working-against-unpublished-dependencies)
- [How the Package Fits Together](#how-the-package-fits-together)
- [Running the Tests](#running-the-tests)
- [Coding Guidelines](#coding-guidelines)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Commit Message Convention](#commit-message-convention)
- [License](#license)

---

## Code of Conduct

This project, and `just_editor_core` beside it, follows our [Code of Conduct](CODE_OF_CONDUCT.md). By taking part you agree to its terms. Report unacceptable behaviour privately, as its [Enforcement](CODE_OF_CONDUCT.md#enforcement) section says.

---

## Reporting Bugs and Suggesting Features

Before opening an issue, search the [existing issues](https://github.com/just-unknown-dev/just-game-engine-editor/issues) and check that the problem happens on the latest version.

A bug report should have:

- a clear title;
- steps to reproduce, and what you expected instead of what happened;
- the output of `flutter --version`, and the platform (Windows, macOS or Linux: the editor runs nowhere else);
- the versions of `just_game_engine_editor`, `just_game_engine` and each package whose module your game passes to `JustGameEditorPlugin.register(modules: …)`, from `pubspec.lock`;
- the scene file (`assets/scenes/<name>.scene.json`), or the smallest one that shows the problem, and whether the scene is 2-D or 3-D. For a Level Map bug, add its `.map.json` and tilesets; for a Tiled bug, the `.tmx` or `.tmj` and its tilesets;
- the Console's lines from around the problem, which are also in `.editor_logs/editor_runtime.jsonl`. The Console replays the last session too, so check the times;
- for a hot reload bug, what you changed, and whether it was a hot reload (**r**) or a hot restart (**R**);
- for a keyboard bug, the keyboard layout, and whether you changed the key in Settings → Keyboard;
- for a layout or drawing bug, a screenshot, the window size, and your Appearance and Accessibility settings.

Some bugs belong elsewhere. If the scene misbehaves in the game too, outside the editor, the bug is in `just_game_engine` (or `just_physics_engine`, for the simulation). The scene format, its migrations and the starter scenes belong to `just_game_engine_formats`; parsing Tiled files to `just_tiled` (turning them into a Level Map is this package's job); the colour picker to `just_colours`. A module's tools belong to its package: the interface editor to `just_ui_editor`, the Sprite Studio to `just_sprite_editor`, the Input Actions editor to `just_input_editor`, the Asset Store window to `just_asset_store_editor`, and a kit's prefabs and tools to `just_platformer_kit` or `just_third_person_kit`. The `just` command is `just_core_cli`, and its game commands (`just game scene`, `just game build`) are `just_game_engine_cli`.

For a feature, open an issue labelled **`enhancement`** that describes the problem it solves and how it should behave. The package's scope is editing a `just_game_engine` game's scenes from inside the running game: the overlay, the scene tree and inspector, the Level Designer and Level Map, play-testing, the docks and settings, and the `EditorModule` API that everything else plugs in through. A tool for one kind of asset or one genre belongs in a module of its own, as the sprite, interface and input editors are. A change to what the editor saves affects every game's levels, and a change to `EditorModule` affects every module, so open the issue first and agree the approach before you write it.

---

## Development Setup

| Tool | Minimum version |
|------|-----------------|
| Dart | 3.11.0 |
| Flutter | 3.47.1 |

The editor runs only in a debug build on Windows, macOS or Linux, so you need one of those to try a change (the package itself compiles for every platform, web and wasm included). It is published on pub.dev, and games take it as a dev dependency. What a module builds on is a package of its own, [`just_editor_core`](https://github.com/just-unknown-dev/just-editor-core): a change to the module contract, the scope, undo, the inspector's rows or the UI kit is made there.

Clone it into a folder named after the package, and check out any `just_*` package you work with beside it, under its own package name. The overrides below and `test/tiled_import_test.dart` look for them there.

```bash
git clone https://github.com/just-unknown-dev/just-game-engine-editor.git just_game_engine_editor
cd just_game_engine_editor
flutter pub get
flutter test
```

If you're working from the Just engine monorepo, run every command from `packages/just_game_engine_editor`.

If `flutter pub get` cannot find a version of a `just_*` package, that version is not published yet: see the next section.

To see a change running:

- **The example app.** `example/` is a bare engine with the editor over it. Run it with `cd example` and `flutter run -d windows` (or `macos`, `linux`). Its `pubspec.yaml` takes the published `just_game_engine` and this checkout (`path: ../`); to run it against unreleased `just_*` versions, override them in a git-ignored `example/pubspec_overrides.yaml`, as below.
- **A game.** Point the game's `pubspec_overrides.yaml` at your checkout; in a project made with `just create`, `just dev link <folder>` does that for every `just_*` checkout in `<folder>`. Then start the game's editor entry point in a debug build (see [QUICKSTART.md](QUICKSTART.md)).

The editor writes scenes, backups and logs relative to the working directory. Leave them out of your pull request.

---

## Working Against Unpublished Dependencies

The package's `just_*` dependencies are `just_editor_core`, `just_game_engine`, `just_tiled`, `just_debugger` and `just_signals`; its tests also use `just_graphics_engine`, `just_colours` and `just_storage`. `just_editor_core` brings `just_game_engine_formats`, `just_di` and the rest. When a change needs an unreleased version of one, check it out next to this repository and point this package at it with a `pubspec_overrides.yaml` in the repository root:

```yaml
# pubspec_overrides.yaml: local only, never commit it.
dependency_overrides:
  just_editor_core:
    path: ../just_editor_core
  just_game_engine:
    path: ../just_game_engine
  just_tiled:
    path: ../just_tiled
```

List only what you have checked out. `just_game_engine` has `just_*` dependencies of its own (`just_game_engine_formats`, `just_physics_engine`, `just_inputs` and others); if the engine you check out needs unreleased versions of them, override them the same way. Then run `flutter pub get`. Delete the file (or the entries) and run `flutter pub get` again to go back to the published versions. `.gitignore` already leaves the file out.

Do not change `pubspec.yaml` to a path dependency. If your pull request needs a version of a `just_*` package that is not published yet, say so in the pull request: this package can only be released after it.

Eight packages build on `just_editor_core`, each with an `EditorModule` of its own: the modules `just_ui_editor`, `just_sprite_editor`, `just_input_editor`, `just_material_editor` and `just_asset_store_editor`, and the kits `just_platformer_kit`, `just_third_person_kit` and `just_world_builder_kit`; three of them (the interface and material editors and the World Builder kit) take this package too. If you change the public API, above all `EditorModule`, say in the pull request what they will need.

---

## How the Package Fits Together

`JustGameEditorPlugin` attaches to a running `Engine` and owns one `EditorScope`, which holds every registry and service of one editor. `JustGameEngineEditor` puts `JustGameEditorOverlay` over the game's `GameWidget`. Games, kits and tools add to the editor through `EditorModule`s. [ARCHITECTURE.md](ARCHITECTURE.md) explains each part in depth.

In this package:

| Folder | Contents |
|--------|----------|
| `lib/just_game_engine_editor.dart` | The public library: what a game's editor entry point and a module's tests use (the plugin, `JustGameEngineEditor`, `BuiltInEditorModule`, `LevelDesignerSession`, the Tiled importer, ...), and `just_editor_core` re-exported |
| `lib/materials.dart` | `BuiltInMaterialsModule` and the normal map maker (`NormalMaps`, `Pixels`) |
| `lib/graphics.dart` | `BuiltInGraphicsModule`, model cooking (`ModelCooking`) and pictures (`ModelThumbnails`) |
| `lib/src/core/plugin/` | `JustGameEditorPlugin`: the engine plugin, the key handler, autosave, the Level Designer session |
| `lib/src/core/scope/` | `EditorScopeServices`: the editor's own services on the scope (the dock controller, `EntityOps`, the Level Map's) |
| `lib/src/core/state/`, `core/play/` | `PlaySnapshot`; `PlayController` |
| `lib/src/core/scene/`, `core/serialization/` | `SceneIO` (open, save, migrate), `SceneLoading`; `SceneManager`, `SceneNameValidator` |
| `lib/src/core/entity/` | `EntityOps`: create, delete, group, re-parent and the clipboard, over the core's commands |
| `lib/src/core/view/`, `core/input/` | `OrbitFlyEditorView` (3-D), `PlanarEntityPicker`; `ViewportInput`, the gizmo drag solvers |
| `lib/src/core/level_map/` | Editing the Level Map: `LevelMapDocuments`, `LevelMapProvision`, the tile commands, `TilesToEntity`, Tiled import and export |
| `lib/src/core/physics/`, `core/tags/` | Renaming and deleting collision layers and tags across scenes (`LayerRefactor`, `TagRefactor`), `PhysicsBodies`, the 3-D collider overlay |
| `lib/src/core/prefabs/` | `PrefabInstances`: prefab files, their instances and overrides |
| `lib/src/core/validation/` | The built-in Problems checks: `BuiltInValidators`, `PhysicsChecks`, `Physics3DChecks`, `TagChecks` |
| `lib/src/core/prefs/`, `core/project/`, `core/assets/`, `core/ecs/` | `RecentScenes`; `EditorPresence`, the `editor.lock` heartbeat; the project-file sprite loader; the editor's two systems |
| `lib/src/extension/` | `BuiltInEditorModule` and the built-in contributions it gathers (camera, audio, 2-D lighting, tags, tiles, 3-D physics, row decorations) |
| `lib/src/integration/` | `JustGameEngineEditor`, the widget a game puts on screen |
| `lib/src/debugger/` | The engine's debugger, attached to the plugin |
| `lib/src/materials/` | `BuiltInMaterialsModule`: the 2-D and 3-D Material windows, their pictures, presets, checks, inspector editors and importers |
| `lib/src/graphics/` | `BuiltInGraphicsModule`, for a game with 3-D graphics: models in the Assets dock (pictures, drop, the Model window, cooking, placing with lights and sockets), picking by triangles, light and camera aids, the Model, Light and Environment inspector sections |
| `lib/src/ui/overlay/` | `JustGameEditorOverlay`: the chrome, docks, settings, right panel, start card, gizmos and viewport menu |
| `lib/src/ui/inspector/`, `ui/panels/` | The built-in field editors and extras, `EntityHeader`, the physics inspector; `EntityInspectorPanel`, `ScenePickerPanel` |
| `lib/src/ui/scene_tree/` | `SceneTreePanel`, `SceneTreeController`, `MapItemRow` |
| `lib/src/ui/level_designer/`, `ui/level_designer_3d/` | The Level Designer (its session, panels, controls, built-in tools, overlays, commands and keys); the Default 3D kit |
| `lib/src/ui/timeline/`, `ui/tileset/`, `ui/json_viewer/` | The Timeline dock (`TimelineSession`); the Tileset Editor workspace (`TilesetSession`) and `BuiltInWorkspaces`; the read-only JSON window |
| `example/` | A bare engine with the editor over it |
| `test/` | The tests; shared helpers are in `test/support/` |

In [`just_editor_core`](https://github.com/just-unknown-dev/just-editor-core), what modules build on (`lib/src/`):

| Folder | Contents |
|--------|----------|
| `extension/` | `EditorModule` and its contributions, asset kinds and the asset index, markers, viewport overlays and handles, prefab variants, workspace contributions |
| `scope/` | `EditorScope`: one editor's registries and services, in a `just_di` container |
| `model/` | `EditorHistory` and the entity and hierarchy commands, `ComponentEdit`, `CommandRegistry` and `DesignerCommand`, `EditorKeys` and `ModifierKeys`, `EditorSceneState`, `EditorViewState`, `SceneCodec`, `SceneStore`, `UnknownComponents` |
| `designer/` | The Level Designer's API: `DesignerSession`, tools, overlays, snapping, prefabs, layers, grids, the 3-D working plane |
| `inspector/` | `DefinitionSection`, the field rows, `FieldEditorRegistry`, component extras, `CollectionEditor`, `AddComponentPicker` |
| `view/` | `EditorView`, `GameCameraEditorView`, the pickers, `HandleDragSession` |
| `project/`, `settings/`, `services/`, `validation/` | Tags, physics layers and colours; `EditorPrefs` and the overlay settings; the log, `ProjectFiles`, `PackageAssetPaths`; `SceneValidator` |
| `scene_tree/` | `SceneTreeModel` and the row tile |
| `look/` | `EditorTheme`, `EditorThemeData`, `EditorMetrics`, `ThemeController`, `ViewportLook`; `kit/` and `widgets/`, the shared widgets every panel, dock, dialog and module is built from |
| `io/` | The `dart:io` seam behind `package:just_editor_core/io.dart` |

A few rules hold the package together. Keep them:

- **Debug builds on the desktop only.** `JustGameEditorPlugin.register` returns null outside `kDebugMode` and where `supportsPlatform` is false (anything but Windows, macOS and Linux), and `JustGameEngineEditor` is then a plain `GameWidget`. Keep both checks.
- **It compiles everywhere.** A game imports this package in its editor entry point and still builds for Android, iOS, the web and wasm. So `lib/` never imports `dart:io`: it imports `package:just_editor_core/io.dart` (stand-ins on the web), and reads pictures from files with its `fileImage`. Tests may import `dart:io`.
- **Files are written safely.** Write a project file through `ProjectFiles` (`writeString`, `writeBytes`: whole or not at all; `rename`: safe for a change of case, never over another file), and refuse a path read out of a file that would leave the project (`ProjectFiles.isContained`, `PackageAssetPaths.isWritable`). Compare paths with `ProjectFiles.samePath`, never `==`: Windows and macOS fold case.
- **Every OS's keys.** Bind keys through `KeyBinding` and read modifiers through `ModifierKeys` or `EditorKeys`, never `isControlPressed`: the primary modifier is Cmd on macOS, where Backspace deletes too.
- **The game reads what the editor saves.** A scene is `assets/scenes/<name>.scene.json`, `{version, name, mode, entities, editor}`, and the game loads the same file through the engine's `SceneLoader`. `SceneCodec` encodes components only through their `ComponentDefinition`, from the registry the game loads with. The format version (`SceneFormat.current`), the migrations and the starter scenes (`SceneStarters`) live in `just_game_engine_formats`, so a format change starts there. The `editor` section is the editor's alone; a module writes under its id with `saveEditorData`.
- **Nothing saved is lost.** Components no definition can read are kept in `UnknownComponents` and written back unchanged. An older file is migrated in memory and changes only when the user saves. Saving during a play-test saves the level as authored (`PlaySnapshot`), and anything that previews a change in the live world registers an authored-state guard (`EditorScope.authoredStateGuards`), so no preview reaches a save or a play-test.
- **One undo stack.** Every edit to the scene is an `EditorCommand` on `scope.history` (`EditorHistory`), one step per gesture: a field is a `ComponentFieldCommand`, an edit to a whole component goes through `ComponentEdit.begin` … `commit`, and several changes are one `CompositeCommand`. Only a document with a file of its own keeps its own stack (`TimelineSession`, `TilesetSession`).
- **No process-wide registries.** Every registry and service belongs to an `EditorScope`, and `reload()` rebuilds them all from the built-ins and the registered `EditorModule`s, so nothing piles up across hot reloads. The built-ins register exactly as a module does.
- **What is built from code is a getter.** Component definitions, prefabs, workspaces, docks and styles that read `EditorTheme` are getters, never `static final`, so a hot reload brings them up to date. `EditorModule.onRegister` runs once per module; `onReassemble` runs after each hot reload.
- **Every `EditorModule` member has a default** (an empty list, null, or nothing to do), so a module overrides only what it adds. Give a new member one too. Ids are saved: dock ids key the layout in the `editor.docks` preference and command ids key the user's changed keys in `editor.keys.shortcuts`, so never rename one.
- **Map data is looked up, never held.** Stop and a state undo replace a `LevelMapComponent` and its `LevelMapData`, so editor code never keeps either. Look the map up by entity id or path (`LevelMapRef`, `scope.mapDocs`) each time, and a layer by its id.
- **`just_game_engine_cli` knows this package by name.** Its release check (`ReleaseRules`) looks in a built game for this package's paths, for `JustGameEditorPlugin`, `EditorScope` and `LevelDesignerSession`, and for the strings `Runtime editor initialized.` and `Just Runtime Editor`. Its own `EditorPresence` reads the `.dart_tool/just_core_cli/editor.lock` that this package's `EditorPresence` touches. Change one of these and `just_game_engine_cli` must change with it.
- **`just_store.json` is the Asset Store manifest**, for projects that install the editor through the store. Its `id` and `version` must equal `name` and `version` in `pubspec.yaml`, or the store refuses the package. `editorOnlyLibraries: ["*"]` tells the release check that no library here may reach a release build.

---

## Running the Tests

Run every command from the repository root. `test/reassemble_test.dart` reads `lib/` from disk, and `test/tiled_import_test.dart` reads real Tiled files from `../just_tiled/test/fixtures`, so it needs `just_tiled` checked out beside this repository.

```bash
# The whole suite.
flutter test

# One file.
flutter test test/scene_manager_test.dart

# The tests that render, on a real GPU.
flutter test --enable-impeller --enable-flutter-gpu --tags gpu --concurrency=1
```

**The `gpu` tag.** A test that renders with Flutter GPU (the 3-D material pictures) carries `@Tags(['gpu'])` (declared in `dart_test.yaml`) and skips with the reason from `gpuUnavailableReason()` (`package:just_graphics_engine/testing.dart`, a dev dependency), so a plain `flutter test` passes on any machine. Run it for any change to the material pictures or the 3-D Material window's preview.

**Tests that hold the rules.**

- `test/reassemble_test.dart` fails on a `static final` or top-level `final` that makes a `TextStyle`, `PrefabDefinition`, `WorkspaceDefinition` or `DockDefinition`, or that reads `EditorTheme`. Make it a getter. (`just_editor_core`'s `hygiene_test.dart` holds its own `lib/` to the same rule.)
- `test/readme_snippets_test.dart` compiles the code README.md and QUICKSTART.md give a game to copy. Change both together.
- `test/inspector_look_test.dart` measures a real inspector and fails when its controls stop looking alike.
- `test/unknown_components_test.dart`, `test/play_snapshot_test.dart` and `test/component_round_trip_test.dart` hold the save rules above.
- `test/mac_keys_test.dart` presses the keys as a Mac does (Cmd, Backspace).
- In `just_editor_core`: `test/editor_dropdown_test.dart` fails on a Material `DropdownButton` or `DropdownButtonFormField` in its `lib/` (use `EditorDropdown`, here too), and `test/scene_starters_parity_test.dart` fails when a component's saved form changes (update the starters in `just_game_engine_formats` to match).

**Writing tests.**

- `testScope()` (`test/support/test_scope.dart`) gives an `EditorScope` over a bare world, disposed with the test. Two tests get two scopes and share nothing.
- `MemorySettingsStore` (`test/support/memory_settings_store.dart`) keeps preferences in memory, so a test touches neither the disk nor `path_provider`.
- Put files in a folder from `Directory.systemTemp.createTempSync`, passed as the scope's `scenesRoot` or a `SceneStore`'s `root`. Never use a fixed path: `flutter test` runs test files in parallel processes.
- Synthetic pointer events carry a zero timestamp unless given one, and the scene tree reads two quick clicks as a double click. Give each click its own `timeStamp`, as `clickAt` in `test/scene_tree_panel_test.dart` does.
- Real file I/O inside `testWidgets` finishes on the real clock: run it in `tester.runAsync`, and wait for its outcome with `pumpUntil` / `waitUntil` (`test/support/real_io.dart`), never for a fixed time.

---

## Coding Guidelines

- **Formatting.** Code is formatted with `dart format`. Format the files you change, and only those, keeping each file's line endings:

  ```bash
  dart format <the files you changed>
  ```

- **Analysis.** `flutter analyze` reports no issues today. Keep it that way: no errors, warnings or infos. The rules are in `analysis_options.yaml`: `flutter_lints`, with `build/` excluded.
- **State.** Editor state is `just_signals`: a `Signal` on the service that owns it, a `Computed` for what derives from it, read in widgets through `SignalBuilder` or `SignalConsumer`, with `batch()` around the writes of one operation. Don't add a `ChangeNotifier` for editor state.
- **UI from the kit.** Build panels from the kit, `package:just_editor_core/kit.dart` (`EditorIconButton`, `EditorButton`, `CommitTextField`, `EditorDialogFrame`, `EditorDropdown` and the rest). Take colours from `EditorTheme` and sizes from `EditorMetrics`, so the theme and the accessibility settings reach them, and never make a target smaller than `EditorMetrics.minTarget`. Write font sizes as they read at 100%: `EditorLook` scales the text.
- **Keys.** A command with a key is a `DesignerCommand` in the scope's `CommandRegistry`, bound by a `KeyBinding`, so Settings → Keyboard can change it. A panel that acts on keys itself wraps itself in `EditorKeyClaim(claims: …)` with exactly those keys; otherwise both it and the editor act.
- **Disposal.** A `State.dispose` must not ask the `EditorScope` for anything: its container may already be closed. Hold what you need from the start.
- **Text.** What the user sees is plain English with British spelling ("colour"), as in the rest of the editor.
- **Documentation.** Give every public API you add a `///` doc comment. Describe user-visible changes in [CHANGELOG.md](CHANGELOG.md). Update [README.md](README.md) when what users see changes, and [ARCHITECTURE.md](ARCHITECTURE.md) when the structure or the module contract does.
- **Tests.** Add or update tests for any behaviour you change. A bug fix comes with a test that fails without it.
- **Dependencies.** Do not add a dependency without discussing it in an issue first.
- **Structure.** Match the existing folders under `lib/src/`. What a module needs belongs in `just_editor_core`, not here. Export what a game's editor entry point or a module's tests need through `lib/just_game_engine_editor.dart` (materials' through `lib/materials.dart`), each export with a `show` list; anything else stays in `lib/src/`. A member that other files of the package need but no game or module should is `@internal`. Modules and games import the library, never files under `lib/src/`; the package's own tests may.

---

## Submitting a Pull Request

1. Create a topic branch from `main`:
   ```bash
   git checkout -b fix/stop-restores-children
   ```
2. Make your change, following the [Coding Guidelines](#coding-guidelines).
3. Check that everything passes:
   ```bash
   dart format --output=none --set-exit-if-changed <the files you changed>
   flutter analyze
   flutter test
   ```
4. Widget tests miss some of what a real window does (focus, hover, drags between panels). For a change to the chrome, the viewport or a panel, try it in the example app or a game, and say in the pull request on which platform.
5. Commit with a [conventional commit message](#commit-message-convention).
6. Push to your fork and open a pull request against `main`. Say what changed and why, with before and after screenshots for a visible change. List any unpublished `just_*` version it needs, and any change it means for the modules and kits that build on this package or for `just_game_engine_cli`.
7. Answer review feedback.

Small pull requests are easier to review.

---

## Commit Message Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

| Type | When to use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

Use the area as the scope: `plugin`, `scope`, `scenes`, `play`, `viewport`, `inspector`, `scene-tree`, `designer`, `level-map`, `physics`, `tags`, `timeline`, `tileset`, `docks`, `settings`, `kit` or `modules` (the `EditorModule` API). Mark a change that breaks the public API or what the editor saves with `!` and a `BREAKING CHANGE:` footer.

**Examples:**
```
fix(play): put back a child that play destroyed under its own parent
feat(docks): sort the Problems dock by entity
docs(contributing): explain the scene file rules
```

---

## License

By contributing to Just Game Engine Editor you agree that your contributions will be licensed under the terms in [LICENSE](LICENSE).
