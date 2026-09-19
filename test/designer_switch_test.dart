// The Level Designer is the built-in one until a module's designer is
// chosen. With no module designer there is nothing to choose, so no switch;
// with one, the header lists both and the choice travels with the scene.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

class _GenreModule extends EditorModule {
  @override
  String get id => 'genre';
  @override
  String get name => 'Genre';
  @override
  IconData get icon => Icons.sports_esports;

  @override
  List<PrefabDefinition> get prefabs => [
    PrefabDefinition(
      id: 'genre.thing',
      name: 'Thing',
      category: 'Genre',
      icon: Icons.star,
      color: Colors.pink,
      build: (_, _) => [TransformComponent()],
    ),
  ];

  @override
  List<PrefabCategory> get prefabCategories => const [
    PrefabCategory(label: 'Genre', order: 5),
  ];

  @override
  List<StatusBarControl> get statusControls => [
    StatusBarControl(id: 'genre.status', build: (_, _) => const Text('G')),
  ];

  @override
  List<LevelToolHandler> createTools(DesignerToolContext context) => [_Tool()];

  @override
  List<DesignerOverlay> get overlays => [_Overlay()];

  @override
  Object? createSessionState(DesignerToolContext context) => _State();
}

/// Tools only: nothing the heuristic sees, so it must say so itself.
class _ToolsOnlyModule extends EditorModule {
  _ToolsOnlyModule({this.declares = false});
  final bool declares;
  @override
  String get id => 'tools';
  @override
  String get name => 'Tools';
  @override
  IconData get icon => Icons.build;
  @override
  bool get providesLevelDesigner => declares;
  @override
  List<LevelToolHandler> createTools(DesignerToolContext context) => [_Tool()];
}

class _Tool extends LevelToolHandler {
  @override
  String get id => 'genre.tool';
  @override
  String get label => 'Genre';
  @override
  IconData get icon => Icons.star;
}

class _Overlay extends DesignerOverlay {
  @override
  String get id => 'genre.overlay';
  @override
  String get label => 'Genre';
  @override
  IconData get icon => Icons.star;
  @override
  void paint(OverlayPaintContext context) {}
}

class _State {}

LevelDesignerSession _open(EditorScope scope) {
  final session = LevelDesignerSession(
    scope: scope,
    uniqueName: (p) => p,
    onDuplicate: () {},
    onDelete: () {},
    onArray: (_, _) {},
    readModifiers: () => const ModifierKeys(),
  );
  addTearDown(session.dispose);
  return session;
}

void main() {
  test('a module with designer content is a designer; tools-only opts in', () {
    expect(testScope(modules: [_GenreModule()]).designers, hasLength(1));
    expect(testScope(modules: [_ToolsOnlyModule()]).designers, isEmpty);
    expect(
      testScope(modules: [_ToolsOnlyModule(declares: true)]).designers,
      hasLength(1),
    );
    expect(testScope().designers, isEmpty);
  });

  test('the built-in designer is the default; a module waits to be chosen', () {
    final scope = testScope(modules: [_GenreModule()]);
    expect(scope.activeDesigner.value, isNull);
    expect(scope.prefabs.byId('genre.thing'), isNull);
    expect(scope.prefabs.byId(BuiltInPrefabs.rectangleId), isNotNull);
    expect(scope.statusControls, isEmpty);
    expect(scope.prefabCategoryOrder('Genre'), greaterThan(1000));

    scope.selectDesigner('genre');
    expect(scope.activeDesigner.value, 'genre');
    expect(scope.prefabs.byId('genre.thing'), isNotNull);
    expect(scope.prefabs.byId(BuiltInPrefabs.rectangleId), isNotNull);
    expect(scope.statusControls.map((c) => c.id), ['genre.status']);
    expect(scope.prefabCategoryOrder('Genre'), 5);

    scope.selectDesigner(null);
    expect(scope.prefabs.byId('genre.thing'), isNull);
    expect(scope.statusControls, isEmpty);
  });

  test('an unknown id, or a module that went away, means the default', () {
    final module = _GenreModule();
    final scope = testScope(modules: [module]);
    scope.selectDesigner('nope');
    expect(scope.activeDesigner.value, isNull);

    scope.selectDesigner('genre');
    scope.modules.unregister('genre');
    scope.reload();
    expect(scope.activeDesigner.value, isNull);
    expect(scope.prefabs.byId('genre.thing'), isNull);
  });

  test('an open session swaps tools, overlays and state with the designer', () {
    final scope = testScope(modules: [_GenreModule()]);
    final session = _open(scope);
    expect(session.tools.byId('genre.tool'), isNull);
    expect(session.overlays.byId('genre.overlay'), isNull);
    expect(session.stateOf<_State>(), isNull);

    scope.selectDesigner('genre');
    expect(session.tools.byId('genre.tool'), isNotNull);
    expect(session.overlays.byId('genre.overlay'), isNotNull);
    expect(session.stateOf<_State>(), isNotNull);
    // The built-ins are part of every designer.
    expect(session.tools.byId(BuiltInTools.select), isNotNull);

    session.controller.toolId.value = 'genre.tool';
    session.controller.activePrefabId.value = 'genre.thing';
    scope.selectDesigner(null);
    expect(session.tools.byId('genre.tool'), isNull);
    expect(session.stateOf<_State>(), isNull);
    // What the switch took away is not left selected.
    expect(session.tools.byId(session.controller.toolId.value), isNotNull);
    expect(
      scope.prefabs.byId(session.controller.activePrefabId.value!),
      isNotNull,
    );
  });

  test('the choice travels with the scene', () {
    final scope = testScope(modules: [_GenreModule()]);
    final session = _open(scope);
    scope.selectDesigner('genre');
    final saved = session.editorData();
    expect(saved['designer'], 'genre');

    scope.selectDesigner(null);
    session.restoreEditorData(saved);
    expect(scope.activeDesigner.value, 'genre');

    // A scene saved without a choice, or before the switch existed, opens
    // in the built-in designer.
    session.restoreEditorData(const {});
    expect(scope.activeDesigner.value, isNull);
    expect(session.editorData().containsKey('designer'), isFalse);
  });

  testWidgets('the header shows a switch only when there is a choice', (
    tester,
  ) async {
    Future<void> pump(EditorScope scope) async {
      final session = _open(scope);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditorScopeProvider(
              scope: scope,
              child: LevelDesignerWorkspace(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
    }

    await pump(testScope());
    expect(find.text('Level Designer'), findsOneWidget);
    expect(find.byType(DesignerSwitch), findsNothing);

    final scope = testScope(modules: [_GenreModule()]);
    await pump(scope);
    expect(find.byType(DesignerSwitch), findsOneWidget);
    expect(find.text(DesignerSwitch.defaultLabel), findsOneWidget);
    expect(find.text('Thing'), findsNothing);

    await tester.tap(find.byType(DesignerSwitch));
    await tester.pumpAndSettle();
    expect(find.text('Genre'), findsOneWidget);
    await tester.tap(find.text('Genre'));
    await tester.pumpAndSettle();

    expect(scope.activeDesigner.value, 'genre');
    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Thing'), findsOneWidget);
    expect(find.text('G'), findsNothing); // the status bar is a separate strip
  });
}
