// The code README.md and QUICKSTART.md give a game to copy, compiled
// against the package as it is: a snippet that stops compiling fails here
// before a reader finds it. Keep the two in step — the snippets are these
// functions, as the guides print them.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

// ── README "Install": lib/main_editor.dart ─────────────────────────────────

/// Stands in for the game's own app (`lib/main.dart`'s).
class MyGame extends StatelessWidget {
  const MyGame({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Future<void> readmeMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // kDebugMode is a compile-time constant: a profile or release build keeps
  // only the else branch, so it holds no editor.
  if (kDebugMode) {
    await _runEditor();
  } else {
    runApp(const MyGame());
  }
}

Future<void> _runEditor() async {
  final engine = Engine();
  await engine.initialize(); // boot the game's world here, as main.dart does
  final plugin = await JustGameEditorPlugin.register(
    engine: engine,
    modules: [MyGameModule()],
  );
  engine.start();
  runApp(
    MaterialApp(
      home: JustGameEngineEditor(engine: engine, plugin: plugin),
    ),
  );
}

// ── QUICKSTART 1: the same, with the hot reload hook of 2 ─────────────────

Future<void> quickstartRunEditor() async {
  final engine = Engine();
  await engine.initialize(); // boot the game's world here, as main.dart does
  final plugin = await JustGameEditorPlugin.register(
    engine: engine,
    modules: [MyGameModule()], // see 3.
    onReassemble: (plugin) => rewire(engine, plugin), // see 2.
  );
  engine.start();
  runApp(
    MaterialApp(
      home: JustGameEngineEditor(engine: engine, plugin: plugin),
    ),
  );
}

// ── QUICKSTART 3: a component, described once ──────────────────────────────

class MyHealthComponent extends Component {
  int maxHp = 3;
  bool invincible = false;
}

ComponentDefinition<MyHealthComponent> get myHealthDefinition =>
    ComponentDefinition(
      type: 'MyHealthComponent',
      create: MyHealthComponent.new,
      fields: [
        SchemaField(
          name: 'maxHp',
          kind: FieldTypes.integer,
          min: 0,
          read: (c) => (c as MyHealthComponent).maxHp,
          write: (c, v) => (c as MyHealthComponent).maxHp = v as int,
        ),
        SchemaField(
          name: 'invincible',
          kind: FieldTypes.boolean,
          read: (c) => (c as MyHealthComponent).invincible,
          write: (c, v) => (c as MyHealthComponent).invincible = v as bool,
        ),
      ],
      hints: const ComponentHints(
        name: 'Health',
        group: 'Gameplay',
        icon: Icons.favorite,
        fields: {
          'maxHp': FieldHint(label: 'Max HP', scrub: ScrubHint(integer: true)),
          'invincible': FieldHint(label: 'Invincible'),
        },
      ),
    );

class MyGameExtension implements RefreshableExtension {
  const MyGameExtension();

  @override
  String get id => 'my_game';

  @override
  void install(EngineContext context) =>
      context.definitions.register(myHealthDefinition);

  @override
  void refresh(EngineContext context) =>
      context.definitions.refresh([myHealthDefinition]);
}

Engine bootEngine() =>
    Engine(config: const EngineConfig(extensions: [MyGameExtension()]));

// ── README "Extending the editor" and QUICKSTART 3: a module ───────────────

class CoinComponent extends Component {}

class MyGameModule extends EditorModule {
  @override
  String get id => 'my_game';

  @override
  String get name => 'My Game';

  @override
  List<PrefabDefinition> get sharedPrefabs => [
    PrefabDefinition(
      id: 'my_game.coin',
      name: 'Coin',
      category: 'Pickups',
      icon: Icons.monetization_on,
      color: const Color(0xFFFFC107),
      placement: PrefabPlacement.point,
      defaultSize: const Size(16, 16),
      build: (position, size) => [
        TransformComponent(position: Vector3(position.dx, position.dy, 0)),
        CoinComponent(),
      ],
    ),
  ];

  @override
  List<EntityIcon> get entityIcons => [
    EntityIcon(
      id: 'my_game.icons',
      of: (entity) =>
          entity.hasComponent<CoinComponent>() ? Icons.monetization_on : null,
    ),
  ];
}

// ── QUICKSTART 2: after a hot reload ───────────────────────────────────────

final List<Spawner> mySpawners = [];

void rewire(Engine engine, JustGameEditorPlugin plugin) {
  plugin.syncModules([MyGameModule()]); // a module added since launch joins
  plugin.scope.spawners.value = mySpawners; // read at the next Play
}

void main() {
  test('the guides\' snippets compile', () {
    expect(readmeMain, isNotNull);
    expect(quickstartRunEditor, isNotNull);
    expect(rewire, isNotNull);
  });

  test("QUICKSTART's component registers, and refreshes, on an engine", () {
    final engine = bootEngine();
    addTearDown(engine.dispose);
    final first = engine.context.definitions.definitionByType(
      'MyHealthComponent',
    );
    expect(first, isNotNull);
    engine.context.refreshDefinitions();
    final again = engine.context.definitions.definitionByType(
      'MyHealthComponent',
    );
    expect(again, isNotNull);
    expect(again!.fields.map((f) => f.name), ['maxHp', 'invincible']);
  });
}
