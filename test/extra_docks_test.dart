// Problems, History and Search: what they find, and what a click does.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/extra/extra_docks.dart';

import 'support/test_scope.dart';

class _RuleModule extends EditorModule {
  @override
  String get id => 'test.rules';

  @override
  String get name => 'Rules';

  @override
  List<SceneValidator> get validators => [
    (context) => [
      if (context.world.findEntityByName('Spawn') == null)
        const SceneProblem(message: 'The level has no Spawn.'),
    ],
  ];
}

void main() {
  group('problems', () {
    late EditorScope scope;
    final files = <String, String>{};

    List<SceneProblem> check() => BuiltInValidators.run(
      ValidationContext(
        scope: scope,
        fileExists: files.containsKey,
        readText: (p) => files[p],
      ),
      [...BuiltInValidators.all, ...scope.validators],
    );

    setUp(() {
      scope = testScope(modules: [_RuleModule()]);
      files
        ..clear()
        ..['assets/hero.json'] = jsonEncode({
          'frames': <String, dynamic>{},
          'meta': {
            'frameTags': [
              {'name': 'idle', 'from': 0, 'to': 1},
            ],
          },
        })
        ..['assets/hero.animator.json'] = const AnimatorGraph(
          states: [
            AnimatorState(name: 'idle'),
            AnimatorState(name: 'run'),
          ],
        ).encode();
    });

    test('a clean scene has none — and a module\'s check counts', () {
      scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Spawn');
      expect(check(), isEmpty);
      scope.world.destroyAllEntities();
      expect(check().single.message, 'The level has no Spawn.');
    });

    test('a timeline bound to nobody, or to a field that is not there', () {
      scope.world.createEntityWithComponents([
        TransformComponent(),
      ], name: 'Spawn');
      final door = scope.world.createEntityWithComponents([
        TransformComponent(),
        TimelinePlayerComponent(
          inline: TimelineAsset(
            duration: 1,
            tracks: [
              PropertyTrack(
                component: 'TransformComponent',
                field: 'position',
                channel: 'x',
                binding: const TrackBinding.name('Lift'),
              ),
              PropertyTrack(
                component: 'VelocityComponent',
                field: 'velocity',
                channel: 'x',
              ),
            ],
          ),
        ),
      ], name: 'Door');
      final problems = check();
      expect(problems.map((p) => p.entity), everyElement(door));
      expect(problems.first.severity, ProblemSeverity.error);
      expect(problems.first.message, contains('VelocityComponent.velocity.x'));
      expect(problems.last.message, contains('answers to Lift'));
      expect(problems, hasLength(2));
    });

    test(
      'a file that is not there is an error, on the entity that names it',
      () {
        final tree = scope.world.createEntityWithComponents([
          TransformComponent(),
          SpriteComponent(spritePath: 'assets/gone.png'),
        ], name: 'Tree');
        final problem = check().first;
        expect(problem.severity, ProblemSeverity.error, reason: 'errors first');
        expect(problem.entity, same(tree));
        expect(problem.message, contains('assets/gone.png'));
        files['assets/gone.png'] = '';
        expect(
          check().where((p) => p.entity == tree),
          isEmpty,
          reason: 'fixed',
        );
      },
    );

    test('an animator that plays clips the atlas lacks says which', () {
      final hero = scope.world.createEntityWithComponents([
        TransformComponent(),
        SpriteAnimationComponent(atlasPath: 'assets/hero.json'),
        AnimatorComponent(graphPath: 'assets/hero.animator.json'),
      ], name: 'Hero');
      final problem = check().firstWhere((p) => p.entity == hero);
      expect(problem.message, contains('"run"'));
      expect(problem.message, contains('only "idle"'));
      expect(problem.hint, contains('tag the frames'));
    });

    test('references to nobody, cameras following nothing, art with nowhere '
        'to be', () {
      scope.world
        ..createEntityWithComponents([
          TransformComponent(),
          VirtualCameraComponent(),
          CameraFramingComponent(),
        ], name: 'Cam')
        ..createEntityWithComponents([
          TransformComponent(),
          CameraConfinerComponent(boundsName: 'Nowhere'),
        ], name: 'Confined')
        ..createEntityWithComponents([
          SpriteAnimationComponent(),
        ], name: 'Ghost');
      final messages = check().map((p) => p.message).join('\n');
      expect(messages, contains('Cam frames a target but follows nothing'));
      expect(messages, contains('refers to "Nowhere"'));
      expect(
        messages,
        contains('Ghost has something to draw but no Transform'),
      );
    });

    test('the scan is cached, and empty with no scene open', () {
      final scan = ProblemScan(scope);
      expect(scan.problems, isEmpty, reason: 'no scene');
      scope.sceneState.openScene(Scene(name: 'level'), const {});
      scan.refresh();
      expect(scan.problems, hasLength(1), reason: 'the module: no Spawn');
      expect(scan.errors, 0);
    });
  });

  test('history: jump to any step, forward or back', () {
    final history = EditorHistory();
    final log = <String>[];
    CallbackCommand step(String name) => CallbackCommand(
      label: name,
      onRedo: () => log.add('+$name'),
      onUndo: () => log.add('-$name'),
    );
    for (final name in ['a', 'b', 'c']) {
      history.push(step(name));
    }
    log.clear();

    history.jumpTo(1);
    expect(log, ['-c', '-b']);
    expect(history.undoEntries.map((c) => c.label), ['a']);
    expect(history.redoEntries.map((c) => c.label), ['c', 'b']);

    history.jumpTo(3);
    expect(log, ['-c', '-b', '+b', '+c']);
    history.jumpTo(0);
    expect(history.undoEntries, isEmpty);
    history.jumpTo(99);
    expect(history.undoEntries, hasLength(3), reason: 'clamped');
  });

  group('search', () {
    late EditorScope scope;
    late Entity hero;
    late Entity bat;

    setUp(() {
      scope = testScope();
      hero = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(120, 40, 0)),
        HealthComponent(maxHealth: 3),
        TagComponent('player'),
      ], name: 'Hero');
      bat = scope.world.createEntityWithComponents([
        TransformComponent(position: Vector3(20, 40, 0)),
        HealthComponent(maxHealth: 1),
        TagComponent('enemy'),
      ], name: 'Bat');
    });

    List<Entity> find(String text) => [
      for (final e in scope.world.entities)
        if (SceneQuery(text).matches(e, scope)) e,
    ];

    test('words match names, tags and component types — all of them', () {
      expect(find('hero'), [hero]);
      expect(find('enemy'), [bat]);
      expect(find('health'), [hero, bat]);
      expect(find('health enemy'), [bat]);
      expect(find('nothing'), isEmpty);
      expect(SceneQuery('   ').isEmpty, isTrue);
    });

    test('a field can be compared, and a vector reached into', () {
      expect(find('Health.maxHealth > 2'), [hero]);
      expect(find('health.maxhealth <= 1'), [bat]);
      expect(find('transform.x >= 100'), [hero]);
      expect(find('Tag.tag = enemy'), [bat]);
      expect(find('Tag.tag != enemy'), [hero]);
      expect(find('health Health.maxHealth < 2 transform.x < 50'), [bat]);
      expect(find('Missing.field > 1'), isEmpty);
    });
  });
}
