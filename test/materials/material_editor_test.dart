// Materials in the editor: the kind and workspace a `.material.json` gets,
// a new one made in a folder, the workspace's own undo and save, and a
// material dropped on a shape or a model drawing it with that file.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late BuiltInMaterialsModule module;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_materials');
    addTearDown(() => dir.deleteSync(recursive: true));
    module = BuiltInMaterialsModule(root: dir.path);
  });

  test('a material file is its own kind, opening in its workspace', () {
    final scope = EditorScope(world: World()..initialize(), modules: [module]);
    addTearDown(scope.dispose);
    const path = 'assets/materials/stone.material.json';
    expect(module.materialKind.matches(path), isTrue);
    expect(AssetKind.of(path).id, 'material');
    expect(AssetKinds.active.filters.map((k) => k.id), contains('material'));
    final workspace = module.workspaces.firstWhere(
      (w) => w.id == BuiltInMaterialsModule.workspaceId,
    );
    expect(workspace.id, BuiltInMaterialsModule.workspaceId);
    expect(workspace.matchOf(path), greaterThan(0));
    expect(workspace.matchOf('assets/models/crate.glb'), 0);
    expect(
      module.assetActions.map((a) => a.id),
      contains(BuiltInMaterialsModule.newMaterialId),
    );
  });

  test('New material makes one, never over another', () async {
    final first = await module.newMaterial('assets/materials');
    final second = await module.newMaterial('assets/materials/');
    expect(first, 'assets/materials/material.material.json');
    expect(second, 'assets/materials/material_2.material.json');
    final made = MaterialFile.parse(
      File('${dir.path}/$first').readAsStringSync(),
    );
    expect(made.validate(), isEmpty);
  });

  test('colours read and written as hex', () {
    expect(MaterialWorkspaceState.hexOf(0xFFFF8000), '#FF8000');
    expect(MaterialWorkspaceState.hexOf(0x80FF8000), '#FF800080');
    expect(MaterialWorkspaceState.argbOfHex('#ff8000'), 0xFFFF8000);
    expect(MaterialWorkspaceState.argbOfHex('FF800080'), 0x80FF8000);
    expect(MaterialWorkspaceState.argbOfHex('nope'), isNull);
  });

  test(
    'without a GPU a material has no picture, and asking never throws',
    () async {
      final path = await module.newMaterial('assets/materials');
      final pictures = MaterialPictures(root: dir.path);
      addTearDown(pictures.dispose);
      expect(pictures.peek(path), isNull);
      expect(await pictures.of(path), isNull);
      expect(
        await pictures.of('assets/materials/missing.material.json'),
        isNull,
      );
    },
  );

  testWidgets('the workspace: edits undo and redo, and Save writes the file', (
    tester,
  ) async {
    final path = await tester.runAsync(
      () => module.newMaterial('assets/materials'),
    );
    final scope = EditorScope(world: World()..initialize(), modules: const []);
    addTearDown(scope.dispose);
    final reloaded = <String>[];
    final key = GlobalKey<MaterialWorkspaceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MaterialWorkspace(
            key: key,
            path: path!,
            root: dir.path,
            pictures: MaterialPictures(root: dir.path),
            workspace: WorkspaceContext(
              scope: scope,
              onClose: () {},
              path: path,
              reloadAssets: reloaded.add,
            ),
            loadOnStart: false,
          ),
        ),
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    expect(state.dirty, isFalse);

    state.edit(state.material.copyWith(roughness: 0.1));
    state.edit(state.material.copyWith(uv: MaterialUv.world));
    state.undo();
    expect(state.material.uv, MaterialUv.natural);
    expect(state.material.roughness, 0.1);
    state.redo();
    expect(state.dirty, isTrue);

    await tester.runAsync(state.save);
    expect(state.dirty, isFalse);
    expect(reloaded, [path]);
    final saved = MaterialFile.parse(
      File('${dir.path}/$path').readAsStringSync(),
    );
    expect([saved.roughness, saved.uv], [0.1, MaterialUv.world]);
    expect(tester.takeException(), isNull);
  });

  group('dropped on the viewport', () {
    late EditorScope scope;

    setUp(() {
      final world = World()..initialize();
      Graphics3D.registerSchemas(world.context);
      scope = EditorScope(world: world, modules: const []);
      addTearDown(scope.dispose);
    });

    AssetDrop drop(Entity? onto) => AssetDrop(
      scope: scope,
      path: 'assets/materials/stone.material.json',
      at: Vector3.zero(),
      surface: SurfacePoint(Vector3.zero(), Vector3(0, -1, 0), onto: onto),
      place: (_, _) => throw StateError('a material makes nothing'),
    );

    test('on a shape: its material file, one undo step', () {
      final cube = scope.world.createEntityWithComponents([
        TransformComponent(),
        Cube3D(),
      ], name: 'Crate');
      expect(BuiltInMaterialsModule.dropMaterial(drop(cube)), isNull);
      expect(
        cube.getComponent<Primitive3D>()!.material,
        'assets/materials/stone.material.json',
      );
      expect(scope.history.undoEntries, hasLength(1));
      scope.history.undo();
      expect(cube.getComponent<Primitive3D>()!.material, isEmpty);
    });

    test('on a model: drawn with it all over; on nothing: nothing', () {
      final model = ModelComponent(model: 'assets/models/crate.glb');
      final crate = scope.world.createEntityWithComponents([
        TransformComponent(),
        model,
      ], name: 'Crate');
      BuiltInMaterialsModule.dropMaterial(drop(crate));
      expect(model.materials, {'*': 'assets/materials/stone.material.json'});
      BuiltInMaterialsModule.dropMaterial(drop(null));
      expect(scope.history.undoEntries, hasLength(1));
    });
  });
}
