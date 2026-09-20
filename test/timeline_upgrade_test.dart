// The Timeline's authoring aids: snapping, recording, copying a keyframe,
// easing — and a sprite's events, editable when a module can write them.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  late JustGameEditorPlugin plugin;
  late Entity door;
  late AnimationControllerComponent timeline;

  Future<void> pump(
    WidgetTester tester, {
    List<EditorModule> modules = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Engine.resetInstance();
    final engine = Engine();
    await tester.runAsync(engine.initialize);
    plugin = JustGameEditorPlugin(engine: engine, modules: modules);
    await tester.runAsync(plugin.onInitialize);
    plugin.setVisible(true);
    if (!plugin.isStatusPanelVisible.value) {
      plugin.toggleStatusPanelVisibility();
    }
    plugin.sceneState.openScene(Scene(name: 'level'), const {});
    timeline = AnimationControllerComponent(duration: 2);
    door = engine.world.createEntityWithComponents([
      TransformComponent(),
      timeline,
    ], name: 'Door');
    plugin.sceneState
      ..syncEntityNode(door)
      ..selectEntity(door);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JustGameEditorOverlay(
            plugin: plugin,
            gameChild: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    plugin.scope.dockController.open('timeline');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    Engine.resetInstance();
  }

  testWidgets('record: moving the entity keys it at the playhead', (
    tester,
  ) async {
    if (!kDebugMode) return;
    await pump(tester);
    timeline.elapsed = 0.5;
    await tester.tap(
      find.byTooltip('Record: key the entity wherever you move it'),
    );
    await tester.pump();
    expect(timeline.suspended, isTrue, reason: 'or it would be pinned back');

    door.getComponent<TransformComponent>()!.setPositionXY(120, 0);
    await tester.pump(const Duration(milliseconds: 50));
    expect(timeline.keyframes, hasLength(1));
    expect(timeline.keyframes.single.time, 0.5);
    expect(timeline.keyframes.single.posX, 120);
    expect(timeline.keyframes.single.posY, isNull, reason: 'only what moved');

    // Nothing moves, nothing is keyed.
    await tester.pump(const Duration(milliseconds: 50));
    expect(timeline.keyframes, hasLength(1));

    await tester.tap(
      find.byTooltip('Recording: move the entity to key it. Click to stop.'),
    );
    await tester.pump();
    expect(timeline.suspended, isFalse);
    await done(tester);
  });

  test('the engine leaves a suspended timeline\'s entity alone', () {
    final world = World()..addSystem(AnimationControllerSystem());
    addTearDown(world.dispose);
    final acc = AnimationControllerComponent(
      duration: 1,
      keyframes: [const TransformKeyframe(time: 0, posX: 50)],
    );
    final e = world.createEntityWithComponents([TransformComponent(), acc]);
    world.update(0);
    expect(e.getComponent<TransformComponent>()!.position.x, 50);

    acc.suspended = true;
    e.getComponent<TransformComponent>()!.setPositionXY(7, 0);
    world.update(0);
    expect(e.getComponent<TransformComponent>()!.position.x, 7);
  });

  testWidgets('a sprite\'s events are read-only until a module can write '
      'them; then they go to the module', (tester) async {
    if (!kDebugMode) return;
    final written = <String>[];
    final module = _SinkModule(
      (atlas, clip, events) => written.add(
        '$atlas#$clip:${events.map((e) => '${e.name}@${e.time}').join(',')}',
      ),
    );
    await pump(tester, modules: [module]);
    expect(plugin.scope.timelineEventSinks, hasLength(1));
    final sink = plugin.scope.timelineEventSinks.single;
    expect(sink.handles('assets/hero.json'), isTrue);
    expect(sink.handles('assets/other.json'), isFalse);
    await tester.runAsync(
      () => sink.write('assets/hero.json', 'run', [
        const AnimationEvent(time: 0.2, name: 'step'),
      ]),
    );
    expect(written, ['assets/hero.json#run:step@0.2']);
    await done(tester);
  });
}

class _SinkModule extends EditorModule {
  _SinkModule(this.onWrite);

  final void Function(String atlas, String clip, List<AnimationEvent> events)
  onWrite;

  @override
  String get id => 'test.sink';

  @override
  String get name => 'Sink';

  @override
  List<TimelineEventSink> get timelineEventSinks => [
    TimelineEventSink(
      handles: (atlas) => atlas.endsWith('hero.json'),
      write: (atlas, clip, events) async {
        onWrite(atlas, clip, events);
        return true;
      },
    ),
  ];
}
