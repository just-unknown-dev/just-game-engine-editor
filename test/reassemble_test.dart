// A hot reload reaches the editor.
//
// On a hot reload Flutter calls State.reassemble and nothing else: main,
// constructors and static initializers do not run again. These tests drive
// that path — tester.binding.reassembleApplication() is what the tool does —
// with "code" a test edits in between, and check that what the editor built
// from code once is built again, and what must happen once happens once.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/built_in_docks.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart';

/// A module whose code a test edits between reloads.
class _EditedModule extends EditorModule {
  _EditedModule({this.moduleId = 'test.edited'});

  final String moduleId;
  int registered = 0;
  int reassembled = 0;
  bool disposed = false;
  List<String> buttons = ['test.first'];
  Color presetAccent = const Color(0xFF00FF00);

  @override
  String get id => moduleId;

  @override
  String get name => 'Edited';

  @override
  List<ToolbarButton> get toolbarButtons => [
    for (final id in buttons)
      ToolbarButton(id: id, icon: Icons.add, tooltip: id, onPressed: (_) {}),
  ];

  @override
  List<ThemePreset> get themePresets => [
    ThemePreset(
      id: 'test.preset',
      label: 'Test',
      data: EditorThemeData.classic.withAccent(presetAccent),
    ),
  ];

  @override
  void onRegister(EditorModuleContext context) => registered++;

  @override
  void onReassemble(EditorModuleContext context) => reassembled++;

  @override
  void dispose() => disposed = true;
}

/// A component whose class "gains" a field: an instance made before the
/// reload never set [shine], and reading it throws, as a new non-nullable
/// field does on an instance the reload kept.
class Gem extends Component {
  int value = 1;
  late double shine;
}

/// The kit that defines [Gem]; [withShine] is the edit.
final class GemKit implements RefreshableExtension {
  bool withShine = false;

  @override
  String get id => 'test.gems';

  ComponentDefinition<Gem> get definition => ComponentDefinition<Gem>(
    type: 'GemComponent',
    create: () => Gem()..shine = 0.25,
    fields: [
      SchemaField(
        name: 'value',
        kind: FieldTypes.integer,
        read: (c) => (c as Gem).value,
        write: (c, v) => (c as Gem).value = v as int,
      ),
      if (withShine)
        SchemaField(
          name: 'shine',
          kind: FieldTypes.decimal,
          read: (c) => (c as Gem).shine,
          write: (c, v) => (c as Gem).shine = v as double,
        ),
    ],
  );

  @override
  void install(EngineContext context) =>
      context.definitions.registerAll([definition], ifAbsent: true);

  @override
  void refresh(EngineContext context) =>
      context.definitions.refresh([definition]);
}

/// What the tool does on `r`: reassemble, then the frame that shows it. The
/// binding finishes a reassemble only once a frame is drawn, which a test
/// draws by pumping.
Future<void> hotReload(WidgetTester tester) async {
  unawaited(tester.binding.reassembleApplication());
  await tester.pump();
}

Future<JustGameEditorPlugin> pumpEditor(
  WidgetTester tester, {
  List<EditorModule> modules = const [],
  List<ContextExtension> extensions = const [],
  void Function(JustGameEditorPlugin plugin)? onReassemble,
}) async {
  final engine = Engine(config: EngineConfig(extensions: extensions));
  addTearDown(engine.dispose);
  await tester.runAsync(engine.initialize);
  final plugin = JustGameEditorPlugin(
    engine: engine,
    modules: modules,
    onReassemble: onReassemble,
  );
  addTearDown(plugin.dispose);
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
  return plugin;
}

