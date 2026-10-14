import 'package:flutter/widgets.dart' show IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/core/scene/editor_scene.dart';
import 'package:just_game_engine_editor/src/core/state/editor_scene_state.dart';
import 'package:just_game_engine_editor/src/core/state/scene_mode_filters.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/commands/designer_command.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/overlays/designer_overlay.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/level_tool.dart';
import 'package:just_game_engine_editor/src/ui/level_designer/tools/tool_registry.dart';

class _Tool extends LevelToolHandler {
  _Tool(this.id, this.dimensions);
  @override
  final String id;
  @override
  final Dimensions dimensions;
  @override
  String get label => id;
  @override
  IconData get icon => const IconData(0);
}

void main() {
  test('a 3-D scene is edited in 3-D', () {
    final state = EditorSceneState();
    expect(state.editingMode, SceneMode.twoD);

    state.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    expect(state.sceneMode.value, SceneMode.threeD, reason: 'kept');
    expect(state.editingMode, SceneMode.threeD);

    state.closeScene();
    expect(state.sceneMode.value, SceneMode.twoD);
  });

  test('a 2-D scene shows a vector\'s x and y; a 3-D one all three', () {
    const field = SchemaField(
      name: 'scale',
      kind: FieldTypes.vector3,
      read: _none,
    );
    expect(SceneModeFilters.visibleChannels(field, null, SceneMode.twoD), {
      'x',
      'y',
    });
    expect(SceneModeFilters.visibleChannels(field, null, SceneMode.threeD), {
      'x',
      'y',
      'z',
    });
    expect(
      SceneModeFilters.visibleChannels(
        field,
        const FieldHint(channels2D: {'z'}),
        SceneMode.twoD,
      ),
      {'z'},
      reason: 'a hint can choose',
    );
  });

  test('fields and components show only where they belong', () {
    const threeDOnly = FieldHint(dimensions: Dimensions.threeD);
    expect(SceneModeFilters.fieldShown(threeDOnly, SceneMode.twoD), isFalse);
    expect(SceneModeFilters.fieldShown(threeDOnly, SceneMode.threeD), isTrue);
    expect(SceneModeFilters.fieldShown(null, SceneMode.twoD), isTrue);

    const flat = ComponentHints(dimensions: Dimensions.twoD);
    expect(SceneModeFilters.componentOffered(flat, SceneMode.twoD), isTrue);
    expect(SceneModeFilters.componentOffered(flat, SceneMode.threeD), isFalse);
  });

  test('tools, overlays and commands default to where they work', () {
    final tools = ToolRegistry()
      ..register(_Tool('flat', Dimensions.twoD))
      ..register(_Tool('any', Dimensions.both));
    var mode = SceneMode.twoD;
    tools.modeOf = () => mode;
    expect(tools.all.map((t) => t.id), containsAll(['flat', 'any']));
    mode = SceneMode.threeD;
    expect(tools.all.map((t) => t.id), ['any']);
    expect(tools.byId('flat'), isNotNull, reason: 'still registered');

    final overlays = OverlayRegistry();
    expect(overlays.all, isEmpty);

    final command = DesignerCommand(id: 'x', label: 'x', run: (_) {});
    expect(command.dimensions, Dimensions.both);
  });
}

Object? _none(Component c) => null;
