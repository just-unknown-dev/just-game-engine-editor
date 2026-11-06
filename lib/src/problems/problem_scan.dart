import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_editor_core/host.dart';
import 'scene_checks.dart';

/// What is wrong with the open scene, kept current: asked a few times a
/// second by the strip and the tab, recomputed only when the scene or the
/// project's files have changed since — or, for a file changed where the
/// editor does not watch, after [_maxAge] — and never during a play-test,
/// whose world is the game's, not the scene: what was found before it
/// stays until it ends.
class ProblemScan {
  ProblemScan(this.scope);

  /// The scan for [scope] — the same one wherever it is asked for, so a
  /// scene is not checked once per thing that wants the answer. Kept in
  /// the scope's container.
  static ProblemScan of(EditorScope scope) =>
      scope.service(() => ProblemScan(scope));

  final EditorScope scope;
  List<SceneProblem> _problems = const [];
  DateTime? _at;
  (EditorScene?, int, int?)? _seen;

  /// [_problems] by the entity each is about, made once per scan when
  /// first asked: a row of the scene tree finds its own without going
  /// through every problem.
  Map<int, List<SceneProblem>>? _byEntity;
  int? _errors;

  static const Duration _maxAge = Duration(seconds: 10);

  /// How often a scene being edited is checked again while the edits keep
  /// coming — a drag changes it on every move, and every check there is
  /// runs per scan. Another scene, or a change on disk, is checked at once.
  /// What shows the problems reads them again after it: the Problems dock
  /// and the status strip on their own beat, the scene tree once the scene
  /// has been still a little longer than this.
  static const Duration editEvery = Duration(seconds: 1);

  /// What time it is: the clock, a test's own.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What a scan was of: the scene, its edits, the files on disk — as the
  /// asset index has seen them, once something has made one (asking for it
  /// here would scan the whole project).
  (EditorScene?, int, int?) _now() => (
    scope.sceneState.activeScene.value,
    scope.sceneState.revision.value,
    scope.container.isRegistered<AssetIndex>()
        ? scope.assetIndex.revision.value
        : null,
  );

  List<SceneProblem> get problems {
    if (_isStale()) {
      final at = _at;
      final seen = _seen;
      final current = _now();
      final age = at == null ? null : now().difference(at);
      final onlyEdited =
          seen != null && seen.$1 == current.$1 && seen.$3 == current.$3;
      if (age == null || !onlyEdited || age >= editEvery) refresh();
    }
    return _problems;
  }

  bool _isStale() {
    if (scope.isPlayTesting.value) return false;
    final at = _at;
    return at == null || _now() != _seen || now().difference(at) > _maxAge;
  }

  /// Checks the scene now.
  void refresh() {
    _at = now();
    _seen = _now();
    _byEntity = null;
    _errors = null;
    _problems = scope.sceneState.hasScene
        ? SceneChecks.run(ScanValidationContext(scope: scope), scope.validators)
        : const [];
  }

  /// The [problems] about [entityId]'s entity, found without going through
  /// the rest: what each row of the scene tree shows.
  List<SceneProblem> problemsFor(int entityId) {
    final all = problems;
    final byEntity = _byEntity ??= () {
      final out = <int, List<SceneProblem>>{};
      for (final p in all) {
        final id = p.entity?.id;
        if (id != null) (out[id] ??= []).add(p);
      }
      return out;
    }();
    return byEntity[entityId] ?? const [];
  }

  /// The ids of the entities with a problem.
  Iterable<int> get entitiesWithProblems {
    problemsFor(-1);
    return _byEntity!.keys;
  }

  int get errors {
    final all = problems;
    return _errors ??= all
        .where((p) => p.severity == ProblemSeverity.error)
        .length;
  }
}

/// A [ValidationContext] that reads each file once per scan: sixty enemies
/// sharing one animator graph and atlas are two reads and two decodes, not
/// a hundred and twenty.
class ScanValidationContext extends ValidationContext {
  ScanValidationContext({
    required super.scope,
    super.projectRoot,
    super.fileExists,
    super.readText,
  });

  final Map<String, bool> _exists = {};
  final Map<String, String?> _texts = {};
  final Map<String, Map<String, dynamic>?> _json = {};

  @override
  bool fileExists(String path) => _exists[path] ??= super.fileExists(path);

  @override
  String? readText(String path) => _texts.containsKey(path)
      ? _texts[path]
      : _texts[path] = super.readText(path);

  @override
  Map<String, dynamic>? readJson(String path) => _json.containsKey(path)
      ? _json[path]
      : _json[path] = super.readJson(path);
}
