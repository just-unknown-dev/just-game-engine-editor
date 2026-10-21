import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:just_signals/just_signals.dart';

/// The steps a scene takes as it opens, in order.
enum SceneLoadStage {
  /// Its file read, and brought to the current format.
  read('Read the scene file', 'Reading the scene file'),

  /// Its entities made, and linked to their parents.
  build('Create the entities', 'Creating the entities'),

  /// What they show arriving: sprites, tile maps, models.
  assets('Load the assets', 'Loading the assets');

  const SceneLoadStage(this.label, this.doing);

  /// The step, as the loader lists it.
  final String label;

  /// The step under way, as the loader says it.
  final String doing;

  /// The part of the whole open the step takes up, from 0 to 1. Assets take
  /// the most: they are what a big scene waits for.
  (double, double) get span => switch (this) {
    SceneLoadStage.read => (0, 0.1),
    SceneLoadStage.build => (0.1, 0.6),
    SceneLoadStage.assets => (0.6, 1),
  };
}

/// How far along the loads are: how many of those asked for have arrived —
/// loaded, or failed to — of how many.
typedef AssetTally = ({int done, int total});

/// Where a scene's opening has got to.
@immutable
class SceneLoadProgress {
  const SceneLoadProgress({
    required this.sceneName,
    required this.stage,
    required this.fraction,
    this.detail,
    this.done = 0,
    this.total = 0,
    this.isFinished = false,
  });

  /// The scene opening.
  final String sceneName;

  /// The step it is on.
  final SceneLoadStage stage;

  /// What the step is doing, when there is more to say than its name:
  /// `Upgrading from format v7`.
  final String? detail;

  /// How many of the step's [total] things are done. Both 0 when the step
  /// has nothing to count.
  final int done;

  /// How many things the step has to do; it can grow, as a load starts
  /// another.
  final int total;

  /// The whole open, from 0 to 1. It never goes back, though [total] grows.
  final double fraction;

  /// Whether the open is over: the loader stays a moment, and the editor
  /// takes edits again.
  final bool isFinished;

  @override
  bool operator ==(Object other) =>
      other is SceneLoadProgress &&
      other.sceneName == sceneName &&
      other.stage == stage &&
      other.detail == detail &&
      other.done == done &&
      other.total == total &&
      other.fraction == fraction &&
      other.isFinished == isFinished;

  @override
  int get hashCode =>
      Object.hash(sceneName, stage, detail, done, total, fraction, isFinished);
}

/// Where a scene's opening has got to, for the loader the editor shows
/// over it.
///
/// `SceneIO` reports the steps it takes. Once the scene is open, the loads
/// its entities start are counted through [watchAssets] and waited for
/// until nothing has been loading for [quietTicks] updates in a row.
/// [tick] is called on each of the editor's updates, the way autosave is
/// timed: there is no timer to cancel, and nothing runs while the editor
/// does not.
///
/// The loader shows only once an open has taken [showAfter], so a small
/// scene opens without a flash. Once shown, it stays at least [showFor], so
/// a slow open does not flicker as it ends.
class SceneLoading {
  SceneLoading({
    this.showAfter = const Duration(milliseconds: 200),
    this.showFor = const Duration(milliseconds: 500),
    this.quietTicks = 3,
    this.giveUpAfter = const Duration(seconds: 15),
  });

  /// How long an open runs before the loader shows.
  final Duration showAfter;

  /// How long the loader stays at least, once it has shown.
  final Duration showFor;

  /// How many updates in a row with nothing loading mean the assets are
  /// in. More than one: a load can start the next a frame later — a tile
  /// map its tilesets, a tileset its image.
  final int quietTicks;

  /// How long the wait goes on with no asset arriving before it ends
  /// anyway. Whatever is still loading goes on loading.
  final Duration giveUpAfter;

  /// Where the open has got to; null when none is under way.
  final Signal<SceneLoadProgress?> progress = Signal(
    null,
    debugLabel: 'sceneLoadProgress',
  );

  /// Whether the loader shows.
  final Signal<bool> isShown = Signal(false, debugLabel: 'sceneLoadShown');

