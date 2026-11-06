// What the editor draws over the game each frame: the game camera's
// preview lets go of the text it lays out, and is not drawn over the four
// 3-D views, which show the level four times already.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/just_game_engine_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_graphics_engine/just_graphics_engine.dart'
    show NullGpuDevice, rendererNullShaders;
import 'package:just_game_engine_editor/src/plugin/just_game_editor_plugin.dart';

/// The text painters [draw] made, and how many of them it disposed.
({int made, int kept}) _painters(void Function() draw) {
  var made = 0;
  var disposed = 0;
  void listen(ObjectEvent event) {
    if (event.object is! TextPainter) return;
    if (event is ObjectCreated) made++;
    if (event is ObjectDisposed) disposed++;
  }

  FlutterMemoryAllocations.instance.addListener(listen);
  try {
    draw();
  } finally {
    FlutterMemoryAllocations.instance.removeListener(listen);
  }
  return (made: made, kept: made - disposed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Engine engine;
  late JustGameEditorPlugin plugin;

  Future<void> start({List<EngineService> services = const []}) async {
    engine = Engine(config: EngineConfig(services: services));
    addTearDown(engine.dispose);
    await engine.initialize();
    registerCameraSystems(engine.world, engine.camera);
    plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
    addTearDown(plugin.dispose);
    await plugin.attach(plugin.engine);
    plugin.setVisible(true);
    engine.world.createEntityWithComponents([
      TransformComponent(position: Vector3(300, 200, 0)),
      VirtualCameraComponent(),
    ], name: 'Main');
  }

  ({int made, int kept}) frame(Size size, {required bool preview}) {
    plugin.showGamePreview.value = preview;
    plugin.update(1 / 60);
    return _painters(() {
      final recorder = ui.PictureRecorder();
      plugin.renderOverlay(ui.Canvas(recorder), size);
      recorder.endRecording().dispose();
    });
  }

  test('the game preview keeps none of the text it lays out', () async {
    if (!kDebugMode) return;
    await start();
    plugin.sceneState.openScene(EditorScene(name: 'level'));
    const size = Size(1280, 720);
    final without = frame(size, preview: false);
    final shown = frame(size, preview: true);
    expect(
      shown.made,
      greaterThan(without.made),
      reason: 'the preview was drawn, with its header',
    );
    expect(shown.kept, without.kept, reason: 'its header is let go of');
  });

  test('no game preview over the four 3-D views', () async {
    if (!kDebugMode) return;
    await start(
      services: [
        Graphics3D(
          device: NullGpuDevice(shaders: rendererNullShaders),
          keepEdges: true,
        ),
      ],
    );
    plugin.sceneState.openScene(
      EditorScene(name: 'deep', mode: SceneMode.threeD),
    );
    plugin.toggleSplitViews();
    expect(plugin.activeSplit, isNotNull);
    const size = Size(402, 302);
    final without = frame(size, preview: false);
    final shown = frame(size, preview: true);
    expect(shown.made, without.made, reason: 'the panes alone');
    expect(shown.kept, 0, reason: 'the panes\' labels are let go of');
  });
}