void main() {
  testWidgets('a hot reload rebuilds what a module contributes', (
    tester,
  ) async {
    final module = _EditedModule();
    final plugin = await pumpEditor(tester, modules: [module]);
    expect(plugin.scope.toolbarButtons.map((b) => b.id), ['test.first']);

    module.buttons = ['test.first', 'test.second']; // the edit
    await hotReload(tester);
    await tester.pump();

    expect(plugin.scope.toolbarButtons.map((b) => b.id), [
      'test.first',
      'test.second',
    ]);
  });

  testWidgets('onRegister runs once; onReassemble once per reload', (
    tester,
  ) async {
    final module = _EditedModule();
    await pumpEditor(tester, modules: [module]);
    expect(module.registered, 1);
    expect(module.reassembled, 0);

    await hotReload(tester);
    await hotReload(tester);
    await tester.pump();

    expect(module.registered, 1, reason: 'one-time setup is not repeated');
    expect(module.reassembled, 2);
  });

  test("a module's edited preset is the palette in use", () {
    // Which preset is in use is the settings' to say, and the overlay
    // follows them; this is the scope's half: the same preset, made again.
    final module = _EditedModule();
    final scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: World()..initialize(),
      modules: [module],
    );
    addTearDown(scope.dispose);
    final theme = scope.theme..select('test.preset');
    expect(theme.current.value.primary, const Color(0xFF00FF00));

    module.presetAccent = const Color(0xFF0000FF); // the edit
    scope.reassemble();

    expect(theme.currentId.value, 'test.preset');
    expect(theme.current.value.primary, const Color(0xFF0000FF));
  });

  testWidgets('a preset a module stopped offering is gone', (tester) async {
    final module = _EditedModule();
    final plugin = await pumpEditor(tester, modules: [module]);
    expect(plugin.scope.theme.preset('test.preset'), isNotNull);

    plugin.syncModules(const []); // the module taken out of main
    await hotReload(tester);
    await tester.pump();

    expect(plugin.scope.theme.preset('test.preset'), isNull);
    expect(module.disposed, isTrue);
  });

  testWidgets('the built-in docks are made again', (tester) async {
    final plugin = await pumpEditor(tester);
    final before = BuiltInDocks.forPlugin(plugin);
    expect(BuiltInDocks.forPlugin(plugin), same(before), reason: 'cached');

    await hotReload(tester);
    await tester.pump();

    final after = BuiltInDocks.forPlugin(plugin);
    expect(after, isNot(same(before)));
    expect(after.map((d) => d.id), before.map((d) => d.id));
  });

  testWidgets("the app's onReassemble runs on each reload", (tester) async {
    var calls = 0;
    final spawner = Spawner(
      id: 'test.player',
      spawn: (world, point) => world.createEntity(name: 'Player'),
    );
    final plugin = await pumpEditor(
      tester,
      onReassemble: (p) {
        calls++;
        p.scope.spawners.value = [spawner]; // handed over anew
      },
    );
    expect(plugin.spawners, isEmpty);

    await hotReload(tester);
    await tester.pump();

    expect(calls, 1);
    expect(plugin.spawners.map((s) => s.id), ['test.player']);
    expect(plugin.playController.spawners, same(plugin.spawners));
  });

  testWidgets('syncModules adds and removes, and keeps what stays', (
    tester,
  ) async {
    final kept = _EditedModule(moduleId: 'test.kept');
    final gone = _EditedModule(moduleId: 'test.gone');
    final plugin = await pumpEditor(tester, modules: [kept, gone]);

    final added = _EditedModule(moduleId: 'test.added');
    plugin.syncModules([_EditedModule(moduleId: 'test.kept'), added]);

    expect(plugin.scope.modules.all.map((m) => m.id), [
      'test.kept',
      'test.added',
    ]);
    expect(plugin.scope.modules.byId('test.kept'), same(kept));
    expect(gone.disposed, isTrue);
    expect(added.registered, 1);
  });

  group('a component that gained a field', () {
    testWidgets('the inspector reads the new definition', (tester) async {
      final kit = GemKit();
      final plugin = await pumpEditor(tester, extensions: [kit]);
      ComponentDefinition? def() =>
          plugin.scope.definitions.definitionByType('GemComponent');
      expect(def()!.fields.map((f) => f.name), ['value']);

      kit.withShine = true; // the edit
      await hotReload(tester);
      await tester.pump();

      expect(def()!.fields.map((f) => f.name), ['value', 'shine']);
    });

    testWidgets('an instance that cannot read it is made again', (
      tester,
    ) async {
      final kit = GemKit();
      final plugin = await pumpEditor(tester, extensions: [kit]);
      final engine = plugin.engine;
      final entity = engine.world.createEntity(name: 'Gem')
        ..addComponent(Gem()..value = 7);
      final old = entity.getComponent<Gem>()!;

      kit.withShine = true;
      await hotReload(tester);
      await tester.pump();

      final now = entity.getComponent<Gem>()!;
      expect(now, isNot(same(old)));
      expect(now.value, 7, reason: 'what it held is kept');
      expect(now.shine, 0.25, reason: 'the new field takes its default');
    });

    testWidgets('an instance that reads it is kept as it is', (tester) async {
      final kit = GemKit();
      final plugin = await pumpEditor(tester, extensions: [kit]);
      final engine = plugin.engine;
      final entity = engine.world.createEntity(name: 'Gem')
        ..addComponent(Gem()..shine = 1);
      final old = entity.getComponent<Gem>()!;

      kit.withShine = true;
      await hotReload(tester);
      await tester.pump();

      expect(entity.getComponent<Gem>(), same(old), reason: 'undo holds it');
    });

    testWidgets('nothing is swapped during a play-test', (tester) async {
      final kit = GemKit();
      final plugin = await pumpEditor(tester, extensions: [kit]);
      final engine = plugin.engine;
      final entity = engine.world.createEntity(name: 'Gem')
        ..addComponent(Gem());
      final old = entity.getComponent<Gem>()!;
      plugin.playController.state.value = EditorPlayState.playing;

      kit.withShine = true;
      await hotReload(tester);
      await tester.pump();

      expect(entity.getComponent<Gem>(), same(old));
      plugin.playController.state.value = EditorPlayState.stopped;
    });
  });

  test('no editor style or definition is a static final', () {
    // Built once and never again: an edit to one would not show until a
    // restart, nor would a theme change. Each must be a getter.
    // A class's static, or a top-level declaration — not a local.
    final pattern = RegExp(
      r'^(?:  static final|final) (?:\w+ )?\w+ =\s*'
      r'(?:TextStyle|PrefabDefinition|PrefabVariant|WorkspaceDefinition|'
      r'DockDefinition)\(',
      multiLine: true,
    );
    final readsTheme = RegExp(
      r'^(?:  static final|final) [^=;(\n]*=[^;]*EditorTheme\.',
      multiLine: true,
    );
    final offenders = <String>[
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          if (pattern.hasMatch(file.readAsStringSync()) ||
              readsTheme.hasMatch(file.readAsStringSync()))
            file.path,
    ];
    expect(offenders, isEmpty);
  });
}
