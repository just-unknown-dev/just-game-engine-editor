// A module can take the whole viewport for a tool of its own, and offer to
// open files from the Assets dock in it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'package:just_game_engine_editor/src/ui/overlay/chrome/editor_chrome.dart'
    show WorkspaceHost;

import 'support/test_scope.dart';

class _PaintModule extends EditorModule {
  final List<String> ran = [];

  @override
  String get id => 'test.paint';

  @override
  String get name => 'Paint';

  @override
  List<WorkspaceDefinition> get workspaces => [
    WorkspaceDefinition(
      id: 'paint',
      label: 'Paint',
      icon: Icons.brush,
      fileExtensions: const ['png', 'jsprite'],
      build: (context, workspace) => Column(
        children: [
          Text('PAINTING ${workspace.path ?? 'nothing'}'),
          TextButton(onPressed: workspace.onClose, child: const Text('Done')),
        ],
      ),
    ),
    WorkspaceDefinition(
      id: 'graph',
      label: 'Graph',
      icon: Icons.account_tree,
      fileExtensions: const ['json', 'animator.json'],
      build: (context, workspace) => const Text('GRAPH'),
    ),
  ];

  @override
  List<AssetAction> get assetActions => [
    AssetAction(
      id: 'paint.edit',
      label: 'Edit sprite',
      icon: Icons.edit,
      appliesTo: (path, {required isDirectory}) =>
          !isDirectory && path.endsWith('.png'),
      run: (scope, path) {
        ran.add(path);
        scope.openInWorkspace(path);
      },
    ),
  ];
}

