// Tags in the editor: the project's list, finding and renaming them in every
// file, the checks that catch a typo, and the pickers that stop one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/extra/extra_docks.dart';

import 'support/test_scope.dart';

void main() {
  late Directory root;
  late EditorScope scope;

  String scenesRoot() => '${root.path}/assets/scenes';

  setUp(() {
    root = Directory.systemTemp.createTempSync('tags_editor_');
    Directory(scenesRoot()).createSync(recursive: true);
    scope = testScope(scenesRoot: scenesRoot());
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A closed scene on disk, in the v6 format — tags were one string then.
  void writeV6Scene(String name) =>
      File('${scenesRoot()}/$name.scene.json').writeAsStringSync(
        jsonEncode({
          'version': 6,
          'name': name,
          'mode': '2d',
          'entities': [
            {
              'name': 'Coin',
              'components': [
                {
                  'type': 'TagComponent',
                  'fields': {'tag': 'coin'},
                },
                {
                  'type': 'TimelineTriggerComponent',
                  'fields': {'targetName': '', 'targetTag': 'coin'},
                },
                {
                  'type': 'CameraTargetGroupComponent',
                  'fields': {
                    'members': [
                      {'name': '', 'tag': 'coin', 'weight': 1.0, 'radius': 0.0},
                    ],
                  },
                },
              ],
            },
          ],
        }),
      );

  Entity add(List<Component> components, {String? name}) =>
      scope.world.createEntityWithComponents([
        TransformComponent(),
        ...components,
      ], name: name);

  List<SceneProblem> problems() => BuiltInValidators.run(
    ValidationContext(scope: scope, projectRoot: root.path),
    [...BuiltInValidators.all, ...scope.validators],
  );

  group('the project tag list', () {
    test('without a file: the declared tags and what the scenes carry', () {
      writeV6Scene('level_02');
      final tags = scope.tags;
      expect(tags.hasFile, isFalse);
      expect(tags.names, containsAll(['player', 'coin']));
      expect(tags['player']!.isDeclared, isTrue);
      expect(tags['coin']!.isDeclared, isFalse);
    });

    test('a new tag is written; a near duplicate or a declared one is not '
        'touched', () {
      final tags = scope.tags;
      expect(tags.create('enemy'), isNotNull);
      expect(tags.hasFile, isTrue);
      final file = jsonDecode(File(tags.path).readAsStringSync()) as Map;
      expect(
        [for (final t in file['tags'] as List) t['name']],
        ['enemy', 'player'],
      );
      expect(tags.problemWithNew('Enemy'), contains('"enemy"'));
      expect(tags.problemWithNew('two words'), isNotNull);
      expect(tags.create('Enemy'), isNull);
      expect(tags.rename('player', 'hero'), isFalse);
      expect(tags.remove('player'), isFalse);
      expect(tags.names, containsAll(['enemy', 'player']));
    });

    test('a spawner\'s tags are known without being listed', () {
      scope.spawners.value = [
        Spawner(
          id: 'boss',
          tags: const {'boss'},
          spawn: (world, at) => world.createEntity(),
        ),
      ];
      expect(scope.tags.isKnown('boss'), isTrue);
      expect(scope.tags.library.value.contains('boss'), isFalse);
      expect(scope.tags.spawnersGiving('boss').single.id, 'boss');
    });
  });

  test('references are found wherever a definition says a field is a tag', () {
    final scene = SceneFormat.migrate({
      'version': 6,
      'entities': [
        {
          'name': 'Cam',
          'components': [
            {
              'type': 'VirtualCameraComponent',
              'fields': {'followName': '', 'followTag': 'coin'},
            },
            {
              'type': 'TimelinePlayerComponent',
              'fields': {
                'timelinePath': '',
                'inline': {
                  'formatVersion': 2,
                  'tracks': [
                    {
                      'kind': 'event',
                      'binding': {'tag': 'coin'},
                      'events': <Object>[],
                    },
                  ],
                },
              },
            },
          ],
        },
      ],
    });
    final uses = scope.tagReferences.inScene(scene, tag: 'coin');
    expect(uses.map((u) => u.where), [
      'Virtual Camera › Follow',
      contains('track binding'),
    ]);
    expect(uses.every((u) => u.kind == TagUseKind.reference), isTrue);
  });

  group('checks', () {
    test('an unknown tag is flagged, and its fix is one undo step', () {
      scope.tags.create('coin');
      final e = add([TagComponent('coinz')], name: 'Pickup');
      final problem = problems().singleWhere(
        (p) => p.message.contains('"coinz"'),
      );
      expect(problem.hint, contains('"coin"'));
      problem.fixes.first.apply();
      expect(e.tags, ['coin']);
      scope.history.undo();
      expect(e.tags, ['coinz']);
    });

    test('a spawn point naming no spawner is an error, fixed in a click', () {
      scope.spawners.value = [
        Spawner(id: 'player', spawn: (w, _) => w.createEntity()),
      ];
      final point = add([SpawnComponent(spawner: 'players')], name: 'Spawn');
      final problem = problems().singleWhere((p) => p.entity == point);
      expect(problem.severity, ProblemSeverity.error);
      expect(problem.fixes.single.label, 'Spawn "player"');
      problem.fixes.single.apply();
      expect(point.getComponent<SpawnComponent>()!.spawner, 'player');
    });

    test('a camera following a name nothing has offers the tag it meant', () {
      final camera = add([
        VirtualCameraComponent(follow: const EntityTarget.name('Players')),
      ], name: 'MainCamera');
      final problem = problems().singleWhere(
        (p) => p.entity == camera && p.message.contains('"Players"'),
      );
      final fix = problem.fixes.singleWhere((f) => f.label.contains('tag'));
      fix.apply();
      expect(
        camera.getComponent<VirtualCameraComponent>()!.follow,
        const EntityTarget.tag('player'),
      );
    });
  });

  test('a rename reaches the open scene as one undo step, and the other '
      'scenes and timelines on disk', () async {
    scope.tags.create('coin');
    writeV6Scene('level_02');
    final timeline = File('${root.path}/assets/timelines/bob.timeline.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'formatVersion': 2,
          'tracks': [
            {
              'kind': 'event',
              'binding': {'tag': 'coin'},
              'events': <Object>[],
            },
          ],
        }),
      );
    scope.sceneState.openScene(EditorScene(name: 'level_01'));
    final coin = add([
      TagComponent.of(['coin', 'shiny']),
      VirtualCameraComponent(follow: const EntityTarget.tag('coin')),
    ], name: 'Coin');

    final refactor = TagRefactor(scope, projectRoot: root.path);
    final plan = refactor.plan('coin', renameTo: 'gem');
    expect(plan.openUses, hasLength(2));
    expect(plan.scenes.keys, ['level_02']);
    expect(plan.timelines.keys, ['assets/timelines/bob.timeline.json']);

    final result = await refactor.apply(plan);
    expect(result.failures, isEmpty);
    expect(coin.tags, ['gem', 'shiny']);
    expect(
      coin.getComponent<VirtualCameraComponent>()!.follow,
      const EntityTarget.tag('gem'),
    );
    expect(scope.tags.names, contains('gem'));
    expect(scope.tags.names, isNot(contains('coin')));

    final saved =
        jsonDecode(
              File('${scenesRoot()}/level_02.scene.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(saved['version'], SceneFormat.current);
    expect(scope.tagReferences.inScene(saved, tag: 'coin'), isEmpty);
    expect(scope.tagReferences.inScene(saved, tag: 'gem'), hasLength(3));
    expect(scope.scenes.backupsOf('level_02'), isNotEmpty);
    expect(timeline.readAsStringSync(), contains('"gem"'));

    scope.history.undo();
    expect(coin.tags, ['coin', 'shiny']);
    expect(
      coin.getComponent<VirtualCameraComponent>()!.follow,
      const EntityTarget.tag('coin'),
    );
  });

  test(
    'a delete takes the tag off entities and leaves what names it',
    () async {
      scope.tags.create('coin');
      scope.sceneState.openScene(EditorScene(name: 'level_01'));
      final coin = add([
        TagComponent('coin'),
        VirtualCameraComponent(follow: const EntityTarget.tag('coin')),
      ]);
      final refactor = TagRefactor(scope, projectRoot: root.path);
      await refactor.apply(refactor.plan('coin'));
      expect(coin.tags, isEmpty);
      expect(
        coin.getComponent<VirtualCameraComponent>()!.follow,
        const EntityTarget.tag('coin'),
      );
      expect(scope.tags.library.value.contains('coin'), isFalse);
      // And now it is a problem to look at, not a silent break.
      expect(problems().any((p) => p.message.contains('"coin"')), isTrue);
    },
  );

  test('tag edits add the component when needed, one undo step each', () {
    final e = add(const []);
    TagEdits.apply(scope.history, e, ['enemy'], scope.sceneState);
    TagEdits.apply(scope.history, e, ['enemy', 'boss'], scope.sceneState);
    expect(e.tags, ['enemy', 'boss']);
    scope.history.undo();
    expect(e.tags, ['enemy']);
    scope.history.undo();
    expect(e.hasComponent<TagComponent>(), isFalse);
  });

  test('the tree narrows to any of several tags', () {
    final a = add([TagComponent('enemy')]);
    final b = add([TagComponent('coin')]);
    final c = add(const []);
    const filter = TreeFilter(tags: {'enemy', 'coin'});
    expect([a, b, c].where(filter.matches), [a, b]);
  });

  test('search finds #tag exactly, among all of an entity\'s tags', () {
    final boss = add([
      TagComponent.of(['enemy', 'boss']),
    ]);
    add([TagComponent('bossy')]);
    expect(
      [
        for (final e in scope.world.entities)
          if (SceneQuery('#boss').matches(e, scope)) e,
      ],
      [boss],
    );
    expect(SceneQuery('Tag.tags = boss').matches(boss, scope), isTrue);
  });

  group('the inspector header', () {
    Future<Entity> pumpHeader(
      WidgetTester tester, {
      List<String> tags = const [],
      double width = 360,
    }) async {
      final e = add([TagComponent.of(tags)], name: 'Hero');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: EntityHeader(
                  entity: e,
                  scope: scope,
                  sceneState: scope.sceneState,
                ),
              ),
            ),
          ),
        ),
      );
      return e;
    }

    Future<void> repump(WidgetTester tester, Entity e) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: EntityHeader(
                  entity: e,
                  scope: scope,
                  sceneState: scope.sceneState,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows the name and the tags, and no "Tags" label', (
      tester,
    ) async {
      await pumpHeader(tester, tags: ['player']);
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('player'), findsOneWidget);
      expect(find.text('Tags'), findsNothing);
      expect(find.text('Add'), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    });

    testWidgets('more tags than room: the first few, then +N', (tester) async {
      await pumpHeader(
        tester,
        width: 300,
        tags: ['player', 'enemy', 'boss', 'flying', 'shiny', 'heavy'],
      );
      expect(find.text('player'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\+\d$')), findsOneWidget);
      expect(find.text('heavy'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'no overflow');
    });

    testWidgets('the tick turns it off and on, undoably', (tester) async {
      final e = await pumpHeader(tester);
      await tester.tap(find.byIcon(Icons.check_box_rounded));
      expect(e.isActive, isFalse);
      scope.history.undo();
      expect(e.isActive, isTrue);
    });

    testWidgets('a double-click renames it', (tester) async {
      final e = await pumpHeader(tester);
      await tester.tap(find.text('Hero'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Hero'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EntityRenameBox), 'Heroine');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(e.name, 'Heroine');
    });

    testWidgets('the ⋮ menu adds a tag from the list', (tester) async {
      scope.tags.create('enemy');
      final e = await pumpHeader(tester);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Manage tags…'), findsOneWidget);
      await tester.tap(find.text('Add tag…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('enemy').last);
      await tester.pumpAndSettle();
      expect(e.tags, ['enemy']);
      await repump(tester, e);
      expect(find.text('enemy'), findsOneWidget);
    });
  });

  testWidgets('a chip comes off with its cross', (tester) async {
    List<String>? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagChips(
            scope: scope,
            tags: const ['enemy', 'boss'],
            onChanged: (next) => changed = next,
          ),
        ),
      ),
    );
    expect(find.text('enemy'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    expect(changed, ['boss']);
  });
}
