// The viewport menu in a 3-D scene: a few prefabs are listed in it; many
// are listed by category, each opening a menu of its own, and a prefab
// picked there is placed where the menu was opened.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

class _Marker extends Component {}

class _Many extends EditorModule {
  _Many(this.count);

  final int count;

  @override
  String get id => 'test.many';

  @override
  String get name => 'Many';

  @override
  List<PrefabDefinition> get prefabs => [
    for (var i = 0; i < count; i++)
      PrefabDefinition(
        id: 'thing$i',
        name: 'Thing $i',
        category: i.isEven ? 'Evens' : 'Odds',
        icon: Icons.square_outlined,
        color: const Color(0xFF26A69A),
        dimensions: Dimensions.threeD,
        build: (_, _) => [TransformComponent(), _Marker()],
        buildAt: (at) => [TransformComponent(position: Vector3.copy(at.position)), _Marker()],
      ),
  ];
}

void main() {
  Future<JustGameEditorPlugin> open(WidgetTester tester, int count) async {
    final engine = Engine();
    addTearDown(engine.dispose);
    await tester.runAsync(engine.initialize);
    final plugin = JustGameEditorPlugin(engine: engine, modules: [_Many(count)], startVisible: false);
    addTearDown(plugin.dispose);
    plugin.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showViewportMenu(
              context,
              plugin,
              entity: null,
              globalPosition: const Offset(200, 200),
              worldPoint: Offset.zero,
              surface: SurfacePoint(Vector3(1, 0, 2), Vector3(0, -1, 0)),
            ),
            child: const Text('menu'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    return plugin;
  }

  testWidgets("the default kit's shapes are always there, by category", (
    tester,
  ) async {
    // With the 3-D default kit's shapes there are always more than a menu
    // lists itself, so even a few of a module's go under their category.
    await open(tester, 3);
    expect(find.text('Shapes…'), findsOneWidget);
    expect(find.text('Evens…'), findsOneWidget);
    expect(find.text('Add Thing 0'), findsNothing);
    await tester.tap(find.text('Shapes…'));
    await tester.pumpAndSettle();
    expect(find.text('Cube'), findsOneWidget);
  });

  testWidgets('many are listed by category; one picked there is placed', (tester) async {
    final plugin = await open(tester, 12);
    expect(find.text('Add Thing 0'), findsNothing);
    expect(find.text('Evens…'), findsOneWidget);
    expect(find.text('Odds…'), findsOneWidget);
    await tester.tap(find.text('Odds…'));
    await tester.pumpAndSettle();
    expect(find.text('Thing 3'), findsOneWidget);
    expect(find.text('Thing 2'), findsNothing, reason: 'only the odds');
    await tester.tap(find.text('Thing 3'));
    await tester.pumpAndSettle();
    final placed = plugin.engine.world.query([_Marker]).single;
    final p = placed.getComponent<TransformComponent>()!.position;
    expect([p.x, p.y, p.z], [1, 0, 2]);
    expect(plugin.sceneState.selectedEntity.value?.id, placed.id);
  });
}