void main() {
  test('a module lists workspaces; a file opens in the one that fits best', () {
    final scope = testScope(modules: [_PaintModule()]);
    // The interface editor is the editor's own workspace and is always
    // there; the module's come after it.
    expect(
      [for (final w in scope.workspaces) w.id],
      [BuiltInWorkspaces.ui, 'paint', 'graph'],
    );
    expect(scope.activeWorkspace.value, isNull);

    expect(scope.openInWorkspace('assets/sprites/hero.PNG'), isTrue);
    expect(scope.activeWorkspace.value!.definition.id, 'paint');
    expect(scope.activeWorkspace.value!.path, 'assets/sprites/hero.PNG');

    // `animator.json` is a longer match than `json`, whoever declares it.
    expect(scope.openInWorkspace('assets/hero.animator.json'), isTrue);
    expect(scope.activeWorkspace.value!.definition.id, 'graph');

    expect(scope.openInWorkspace('assets/readme.txt'), isFalse);
    expect(scope.activeWorkspace.value!.definition.id, 'graph', reason: 'kept');

    expect(scope.openWorkspace('paint'), isTrue);
    expect(scope.activeWorkspace.value!.path, isNull);
    expect(scope.openWorkspace('nope'), isFalse);
    scope.closeWorkspace();
    expect(scope.activeWorkspace.value, isNull);
  });

  test('a workspace whose module goes away gives the viewport back', () {
    final module = _PaintModule();
    final scope = testScope(modules: [module]);
    scope.openWorkspace('paint');
    scope.modules.unregister(module.id);
    scope.reload();
    expect(
      [for (final w in scope.workspaces) w.id],
      [BuiltInWorkspaces.ui],
      reason: "only the editor's own is left",
    );
    expect(scope.activeWorkspace.value, isNull);
  });

  test('asset actions say which files they are for', () {
    final module = _PaintModule();
    final scope = testScope(modules: [module]);
    final action = scope.assetActions.single;
    expect(action.appliesTo('assets/a.png', isDirectory: false), isTrue);
    expect(action.appliesTo('assets/a.json', isDirectory: false), isFalse);
    expect(action.appliesTo('assets/png', isDirectory: true), isFalse);
    action.run(scope, 'assets/a.png');
    expect(module.ran, ['assets/a.png']);
    expect(scope.activeWorkspace.value!.path, 'assets/a.png');
  });

  testWidgets('it fills the editor, and the level\'s keys stand down', (
    tester,
  ) async {
    if (!kDebugMode) return;
    Engine.resetInstance();
    final engine = Engine();
    await tester.runAsync(engine.initialize);
    final plugin = JustGameEditorPlugin(
      engine: engine,
      modules: [_PaintModule()],
    );
    await tester.runAsync(plugin.onInitialize);
    plugin.setVisible(true);

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
    await tester.pump();
    expect(find.textContaining('PAINTING'), findsNothing);

    plugin.scope.openInWorkspace('assets/hero.png');
    await tester.pump();
    expect(find.text('PAINTING assets/hero.png'), findsOneWidget);

    // F5 is Play — always in scope, except while a workspace has the screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(plugin.playController.state.value, EditorPlayState.stopped);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.textContaining('PAINTING'), findsNothing);
    expect(plugin.scope.activeWorkspace.value, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    expect(plugin.playController.state.value, EditorPlayState.playing);

    plugin.playController.stop();
    await tester.pumpWidget(const SizedBox());
    plugin.dispose();
    Engine.resetInstance();
  });

  group('how it sits in the editor', () {
    Future<Rect> bodyRect(
      WidgetTester tester,
      Size window,
      WorkspacePresentation presentation, {
      ValueNotifier<bool>? fullScreen,
    }) async {
      tester.view
        ..physicalSize = window
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scope = testScope();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceHost(
              open: OpenWorkspace(
                WorkspaceDefinition(
                  id: 'w',
                  label: 'W',
                  icon: Icons.brush,
                  presentation: presentation,
                  build: (context, workspace) =>
                      const SizedBox.expand(key: Key('body')),
                ),
              ),
              workspace: WorkspaceContext(
                scope: scope,
                onClose: () {},
                fullScreen: fullScreen,
                onToggleFullScreen: fullScreen == null
                    ? null
                    : () => fullScreen.value = !fullScreen.value,
              ),
            ),
          ),
        ),
      );
      return tester.getRect(find.byKey(const Key('body')));
    }

    testWidgets('a dialog by default: the editor shows around it, dimmed', (
      tester,
    ) async {
      final rect = await bodyRect(
        tester,
        const Size(1600, 900),
        WorkspacePresentation.dialog,
      );
      expect(rect, const Rect.fromLTRB(40, 28, 1560, 872));
      expect(find.byKey(WorkspaceHost.scrimKey), findsOneWidget);
    });

    testWidgets('a small window has no margin to spare, so it fills', (
      tester,
    ) async {
      final rect = await bodyRect(
        tester,
        const Size(900, 600),
        WorkspacePresentation.dialog,
      );
      expect(rect, const Rect.fromLTRB(0, 0, 900, 600));
    });

    testWidgets('full screen when a workspace asks for it', (tester) async {
      final rect = await bodyRect(
        tester,
        const Size(1600, 900),
        WorkspacePresentation.fullScreen,
      );
      expect(rect, const Rect.fromLTRB(0, 0, 1600, 900));
    });

    testWidgets('the workspace can ask to fill the editor, and go back', (
      tester,
    ) async {
      final fullScreen = ValueNotifier(false);
      addTearDown(fullScreen.dispose);
      expect(
        await bodyRect(
          tester,
          const Size(1600, 900),
          WorkspacePresentation.dialog,
          fullScreen: fullScreen,
        ),
        const Rect.fromLTRB(40, 28, 1560, 872),
      );

      fullScreen.value = true;
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('body'))),
        const Rect.fromLTRB(0, 0, 1600, 900),
      );
      expect(find.byKey(WorkspaceHost.scrimKey), findsNothing);

      fullScreen.value = false;
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const Key('body'))),
        const Rect.fromLTRB(40, 28, 1560, 872),
      );
    });

    testWidgets('the scope keeps the choice while a workspace is open', (
      tester,
    ) async {
      final scope = testScope(modules: [_PaintModule()]);
      expect(scope.workspaceFullScreen.value, isFalse);
      scope
        ..openWorkspace('paint')
        ..toggleWorkspaceFullScreen();
      expect(scope.workspaceFullScreen.value, isTrue);
      scope.openWorkspace('graph');
      expect(scope.workspaceFullScreen.value, isTrue, reason: 'still filled');
    });
  });
}
