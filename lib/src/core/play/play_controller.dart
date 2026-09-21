import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_signals/just_signals.dart';

import '../scope/editor_scope.dart';
import '../state/play_snapshot.dart';

/// Play/Pause/Stop state for the editor's in-scene play-test.
enum EditorPlayState { stopped, playing, paused }

/// Creates the entity a [SpawnComponent] stands for, when play starts.
typedef EntitySpawner = Entity Function(World world, Entity spawnPoint);

/// The editor's play-test: runs the real systems on the open scene, then puts
/// everything back.
///
/// Editor-only. It never runs in a release build and has no effect on the
/// shipped game's own start-up; it operates on the scene already live in the
/// editor. While a play-test is on, [snapshot] is the level as authored,
/// which is what a save during play writes.
class PlayController {
  PlayController({
    required this.engine,
    required this.scope,
    this.spawnRegistry = const {},
  });

  final Engine engine;
  final EditorScope scope;

  /// Maps a [SpawnComponent.tag] to what creates the entity for it. The app
  /// owns what gets created; the editor only knows where and when to ask.
  final Map<String, EntitySpawner> spawnRegistry;

  /// The play-test state; the toolbar and the grid follow it.
  final Signal<EditorPlayState> state = Signal(
    EditorPlayState.stopped,
    debugLabel: 'playState',
  );

  /// The speeds the toolbar offers. Slow motion is for watching a camera
  /// blend or a jump arc; double speed for getting back to the hard part.
  static const List<double> speeds = [0.25, 0.5, 1.0, 2.0];

  /// How fast game time runs while playing.
  final Signal<double> speed = Signal(1.0, debugLabel: 'playSpeed');

  /// Whole seconds of game time played this session, for the toolbar. A
  /// signal that changes once a second, not once a frame.
  final Signal<int> elapsedSeconds = Signal(0, debugLabel: 'playElapsed');

  double _elapsed = 0;
  int _stepFrames = 0;
  final List<EntityId> _spawned = [];
  PlaySnapshot? _snapshot;

  /// True between [play] and [stop], paused or not.
  bool get isRunning => state.value != EditorPlayState.stopped;

  /// The authored scene as it was when play started, or null when stopped.
  PlaySnapshot? get snapshot => _snapshot;

  /// Starts (or resumes) simulating the currently open scene.
  ///
  /// The first call in a session (from [EditorPlayState.stopped]) spawns one
  /// entity per [SpawnComponent] found in the world via [spawnRegistry],
  /// tracking what it created so [stop] can clean up precisely — the spawn
  /// point entities themselves are never touched, same as the camera entity.
  /// Calling this again while already playing/paused just resumes time.
  void play() {
    if (!engine.isInitialized) return;

    if (state.value == EditorPlayState.stopped) {
      _elapsed = 0;
      elapsedSeconds.value = 0;
      // Before anything spawns or moves — and with nothing previewed.
      scope.restoreAuthoredState();
      _snapshot = PlaySnapshot.capture(engine.world, scope.codec);
      for (final spawnPoint in engine.world.query([SpawnComponent])) {
        final tag = spawnPoint.getComponent<SpawnComponent>()!.tag;
        final spawner = spawnRegistry[tag];
        if (spawner == null) continue;
        final spawned = spawner(engine.world, spawnPoint);
        _spawned.add(spawned.id);
      }
      scope.log.log(
        'Play: spawned ${_spawned.length} entities.',
        source: 'editor',
        category: 'play',
      );
    }

    _stepFrames = 0;
    state.value = EditorPlayState.playing;
    engine.time.timeScale = speed.value;
  }

  /// Freezes simulation without destroying anything — [play] resumes
  /// exactly where this left off.
  void pause() {
    if (state.value != EditorPlayState.playing) return;
    state.value = EditorPlayState.paused;
    engine.time.timeScale = 0.0;
  }

  /// Play when stopped, Stop otherwise: one key for "try it / back to work".
  void togglePlay() => isRunning ? stop() : play();

  /// Pause while playing, resume while paused.
  void togglePause() => switch (state.value) {
    EditorPlayState.playing => pause(),
    EditorPlayState.paused => play(),
    EditorPlayState.stopped => null,
  };

  /// Back to the authored scene and straight into a fresh run.
  void restart() {
    if (!isRunning) return;
    stop();
    play();
  }

  /// Changes how fast game time runs; takes effect at once while playing.
  void setSpeed(double value) {
    speed.value = value;
    if (state.value == EditorPlayState.playing) {
      engine.time.timeScale = value;
    }
  }

  /// Runs exactly one frame and pauses again. Pauses first if playing, so
  /// the key works as "freeze here, now go one at a time".
  void step() {
    if (!isRunning) return;
    if (state.value == EditorPlayState.playing) pause();
    engine.time.timeScale = speed.value;
    _stepFrames = 1;
  }

  /// Called once per frame, after the game has updated, with wall-clock
  /// [dt]: counts play time and closes a stepped frame.
  void tick(double dt) {
    final ran = state.value == EditorPlayState.playing || _stepFrames > 0;
    if (_stepFrames > 0 && --_stepFrames == 0) engine.time.timeScale = 0.0;
    if (!ran) return;
    _elapsed += dt * speed.value;
    elapsedSeconds.value = _elapsed.floor();
  }

  /// Destroys every entity [play] spawned, puts every authored entity back
  /// exactly as it was when play started, and returns to authoring.
  void stop() {
    if (state.value == EditorPlayState.stopped) return;

    for (final id in _spawned) {
      final entity = engine.world.getEntity(id);
      if (entity != null) engine.world.destroyEntity(entity);
    }
    scope.log.log(
      'Stop: destroyed ${_spawned.length} entities.',
      source: 'editor',
      category: 'play',
    );
    _spawned.clear();

    final snapshot = _snapshot;
    _snapshot = null;
    if (snapshot != null) {
      final restored = snapshot.restoreInto(engine.world);
      scope.log.log(
        'Stop: restored $restored authored entities.',
        source: 'editor',
        category: 'play',
      );
    }

    _stepFrames = 0;
    state.value = EditorPlayState.stopped;
    engine.time.timeScale = 0.0;
  }

  void dispose() {
    state.dispose();
    speed.dispose();
    elapsedSeconds.dispose();
  }
}
