// Sound plays only in a play-test: while the scene is edited the game's
// AudioSystem does not run (it would start every source, and mark it
// played in the scene), and stopping a play-test stops what it played.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/real_io.dart';

/// Keeps the sounds asked for, and plays nothing.
class _Audio extends AudioEngine {
  final Set<String> live = {};
  int _count = 0;

  @override
  Future<void> initialize() async {}

  @override
  bool get isInitialized => true;

  @override
  Future<String?> playSfx(
    String path, {
    double volume = 1.0,
    bool loop = false,
    double pan = 0.0,
    double pitch = 1.0,
    double speed = 1.0,
    List<AudioEffect> effects = const [],
    Audio3DPosition? position3d,
    AudioSpatial spatial = const AudioSpatial(),
    AudioChannel channel = AudioChannel.sfx,
  }) async {
    final id = 'sfx-${++_count}';
    live.add(id);
    return id;
  }

  @override
  bool isSfxPlaying(String id) => live.contains(id);

  @override
  Future<void> stopSfx(String id) async => live.remove(id);

  @override
  void update({double? dt}) {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sound plays in a play-test, not while the scene is edited', () async {
    if (!kDebugMode) return;
    final audio = _Audio();
    final engine = Engine(
      config: EngineConfig(
        defaultSystems: {DefaultSystem.audio},
        createAudio: () => audio,
      ),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    final plugin = JustGameEditorPlugin(engine: engine);
    addTearDown(plugin.dispose);
    await plugin.attach(plugin.engine);
    plugin.sceneState.openScene(EditorScene(name: 'level'));
    final source = AudioSourceComponent(
      clipPath: 'assets/audio/wind.wav',
      loop: true,
    );
    engine.world.createEntityWithComponents([TransformComponent(), source]);
    final system = engine.world.systems.whereType<AudioSystem>().single;

    plugin.setVisible(true);
    plugin.update(1 / 60);
    engine.world.update(0);
    await pumpEventQueue();
    expect(system.isActive, isFalse);
    expect(audio.live, isEmpty);
    expect(source.playOnAdd, isTrue, reason: 'the scene is left as it is');

    plugin.playController.play();
    plugin.update(1 / 60);
    expect(system.isActive, isTrue);
    engine.world.update(1 / 60);
    await pumpEventQueue();
    expect(audio.live, hasLength(1));

    plugin.playController.stop();
    plugin.update(1 / 60);
    expect(system.isActive, isFalse);
    expect(
      audio.live,
      isEmpty,
      reason: 'what the play-test played stops with it',
    );
  }, timeout: bootTimeout);
}
