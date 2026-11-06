// The palette's pictures of 3-D shapes: one set per editor, keeping its
// own meshes rather than the process's.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_3d/shapes/shape_3d_pictures.dart';
import 'package:just_game_engine_editor/src/level_designer/level_designer_3d/shapes/shape_3d_prefabs.dart';

import '../support/test_scope.dart';

void main() {
  test("each set of pictures keeps its own meshes, one per shape", () {
    final cube = Shape3DPrefabs.all.first;
    final one = Shape3DPictures(), two = Shape3DPictures();
    expect(one.picture(cube, 32), isNotNull);
    expect(one.keptMeshes, 1);
    expect(two.keptMeshes, 0, reason: 'not shared through the process');
    one.picture(cube, 48);
    expect(one.keptMeshes, 1, reason: 'one shape, one mesh');
  });

  test("the editor's module brings one set, and another editor another", () {
    final a = BuiltInEditorModule(testScope());
    final b = BuiltInEditorModule(testScope());
    expect(a.prefabPictures, same(a.prefabPictures));
    expect(a.prefabPictures.single, isNot(b.prefabPictures.single));
  });
}
