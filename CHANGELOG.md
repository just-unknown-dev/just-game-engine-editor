# Changelog

## 0.1.0

The first release that isn't a dev release: from here its API follows semantic versioning (in 0.x, a breaking change moves the minor version). It is made for just_game_engine 2.0.x, and so for Flutter 3.47 (just_game_engine's README, "Flutter versions"). The editor runs in a game's desktop debug build: verified on Windows; macOS and Linux are untested. It says so when it runs on another Flutter than the one the project pins (below).

### Breaking

- **Renamed** (the public library's names): `GizmoPainter` → `Gizmo2DPainter` (beside the 3-D gizmo), `Pixels` → `ImagePixels` (in `materials.dart`; the file was `image_pixels.dart` already), `BuiltInGraphicsModule` → `BuiltInGraphics3DModule` (in `graphics.dart`; it is the 3-D one, beside 2-D lighting). Module, dock, workspace and command ids keep their strings, so nothing saved changes.
- Requires just_editor_core ^0.1.0, whose names follow the naming rules; the editor's library re-exports them: the inspector's rows are `…FieldRow` (`ColorFieldRow`, `DropdownFieldRow`, `ReadonlyFieldRow`, …), color is spelt so (`ProjectColors`, `PrefabColors`, `gridColor`, `selectionColor`, `colorBlindSafe`; the saved settings keys are unchanged), the 3-D tag follows its subject (`Array3DMode`, `View3DMode`, `Pivot3DMode`), a command's `CommandScope` is its `CommandAvailability` (`DesignerCommand(availability:)`, `dispatch(availabilities:)`), and `WorkspaceIds.material` is `WorkspaceIds.material3D` (its id is unchanged).
- `OrbitFlyEditorView`, `HexGrid` and `HexGridModule` moved into just_editor_core (the editor's library still re-exports them), and the 3-D view's pose is `View3DPose` (was `ViewPose3D`). `GizmoConstants` and `OverlayLayout` moved the other way: they are the editor's own now, and no longer public.
- `BuiltInAssetStoreModule` has one constructor on every platform, `BuiltInAssetStoreModule({String? root})`: the test seams moved to the native-only `BuiltInAssetStoreModule.forTest(root:, sources:, cacheDir:, pub:)`, the `sources`, `cacheDir` and `pub` fields are private, and `controllerFor` is internal. The web stand-in no longer takes `cacheDir`.
- The editor's own modules take their project folder from the scope (`EditorScope.projectRoot`, the working folder when the scope was given none): `BuiltInMaterialsModule.make`, `BuiltInGraphics3DModule.make` and `BuiltInAssetStoreModule.make` pass it as `root:`. `BuiltInEditorModule.make` is new, and `JustGameEditorPlugin.builtInsFor` lists `.make` for all four.
- The editor's checks reach Problems as `BuiltInEditorModule.validators`, and the Problems dock runs `scope.validators` only: a module registered with the id `editor` now replaces them too.
- `ModelCooking.isStale` returns a `Future<bool>` (it reads the model without stopping the editor). `ModelCooking.saveSettings`, `cook` and `uncook` throw an `UnsupportedError` for a package's model; `ModelCooking.isWritable` says which are not. `ModelThumbnails.forget` is new.

### Added

- The inspector shows a 2-D collider's **Reflectivity** (its Rays group, 0 to 1): how much of a ray the engine's `RayTracer2D` bounces off it. It is saved with the scene; a collider saved before it existed absorbs rays (0).
- `physicsShape` fields have an **Offset** row: a circle's centre, and where a capsule sits on the body.
- Before an Asset Store update or uninstall replaces a folder holding files changed by hand since the store installed it, the preview names those files (`AssetStore.withLocalEdits`), and afterwards a notice says where they were kept (`InstallResult.trashFolder`, under `.editor_trash/store/`).
- `tool/test_gpu.dart` runs the tests that draw with Flutter GPU (the 3-D material pictures, the model thumbnails), which skip themselves in a plain `flutter test`; README and CONTRIBUTING name it.
- A `perf` test tag (skipped by default; `flutter test --tags perf --run-skipped`) puts ceilings on a scene revision, the problem scan and a rename frame at 5,000 entities (`test/perf/`).
- **Input action pickers in the inspector**: a field of the engine's input action kinds (`InputDefinitions.actionType`, `actionListType`) is a searchable dropdown of the actions the project's input assets have (every `.input.json` under `assets/`, read with just_inputs through the engine, and read again when one changes on disk), each shown with its maps and its type; a list of them is chips with an Add picker. A name no asset has stays shown and marked ("not an input action", a warning beside it), so opening the inspector never rewrites it, and a name can still be typed for an action not made yet; a project with no input asset types the name in a text box. The editor needs nothing of the Input Actions editor for it (`inspector/input_action_field_editors.dart`: `InputActionFieldEditors`, and `ProjectInputActions` as `scope.inputActions`).
- **The project's pinned Flutter.** `just` pins one exact Flutter per project in `just.json` (`"flutter": "3.47.9"`), as 3-D draws with Flutter GPU, which changes between Flutter versions. When the editor runs on another (`FlutterVersion.version`, else the `flutterVersion` of `.dart_tool/package_config.json`), it says so: a warning in the Console at start (category `project`), an entry in Problems whose **Copy command** button copies `just sdk install`, and a message that stays until dismissed, once per pinned version (`editor.flutterPin.shown` in the editor's preferences). The fix: `just sdk install` in the project folder, then `just run --editor`. No pin, or one that is not an exact version, says nothing. The files are read once per session (`project/flutter_pin_check.dart`: `FlutterPinCheck`, `FlutterPinMismatch`).

### Changed

- **One folder per feature.** `lib/src/` was `core/`, `extension/`, `ui/`, `debugger/` and `integration/`; it is now 24 features — `asset_store`, `assets`, `audio`, `camera`, `chrome`, `docks`, `entities`, `graphics` (`graphics_2d/`, `graphics_3d/`), `inspector`, `level_designer` (`level_designer_2d/`, `level_designer_3d/`), `level_map`, `materials` (`materials_2d/`, `materials_3d/`), `physics` (`physics_2d/`, `physics_3d/`), `play`, `plugin`, `prefabs`, `problems`, `project`, `scene_tree`, `scenes`, `tags`, `tileset`, `timeline`, `viewport` — in eight layers with no import loop between them, each with one barrel; the public libraries export the barrels with `show` lists. `test/library_layout_test.dart` guards the layout. The public libraries' names are unchanged apart from the renames above; no dependent imported a `src/` path.
- The editor's own scope services are one extension per feature: `ScopeEntities`, `ScopeDocks`, `ScopeLevelMaps`, `ScopePrefabs` (was `EditorScopeServices`); placing prefabs with the entity operations is `EntityOpsPrefabs`, in `prefabs/`. `TimelineSession.of`, `Collider2DEditSession.of` and `ProblemScan.of` keep their object with `EditorScope.service`, and the Level Map's documents resolve paths against the scope's project folder.
- `JustGameEditorPlugin` keeps its state, lifecycle and public API in `plugin/just_game_editor_plugin.dart` (3,482 → 1,460 lines); its other jobs — the Level Designer, keys, asset drops and reloads, authoring, rendering, the panes, the game preview, the selection, the scene session, settings, visibility, hot reload — are in parts beside it, unchanged. The other classes over 1,000 lines (`TimelineSession`, both material windows, the scene tree, the Assets dock, `LevelDesignerSession`'s private parts, the settings dialog) are split by their sections the same way.
- One text prompt: the scene, tag and layer names and the timeline, tileset and Tiled prompts all use just_editor_core's `showEditorPrompt` (`promptSceneName` and `promptTimelineText` are gone). The timeline's prompts now look like the editor's other dialogs; a scene-name prompt pressed Enter on while still empty shows why it cannot be empty.
- Internal names follow the naming rules: the 2-D and 3-D twins say so (`Gizmo3DPainter`, `Gizmo2DHitTester`, `Gizmo3DHitTester`, `Gizmo2DDragSolver`, `Gizmo3DDragSolver`, `Select2DTool`, `Measure2DTool`, `Collider2DEditSession`, `Material3DWorkspace`, `Material3DPictures`, `Material3DPreset`, `Graphics3DInspectors`), the tag follows its subject (`Collider3DOverlay`, `Translate3DSnaps`, `Level3DChecks`, `BuiltInDesigner3DContributions`, `Shape3DPrefabs`, `Shape3DPictures`, `Shape3DRayTest`, `Shape3DSizeHandles`, `Collider3DSizeHandles`, `Polygon3DHandles`), one word per family (`TilesetWorkspace`, `JsonWorkspace`, `StoreWorkspace`, `LevelDesignerPanel`, `AssetsDock`, `AnimatorDock`, `SearchDock`, `DockArea`, `NewSceneDialog`, `EditorOverlay`, `TimelineScrollbar`, `CollisionShapeEditor`, `DockResizeHandle`, `TileStampTool`, `TileTerrainTool`, `TargetFieldRow`), extensions are `<On><Feature>` (`ScopeSplitViews`, `CommandContextEditor`, `EngineDebugger`, `BuiltInPhysics3DContributions.isFor`), and color is spelt so in identifiers (`ColorSwapsEditor`, `spriteColors`, `lightColor`, `TextureRole.color`, whose label stays "colour"). Files are named after their class.
- The editor's checks live in their features: `SceneChecks` (`problems/`, was `BuiltInValidators`) and `LevelMapChecks` (`level_map/`); the dock ids are `DockIds` (`docks/`); the workspaces' definitions are `TilesetWorkspace.definition` and `JsonWorkspace.definition`; `GamePreviewStyle` is in `camera/`; `BuiltInPrefabs.newLevelMap` returns `LevelMapProvision.blankMap`.
- The viewport's look (grid, selection colour, handle size) follows the settings through the overlay's `EditorMetrics.apply`, which now drives `ViewportLook` too; `ViewportLook.apply` is gone. The asset index is just_editor_core's `scope.assetIndex`, and the editor's own scope services are made with `EditorScope.service`.
- Requires just_game_engine ^2.0.0.
- Requires just_graphics_engine ^0.1.0 and just_tiled ^0.5.0. The 3-D views, model thumbnails and material pictures use just_graphics_engine's new names (`Render3DScene`, `Render3DView`, `Render3DViewMode`, `Material3DOverride`, `Shape3DMesh`, `Shape3DUv`); a model's lights take their kind as the model has it (`Light3DData.kind`, which is the engine's `Light3DKind`); Tiled maps are read through `TmxParser` and a `TiledFileProvider`.
- Depends on just_graphics_engine directly (it was a dev dependency): model cooking and glTF import, thumbnails and the material previews use the parts of it that the engine's 3-D library no longer re-exports.
- Requires just_colours ^0.2.0 and just_debugger ^0.1.0: the debugger binds through `JustDebuggerController.bind` (`bindToSources` is gone).
- Requires just_asset_store ^0.3.0. Planning an uninstall searches the project for everything that goes with the item in one pass, on another isolate (`AssetStore.planUninstall`), so the store window no longer stops while it reads the project; it says "Reading the project" meanwhile, and its buttons wait.
- A cooked model is stale when any file its model refers to changed (a `.gltf`'s buffers and images, found with `modelFilesOf` and stamped with `cookStamp(files:)`), not only the model file and its settings; one that is missing cooks it again. Cooks made by just_graphics_engine's dev releases (0.1.0-dev.1 and dev.2) are cooked again as a project opens.
- Rays are just_dart 0.3.0's `Ray3D` (was `Ray3`), through the engine, in the 3-D gizmos, snaps, picking and Level Designer checks (`Gizmo3DDragSolver.adjustMove`, `Translate3DSnaps.adjust`, `ModelRayTest`, `Shape3DRayTest`).
- A scene that names a component or field a package has renamed opens with the new names, whatever its format (just_game_engine_formats 0.3.0 applies the renames at every load); the log says so, and a save keeps them. The 3-D material actions use `Material3DFile.isMaterial3DPath`.
- Uses just_physics_engine 2.0's names, through the engine (`Physics2DBody`, `Shape2D`, `Circle2DShape`, `Body2DType`, …); the system that holds a dragged body still while a play-test runs (`JustGameEditorPlugin(bindPhysicsBodies:)`) is `Physics2DBodyBindingSystem`. Nothing behaves differently.
- Uses the engine's new component names (`RigidBody2DComponent`, `Light3DComponent`, `Circle2DComponent`, …), in the inspector, the viewport handles and the material users.
- Converts colours for the 3-D material previews with the engine's `LinearColor.of` (was `GraphicsShapes.linear`).
- Follows the engine's feature layout: the 2-D material stage's world has the built-in components, and 3-D graphics is given as a service (`EngineConfig(services: [Graphics3D()])`).
- Collider outlines are drawn by the engine's `Collider2DDebuggerSystem`, which the editor puts in the game's world while it shows colliders: the same colours and filters as before, drawn above the scene's sprites and shapes rather than under them.
- Colour keys added, moved, pasted or recorded in the Timeline get even-paced handles, as the engine blends colours.
- Opening a scene lets go of the 3-D models, material files and maps only the scene left behind used.
- 2-D material files, a preset's included, are saved in 2-D material format 2, which keys a colour value `color` (`tint.color`, `dissolve.edgeColor`); a format 1 file opens as before and is saved as format 2.
- The heartbeat that tells `just` the editor has the project open (`.dart_tool/just_core_cli/editor.lock`) is written through just_game_engine_formats' `EditorHeartbeat`, the class just_game_engine_cli 0.2.0 reads it with, so the two no longer keep its path and timings in step by hand. The file holds JSON, `{"pid", "beat"}`, written again each beat (it held the process ID, and was touched). Depends on just_game_engine_formats ^0.3.0 directly.
- `lib/src/asset_store/store_checks.dart` and `ui/item_details.dart` are formatted, so `dart format --set-exit-if-changed lib` passes.
- The tests mirror the features (`test/<feature>/`) and are named by what they test, with no review ID in a name: `play_and_lifecycle_safety`, `scene_open_safety`, `scene_manager_safety`, `prefab_safety` and `refactor_prefabs` are `play_and_lifecycle`, `scene_open`, `scene_rename_copy_delete`, `prefab_file_changes` and `prefab_rewrites`; `level_designer_3d_tools`, `level_designer_gestures`, `selection_ops`, `level_map_background_work`, `map_files`, `scene_tree_and_inspector`, `tileset_editing`, `gizmo_bounds` and `gizmo_snap` were `*_fixes`, `*_audit`, `*_safety` and `*_probe`; `timeline_fixes`, `material_safety` and `refactor_safety` are `timeline_files`, `timeline_preview_and_edits`, `timeline_renames`, `material_files_and_images`, `tag_refactor` and `layer_refactor`.
- Tests wait for what they need, not for fixed real time (the Asset Store's; the 2-D normal-map test); a scene-manager test that asserted nothing checks the files are untouched, and the camera rig's drawing test checks what is drawn; a model pictured again once it changed has a GPU test.

### Fixed

#### Scenes, saving and play-testing

- **Hiding the editor (F1) over a scene** keeps the level as authored, as Play does: the game runs on it while the editor is hidden, a save meanwhile (autosave, or Ctrl+S once shown) writes the level as it was, and showing the editor puts it back. Before, the simulated level — fallen bodies, taken pickups, what the game made — was saved into the scene.
- **A save marks the scene saved as of what it wrote:** an edit made while the files are written — a gizmo let go, a field committed — leaves it unsaved. It was marked saved after the writes, with the file holding the state before the edit. Autosave also waits while a gizmo is dragged.
- **Saving** is one save at a time, its map files included: Ctrl+S during an autosave no longer writes the same map files at once through the same temporary files.
- **Autosave waits while a scene is being opened**, from its first question: after Discard, the recover-a-backup question no longer gave autosave time to save the discarded changes.
- **Declining a recovered backup** sets aside every unsaved backup of the scene, not only the newest: the older ones were offered again on each open.
- **Closing the window with unsaved changes asks first**, in the editor's own dialog — Save, Don't save or Cancel — the map files the scene edits included, after any save under way; with nobody to ask (the editor's window gone), a backup is written.
- A scene saved by an earlier editor with a child of an unnamed parent opens with the child under that parent again, not as a root: the parent gets back the name its children were saved with (`SceneCodec.nameUnnamedParents`), the log says how many, and a save keeps it. A scene saved now writes such a parent's name (`entity_<id>`).
- **The Scenes list** reads each scene's summary through the store's one cache; a second cache here looked at every scene's file twice on each refresh.
- **Undo and redo during a play-test** reach only what was done in it: the keys, the toolbar and the History dock cannot undo a step from before Play (a tile stroke on a map file), which Stop did not put back while the restored history called it done, nor fold a play-time edit into one.
- **Stop keeps the selection alive:** an entity play destroyed is selected as Stop made it again, and one the play-test made is let go of. The inspector edited a destroyed entity, recording undo steps that changed nothing.
- **Play, Restart and Stop wait for a drag to end** (a designer gesture, a ruler guide, a gizmo drag), as Save and Undo do: Play captured the level half-edited and the drag then committed into the play-test.
- **Play from here** moves nothing when Play did not start (a spawner threw); it moved the authored player for good.
- **The game camera preview** is not drawn over the four 3-D views (it drew the level a fifth time each frame), and it, a typed gizmo value and the panes' labels let go of the text they lay out at once.
- **Starting the editor** before its engine has started does nothing, and it starts when the engine it is registered with has; a start that fails takes back what it did and can be tried again. It was marked started first, and left half-started for good.
- **`syncModules`** disposes a module replaced by one of another class once, not twice.
- A generated registry (`lib/editor/store_modules.g.dart`, `lib/game/store_extensions.g.dart`) that differs only in its line endings, such as one git checked out with CRLF, no longer asks for a restart.
- **The Asset Store's Restore** says why it failed (no network, a lock held by `just store`) instead of throwing out of the button.

#### Prefabs and entities

- **A prefab instance a play-test destroyed** comes back on Stop as an instance — its parts linked to its top, the top holding the instance as loaded — so the next save writes one `prefab` entry again; it came back as plain entities and was saved unpacked, no longer following its prefab. A part that survived links to its top made again. A prefab file that changes on disk during a play-test (or while the editor is hidden) is made again in the scene once the level is back, from the level as authored.
- **Prefab Apply, Revert, Unpack, Make and Edit wait for Stop** during a play-test, the log saying so; the inspector's buttons and the `editor.prefab.*` commands are off, and the section does not count the game's changes. Apply wrote what the game had done to an instance (a health run down to 0) into the prefab every scene uses.
- **The inspector's prefab section** reads the instance afresh on every change: an Unpack within the inspector's cool-down after another change threw in its build. What an instance changes is worked out once per undo step, not on every pointer move of a drag.
- The prefab inspector counts each added component, now that a prefab instance lists them per entity (just_game_engine_formats 0.3.0); it counted the entities with any.
- **Entity operations** never act on a selected entity that is gone.
- **A paste at the top level** (the scene tree's, or the viewport menu's outside the Level Designer) is on no map layer: a map member copied kept its layer number, which the Level Map check flagged.
- A change made by a fix or a refactor (moved collision layers, renamed tags, a spawn point's spawner, a sky preset, a collider's shape, the physics checks' fixes) names the field it writes (`ComponentFieldCommand(field:)`), so edits of two fields are never merged into one undo step. From just_editor_core too: Group keeps the group where the first of what it holds was (inside its parent; under a Level Map, on its layer), Space is saved by name in the shortcut settings, the inspector's undo steps name the row or group when two fields share a label, and the project's tag list reads the other scenes' tags in the background.

#### Viewport and Level Designer

- **Picking in the 2-D viewport:** a click picks what is drawn on top — by layer, then z, as the renderer and the Level Designer order them — not whatever the world lists last; the right-click menu acts on it too. A platform on layer 10 over a backdrop on layer -10 is the platform.
- **Esc in the quick bar's step and grid rows, or in its gizmo menu,** puts them away and only that: it also cleared the selection.
- **The viewport's right-click menu** is about the tiles selected only while Select tiles is in hand; under any other tool it is the entity's again, though a tile selection is left over. In the Level Designer its **Paste here** and **New entity here** put the entity under the Level Map, on its layer at the depth placed at, as Draw does; they made root entities, hidden and out of reach at once.
- **Level Designer, what is under a parent:** a resize (by a handle or typed) and an angle typed for a parent leave what is under it where it is in the world, and a flip mirrors it with the parent. What is under it no longer jumps by what the parent did at Play, or at the parent's next settle (a value typed in the inspector, an undo), with the jump saved and no undo step for it — done, undone and redone alike.
- **Level Designer, pieces of a map:** tiles made an entity (Select tiles → Make entity) have the size of their tiles. A piece is picked by its tiles, not only within 12 pixels of its corner; a marquee sweeps it; its gizmo and rotate ring sit on its tiles; snapping, Align, Frame and the minimap see it; and the eraser takes it, never the whole map.
- **Level Designer, map layers:** Raise and Lower move a map layer past the one drawn next to it at its depth — the two trade their z and their place in the list — and are offered only when there is one. They no longer reorder the list when that changes nothing drawn, nor record an undo step that undoes nothing.
- **Level Designer, the rotate ring:** a drag round the ring too small to make a step turns nothing and keeps the selection; only a press that never moved 3 pixels is a click on what is under the ring. Before, a turn under half a step (7.5° for entities, 45° for tiles) was replayed as a click where the pointer was let go, dropping or replacing the selection.
- **Level Designer, placing:** a prefab file drawn with Draw goes under the Level Map, on its layer at the depth placed at, the map and the layer made for it in the same undo step, like anything else drawn. In a scene with no map it was a root entity, hidden and out of reach at once.
- **Level Designer, keys:** Esc while a ruler guide is pulled lets the guide go and keeps the selection (it cleared the selection and left the guide being pulled); so does the Cancel command on whatever key it is bound to. A tool's keys act once a press: holding Z with the Stamp turns the brush once, not on every repeat; held, X and Y no longer flip it back and forth, V no longer cycles Select tiles' modes, G no longer cycles the fill shapes.
- **Level Designer, a lost release:** a press that arrives while a gesture is still open — its release lost to a window that lost focus, or to a second pointer — ends that gesture first, as Esc would. Place (3-D) and Paint material keep what such a gesture made as its own undo step instead of leaving it in the scene with none, and a stamped trail is recorded though the prefab was put down before its release.
- **Align and Distribute** record no undo step, and do not mark the scene changed, when the selection is lined up already; they line a piece of a map up by its tiles.
- **Convert to a tileset** never writes over a `.tileset.json` already there, which may have been edited since: the new one goes beside it, numbered (`forest_2.tileset.json`), and the log says so. `TiledImporter.convertTileset` takes `warnings:` for that. Tiled imports, conversions and exports write their files whole or not at all, as every project file is saved, and the Assets dock sees a converted tileset at once.

#### Scene tree and inspector

- **Renaming an entity in the scene tree** (F2, the slow second click, Rename in its menu) takes the inline timelines' tracks bound to the old name along, in the same undo step, as the inspector's header did; it left them bound to a name nothing had.
- **Scene tree:** a rename armed by a click on the selected row is taken back when another row is clicked, or the selection moves elsewhere, before it opens — the box no longer opens on a row that is not selected. Home, End, and ↑ with nothing selected land on the nearest row that can be selected in the key's direction, past map-layer rows and what is out of reach (they did nothing when the edge row was one of those).
- **Scene tree, cost per edit:** a scene revision — every pointer move of a gizmo drag — no longer walks the whole world to learn whether the rows changed. That is looked at once after an undo step, when entities come or go, and after a still moment; otherwise at most every 250 ms. The filter chips are gathered when it changed. Each row reads its problem mark, and the Problems filter its entities, from the scan's index (`ProblemScan.problemsFor`, made once a scan), and the scan due once the scene is still runs between frames, not in a build.
- The inspector's header lets go of the text layouts it measures its tag chips with at once, not when the collector finds them.

#### Timeline

- **Timeline, an entity renamed:** undoing or redoing the rename renames the tracks of the inline timeline as it is then. It put back a copy taken at the rename, losing every key added in the Timeline since, with no way back.
- **Timeline, the ruler:** a play-range drag whose pointer is cancelled (the window loses it) is still one undo step; the player's range was changed with none. A press that arrives while an earlier drag was never let go closes that drag first.
- **Timeline, Make relative / Make absolute** converts the track's keys by the field's value in the scene (not the value a preview shows), as one undo step, so the animation plays where it did; it reinterpreted them, moving the entity.
- **Timeline:** its session lets go of its signals when the editor does.

#### 3-D models and materials

- **3-D models from packages** (`packages/<name>/…`, an Asset Store item or pub's cache) are read where the package is: they have a picture, open in the Model window — read-only, never saved — and can be placed, and the game in the editor reads a kit installed since the app was built. Their settings and cooked copies are never written (`ModelCooking.saveSettings`, `cook` and `uncook` refuse them; `ModelCooking.isWritable`), so no stray `packages/…/*.import.json` is made in the project.
- **Model cooking** writes the cooked copy and the settings whole or not at all: a cook cut short leaves the copy that was there, not a truncated `.jmodel` the game cannot load and the editor never cooks again. A cooked copy that cannot be read (held by another program) or is no cooked model is cooked again rather than stopping the session's check of the rest; its header is read only after its first bytes say it is one, and never past the file's end.
- **The Model window:** a model only looked at is no longer "unsaved" (it asked to save on close, and Save cooked it); a model with no settings yet has a Cook button. A Save the window is closed during still cooks. Whether the cooked copy is out of date is found after the window opens, without reading and hashing the model before its first frame.
- **3-D graphics module:** disposed with the editor, it lets go of its model pictures and of the game's model reader; a model changed on disk is pictured again and the older picture let go (each model kept one picture per change before); picking lets go of a model's triangles when it is loaded again.
- **Layered 3-D materials:** a layer slot cleared between others (a vertex colour's channel left empty, saved as `""`) draws nothing; the material's picture and the window's preview failed with a file-system error. With just_game_engine_formats 0.3.0 the Problems dock no longer flags such a file, and with just_game_engine 2.0.0 the game draws nothing in that slot either.
- **3-D material window:** Save keeps keys a material file does not know (a note added by hand, another tool's key), and Apply to parent keeps the parent's; they were dropped.
- **2-D material users** in scenes and prefabs saved before scene format 11 (`Material2D`, `CircleComponent`, a light's `colour`) are found and drawn: Auto and the Assets dock's 2-D pictures showed the sample sprite instead.
- **Material caches belong to the editor:** what draws with each 2-D material and the material files the inspector reads are kept by the materials module and let go with it, and which material cards are folded is kept per editor, as are the meshes the palette pictures 3-D shapes with — none of them for the life of the process. The inspector's material editors no longer look at the disk on each build of a drag when the asset index knows the file.
- Saving a picture a 2-D material uses, such as a normal map, shows the new picture instead of drawing with a released one.
- Saving a 3-D scene's skybox picture shows the new sky at once.
- The materials tests no longer leave `jge_material…` / `jge_variants…` folders in the temp folder on Windows: a 2-D variant's window is let finish reading its parent before the test ends, and a folder that can't be removed fails the test, naming it.

#### Physics, docks and assets

- **`physicsShape` fields:** editing a circle's radius keeps its centre, and editing a capsule keeps where it sits on the body (both were moved back to the body's origin, and saved so).
- **The collision layer pickers** count each layer's bodies once per undo step while authoring (once per change during a play-test), not on every pointer move of a drag.
- **The JSON viewer** scrolls sideways: a line wider than the window is shown whole, not cut at its edge, and a match past the edge is scrolled to.
- **The World dock** is built again when the scene changes, at most every 100 ms; only during a play-test, or while its Systems tab shows their times, does it look twice a second. Its filter reads each entity's text once per change.
- **The editor's sprite loader** hands each caller its own copy of an image and lets go of — and disposes — the sheets and atlases that neither of the last two scenes opened asked for, and what it evicts or clears; before, every sheet decoded in the session stayed, and evicted images waited for the collector.
- **The Profiler's frames** are kept per editor and disposed with it.
- **The History dock's undo notifier** is the editor's scope's (`BuiltInDocks.historyOf`), disposed with the editor; it was held per editor in a static `Expando` and never disposed.
- **Problems:** each entity's problems are read from an index made once a scan (`ProblemScan.problemsFor`), and the Problems dock runs the scan between frames, not in its build.

### Removed

- `PlanarEntityPicker`, which nothing used (2-D picking goes through the gizmo hit tester), and its two tests.
- `GizmoConstants` and `OverlayLayout` are the editor's own (in `viewport/gizmos/` and `chrome/`), as noted under Breaking.
- `promptSceneName` and `promptTimelineText` (one prompt now, `showEditorPrompt`) and `ViewportLook.apply` (see Changed).

## 0.1.0-dev.2

- **Tags.** The Asset Store shows where each item comes from (Official, Third Party, Unlisted, Local) and how finished it is (Beta, Experimental, Deprecated; stable shows none). Experimental items are listed once "Show experimental" is on, deprecated ones only to a search; installing either says so first, and an installed deprecated item is a warning in the Problems dock, naming what replaces it. The editor shows its own stage, Beta, on its start card (`EditorRelease`).
- **A tidier store page.** Cards have a 16:9 picture (marked when the item is installed or has an update), a line about the item, and one row of tags; a kind with nothing to show has no chip; the grid sorts by name or by the newest release. The details show the item's pictures with a strip to pick one, a version menu (install or switch to an older version), the version's date, size, licence and catalog by name, what it needs (another store item opens on a click), and links to its store page, its source and the report form. When no catalog can be read, the page says why and offers to try again, to show what is installed, or to open Sources. The Installed page lists items no catalog lists too (a checkout of your own, or everything while offline), as their own manifests describe them and with their own pictures; a checkout of your own shows no empty button bar.

- **The Asset Store is part of the editor.** `BuiltInAssetStoreModule` (in `asset_store.dart`) comes with every game's editor, as the materials do, so plugins, kits, art and sound can always be added from inside it: the shop button under the transform tools (always shown, with its tile and tip on the start card), Ctrl+Shift+G (Cmd+Shift+G on macOS), or *Get assets from the store* in the Assets dock. It takes the place of the `just_asset_store_editor` package, which is retired. The editor now depends on `just_asset_store` ^0.2.0, the store's core: plugins and kits it installs go into `plugins/{category}/{name}/`, content into `packages/{category}/{name}/`.
- **WebAssembly again.** The 3-D graphics files reach files through `package:just_editor_core/io.dart` instead of `dart:io`, so the package is wasm-ready again; the store's own files never compile on the web (an empty module stands in for it there).

## 0.1.0-dev.1

First release: a level editor that runs inside a `just_game_engine` game in a debug build. The package compiles on every Flutter platform (web and wasm too); editing runs on Windows, macOS and Linux. Elsewhere, and in a profile or release build, `JustGameEditorPlugin.register` returns null (`supportsPlatform` says why) and the game runs on its own. Needs `just_game_engine` ^2.0.0-dev.2, Flutter 3.47.1 and Dart 3.11.

### Getting started

- `JustGameEditorPlugin.register` makes the editor for a game's engine, with the game's modules, spawners and hot reload hook; `JustGameEngineEditor` shows the game with the editor over it, and is a plain `GameWidget` when there is no editor.
- Built on `just_editor_core` (the module contract, the scope, undo, the inspector's rows, the UI kit), re-exported by the package's library.
- The editor's own tools come as modules, `BuiltInEditorModule`, `BuiltInMaterialsModule` and, for a game with 3-D graphics, `BuiltInGraphicsModule`, registered ahead of the game's (`JustGameEditorPlugin.builtInsFor`).

### Scenes and play-testing

- Scenes are JSON files in `assets/scenes/`, with the play order in `scenes.json`; the game loads the same files through the engine's `SceneLoader`.
- Files of an earlier scene format are migrated as they open; components no registered definition reads are kept and written back unchanged.
- New scene (2-D or 3-D) writes the same starter scenes as `just game scene new` (`just_game_engine_formats`).
- A start card when no scene is open, and a Scenes panel: search, sort, play order by drag or Alt+↑/↓, rename, duplicate, delete, keyboard control.
- Autosave with backups in `.editor_backups/`, recovery of unsaved changes on open, and the last session reopened on start.
- Play-testing in place: Play, Pause, Step, Restart and speed, a game-camera preview (F4), and the authored level put back exactly on Stop.
- The editor tells the `just` tool it has the project open (`.dart_tool/just_core_cli/editor.lock`), so `just game scene` and `just upgrade` wait for it.

### Viewport and scene tree

- All, Move, Scale and Rotate (Q, W, E, R); moving a parent carries its children; each gizmo drag is one undo step.
- Snapping: one switch, move, rotation and scale steps, smart snapping to entities and guides; Ctrl (Cmd on macOS) suspends it mid-drag.
- Gizmos shown or hidden per mode (editor, Level Designer, play-test), each kind on its own.
- The scene tree on the editor's one undo stack: re-parent, reorder, group, rename, enable, hide, lock, isolate, colour labels, and filters by component, tag, layer or problem.
- A right-click menu on the level; files dragged from the Assets dock become entities where they land. One that goes in the other kind of scene — a model in a 2-D scene, a sprite in a 3-D one — is turned away with a message saying where it goes.

### 3-D scenes

- An orbit-and-fly view, a 3-D gizmo (in world or local axes), picking by ray, a grid on the working plane, and placement on surfaces.
- A 3-D Level Designer with a built-in Default 3D kit: marquee select, a working plane, Place with a ghost, arrays, size handles for the eleven built-in 3-D shapes and for colliders, groups, view modes and a view cube, bookmarks, a slice plane, four views, a material paint tool, prefab files with overrides, and level aids (ruler, level checks, a performance meter, Play from here).
- 3-D physics when the engine has `Physics3D`: collider and character outlines, material presets, Solid and Trigger variants of every shape, and Problems checks.
- 3-D graphics when the engine has `Graphics3D` (`BuiltInGraphicsModule`, in `graphics.dart`): models (`.glb`, `.gltf`) in the Assets dock with rendered pictures, dropped into 3-D scenes, opened in a Model window of their import settings and cooked (`ModelCooking`), or placed with their lights and sockets as entities; picking by triangles; light markers, a selected light's reach and a selected camera's frustum; Model, Light and Environment inspector sections with sky presets.

### Inspector

- Built from each component's runtime `ComponentDefinition`, with an editor for every field type; vectors and related numbers in one row, lists and maps as rows, references as pickers.
- Cards that can be rearranged (Transform first), saved with the entity's component order.
- A typed value is kept when a field is left (Enter, Tab or a click elsewhere); Esc puts back what was there.
- A colour picker beside the field, live in the scene, with gradients, project palettes and an eyedropper.
- Tags from `assets/project/tags.json`, with tag and target pickers.
- Physics, 2-D and 3-D alike: body type, material presets, Fit to visual, collider editing in the viewport, named collision layers and a collision grid (`assets/project/physics.json`), a live readout while playing.
- Virtual cameras: previewed while authoring, frames, zones and confiners drawn in the viewport, Solo camera, and a dolly track tool.

### Level Designer

- Tools: Select, Draw, Paint, Sample and Measure, with rulers and guides, a minimap, view bookmarks, align, distribute, duplicate and array.
- The Level Map: one tile map per scene, painted with Stamp, Terrain, Fill, Erase and Select tiles, on orthogonal, isometric, staggered and hexagonal maps; placed entities go on its layers.
- LAYERS and TILESET panels, a built-in Basic shapes tileset, and a Tileset Editor for collision, animation, properties and terrains.
- Tiled: import `.tmx` and `.tmj`, convert `.tsx` and `.tsj`, export any map.
- A designer switch: a module can bring a Level Designer of its own (prefabs, tools, layers, grid).

### Sound and 2-D lighting

- Sound sources and the listener as markers, a selected source's reach drawn in the viewport, an Audio group in the Add menu, and an audio file dropped on the viewport becomes a source. Sound plays only in a play-test.
- 2-D lights and the scene's lighting as markers, a light's reach and a spot's cone drawn, a Lighting group in the Add menu, Shift+L to see the scene unlit, and a check for lights with no Scene lighting.

### Materials

- 3-D and 2-D material files pictured in the Assets dock; New material, New 2D material, New screen material and New variant.
- The 3-D and 2-D Material windows, alike in layout and keys: the material's values in cards on the left, a live preview under one toolbar, presets and variants. The 2-D window adds effects from a grouped, searchable Add effect menu.
- A material being edited is drawn live in the open scene; a material dropped on what it draws is one undo step; Level Map layers take a 2-D material.
- Problems checks for materials, with fixes; materials made from texture sets and from a model's own; normal maps made from a picture (`NormalMaps`, in `materials.dart`).

### Docks and settings

- One tabbed dock panel: Console (with a command line), Assets, Timeline, Profiler, World, Problems, History, Animator, Search, Tags and Physics Layers. Tabs reorder, docks pop out, and the layout is remembered.
- The Assets dock opens every file: a scene as the scene, a file in its module's window, and any other JSON file in a read-only JSON window.
- Timeline: dope sheet, curve editor, Record, markers, work and play ranges, motion paths in the viewport, and a preview that never reaches a save.
- Problems: what is wrong with the open scene, many with one-click fixes.
- Settings (Ctrl+,): appearance, accessibility, editing, snapping, viewport, saving, play-testing, Console, performance and every command's keys, searchable, exported and imported as one file.
- Accessibility: text size, bolder text, high contrast, colour-blind safe colours, reduced motion, longer timings, bigger targets and a visible focus ring.
- On macOS the shortcuts use Cmd, and Backspace deletes.

### Hot reload

- A hot reload brings the game's wiring (`register(onReassemble:)`), the component definitions, every registry, the Level Designer's tools and the built-in docks up to the code; a field added to a component shows in the inspector.
- `EditorModule.onRegister` runs once per module, `onReassemble` after each hot reload; definitions, prefabs and styles are getters, so a reload updates them.
- A hot restart starts the editor clean.
