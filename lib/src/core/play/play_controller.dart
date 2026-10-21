import 'package:just_debugger/just_debugger.dart' show DebuggerLogLevel;
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_editor_core/host.dart';
import '../state/play_snapshot.dart';

/// Where the editor's play-test of the open scene is.
enum EditorPlayState {
  /// No play-test: the scene is being authored, the game's time held at 0.
  stopped,

  /// The game's systems run on the scene, as in the game.
  playing,

  /// The play-test is frozen where it was; Stop still puts the authored
  /// scene back.
  paused,
}

/// The editor's play-test: runs the real systems on the open scene, then puts
/// everything back.
///
/// Editor-only. It never runs in a release build and has no effect on the
/// shipped game's own start-up; it operates on the scene already live in the
/// editor. While a play-test is on, [snapshot] is the level as authored,
/// which is what a save during play writes.
class PlayController {
  /// [spawners], when given, become the scope's ([EditorScope.spawners]).
  PlayController({
    required this.engine,
    required this.scope,
    List<Spawner>? spawners,
  }) {
    if (spawners != null) scope.spawners.value = spawners;
  }

  final Engine engine;
  final EditorScope scope;

  /// What a spawn point's [SpawnComponent.spawner] can name. The app owns
  /// what gets created; the editor only knows where and when to ask. Read
  /// from the scope at Play, so spawners handed over after a hot reload are
  /// the ones used.
  List<Spawner> get spawners => scope.spawners.value;

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
  EditorHistoryMark? _historyMark;

  /// True between [play] and [stop], paused or not.
  bool get isRunning => state.value != EditorPlayState.stopped;

  /// The authored scene as it was when play started, or null when stopped.
  PlaySnapshot? get snapshot => _snapshot;

  /// Starts (or resumes) simulating the currently open scene.
  ///
  /// The first call in a session (from [EditorPlayState.stopped]) spawns one
  /// entity per [SpawnComponent] found in the world through [spawners],
  /// tracking what it created so [stop] can clean up precisely — the spawn
  /// point entities themselves are never touched, same as the camera entity.
  /// Calling this again while already playing/paused just resumes time.
  void play() {
    if (!engine.isInitialized) return;

    if (state.value == EditorPlayState.stopped) {
      // Before anything spawns or moves — and with nothing previewed.
      scope.restoreAuthoredState();
      final snapshot = PlaySnapshot.capture(
        engine.world,
        scope.codec,
        rootOrder: scope.sceneState.rootOrder(engine.world),
      );
      final List<Entity> spawned;
      try {
        spawned = SpawnPoints.spawnAll(
          engine.world,
          spawners,
          onMissing: (point, id) => scope.log.log(
            'Play: nothing spawned at ${point.name ?? 'a spawn point'} — no '
            'spawner is called "$id".',
            source: 'editor',
            category: 'play',
            level: DebuggerLogLevel.warning,
            details: spawners.isEmpty
                ? 'The game registered no spawners with the editor.'
                : 'Spawners: ${spawners.map((s) => s.id).join(', ')}.',
          ),
        );
      } on Object catch (error, stack) {
        // A spawner of the game's threw. What the spawners made before it
        // goes again, and the editor stays as it was: no play-test, no
        // snapshot (a save keeps writing the level as it stands), and
        // nothing half-spawned left in the level to be saved with it.
        final removed = snapshot.removeAddedFrom(engine.world);
        scope.sceneState.refresh();
        scope.log.log(
          'Play did not start: a spawner threw — $error',
          source: 'editor',
          category: 'play',
          level: DebuggerLogLevel.error,
          details: [
            if (removed > 0)
              'The $removed entities the spawners had made were taken away '
                  'again.',
            '$stack',
          ].join('\n'),
        );
        return;
      }
      _elapsed = 0;
      elapsedSeconds.value = 0;
      // Each play-test starts the cameras from nothing, as the game does:
      // no memory of the last run, impulse and noise seeds from the start —
      // so a shake or a handheld drift plays the same way every time.
      if (engine.cameraSystem.isInitialized) {
        engine.cameraSystem.brain.reset();
      }
      _snapshot = snapshot;
      // What is done in the play-test is undone by Stop, not by Ctrl+Z
      // afterwards: the history goes back to this when it stops.
      _historyMark = scope.history.mark();
      _spawned.addAll(spawned.map((e) => e.id));
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
    if (engine.isInitialized) engine.time.timeScale = 0.0;
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
    if (!engine.isInitialized) {
      // The engine is gone (an app closing disposes it first): nothing is
      // left to put back, only the play-test to end.
      _spawned.clear();
      _snapshot = null;
      _endPlayTest();
      return;
    }

    final snapshot = _snapshot;
    final int spawned;
    final int restored;
    try {
      spawned = _destroySpawned();
      restored =
          snapshot?.restoreInto(
            engine.world,
            // So an undo step recorded before play still finds an entity
            // play destroyed and Stop made again.
            onRecreated: scope.sceneState.entityRebuilt,
          ) ??
          0;
    } on Object catch (error, stack) {
      // The level could not be put back. Kept as it is — paused, the
      // snapshot still held — so a save still writes the level as
      // authored, and Stop can be pressed again.
      if (state.value == EditorPlayState.playing) pause();
      scope.log.log(
        'Stop could not put the level back as it was: $error. The '
        'play-test is paused; press Stop again, or open the scene again '
        'without saving.',
        source: 'editor',
        category: 'play',
        level: DebuggerLogLevel.error,
        details: '$stack',
      );
      return;
    }
    scope.log.log(
      'Stop: destroyed $spawned entities.',
      source: 'editor',
      category: 'play',
    );
    if (snapshot != null) {
      scope.log.log(
        'Stop: restored $restored authored entities.',
        source: 'editor',
        category: 'play',
      );
    }
    _snapshot = null;
    _endPlayTest();
    engine.time.timeScale = 0.0;
  }

  /// Back to authoring: the history as it was at Play, the state stopped.
  void _endPlayTest() {
    final mark = _historyMark;
    _historyMark = null;
    if (mark != null) scope.history.restore(mark);
    _stepFrames = 0;
    state.value = EditorPlayState.stopped;
  }

  /// Destroys what [play] spawned; how many there were.
  int _destroySpawned() {
    final count = _spawned.length;
    final ids = List.of(_spawned);
    // Cleared first: tried again after a failed Stop, an id may be another
    // entity's by then.
    _spawned.clear();
    for (final id in ids) {
      final entity = engine.world.getEntity(id);
      if (entity != null) {
        engine.world.destroyEntity(entity, withChildren: false);
      }
    }
    return count;
  }

  void dispose() {
    state.dispose();
    speed.dispose();
    elapsedSeconds.dispose();
  }
}