  /// Whether a scene is opening. The editor waits for it, and takes no
  /// edits meanwhile.
  bool get isLoading {
    final current = progress.value;
    return current != null && !current.isFinished;
  }

  /// Whether the scene is open and its assets are still arriving: [skip]
  /// shows it as it is.
  bool get isWaitingOnAssets =>
      isLoading && progress.value!.stage == SceneLoadStage.assets;

  final Stopwatch _clock = Stopwatch();
  Duration _shownAt = Duration.zero;
  double _fraction = 0;
  AssetTally Function()? _assets;
  AssetTally? _lastTally;
  Duration _lastArrival = Duration.zero;
  int _quiet = 0;

  /// [sceneName] starts opening.
  void begin(String sceneName) {
    _assets = null;
    _fraction = 0;
    _clock
      ..reset()
      ..start();
    // Another open straight after one that showed: the loader stays up.
    if (isShown.value) _shownAt = Duration.zero;
    progress.value = SceneLoadProgress(
      sceneName: sceneName,
      stage: SceneLoadStage.read,
      fraction: 0,
    );
  }

  /// The open is on [stage], [done] of [total] things through it, with
  /// [detail] to say what it is doing.
  void report(
    SceneLoadStage stage, {
    String? detail,
    int done = 0,
    int total = 0,
  }) {
    final current = progress.value;
    if (current == null || current.isFinished) return;
    final (from, to) = stage.span;
    final within = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    _fraction = math.max(_fraction, from + (to - from) * within);
    progress.value = SceneLoadProgress(
      sceneName: current.sceneName,
      stage: stage,
      detail: detail,
      done: done,
      total: total,
      fraction: _fraction,
    );
  }

  /// The scene is open. [count] says how many of the loads it started have
  /// arrived; the open waits on them.
  void watchAssets(AssetTally Function() count) {
    if (!isLoading) return;
    _assets = count;
    _lastTally = null;
    _lastArrival = _clock.elapsed;
    _quiet = 0;
    report(SceneLoadStage.assets);
  }

  /// The open is over, or went wrong: there is nothing more to wait for.
  void end() {
    final current = progress.value;
    if (current == null || current.isFinished) return;
    _assets = null;
    if (!isShown.value) {
      _clear();
      return;
    }
    // Shown: it ends full, and stays a moment (see [tick]).
    progress.value = SceneLoadProgress(
      sceneName: current.sceneName,
      stage: current.stage,
      done: current.total,
      total: current.total,
      fraction: 1,
      isFinished: true,
    );
  }

  /// Stops waiting on the assets: the scene shows as it is, and what is
  /// still loading goes on loading.
  void skip() {
    if (isWaitingOnAssets) _clear();
  }

  /// Moves the open along: counts the assets, ends the wait once they are
  /// in, and shows or hides the loader. Called on each of the editor's
  /// updates.
  void tick() {
    if (progress.value == null) return;
    final now = _clock.elapsed;
    final count = _assets;
    if (count != null && isLoading) _tickAssets(count(), now);
    final current = progress.value;
    if (current == null) return;
    if (!isShown.value) {
      if (!current.isFinished && now >= showAfter) {
        isShown.value = true;
        _shownAt = now;
      }
    } else if (current.isFinished && now - _shownAt >= showFor) {
      _clear();
    }
  }

  void _tickAssets(AssetTally tally, Duration now) {
    final pending = tally.total - tally.done;
    _quiet = pending <= 0 ? _quiet + 1 : 0;
    if (tally != _lastTally) {
      _lastTally = tally;
      _lastArrival = now;
      report(SceneLoadStage.assets, done: tally.done, total: tally.total);
    }
    if (_quiet >= quietTicks || now - _lastArrival >= giveUpAfter) end();
  }

  void _clear() {
    _assets = null;
    _clock.stop();
    progress.value = null;
    isShown.value = false;
  }

  /// Lets go of the signals; nothing may be reported after it.
  void dispose() {
    _assets = null;
    _clock.stop();
    progress.dispose();
    isShown.dispose();
  }
}
