// A module teaches the designer with declarations, not patches. Each promise
// the contract makes is one test: a chord a module binds beats a built-in,
// its snapping wins at its priority, its state survives a reload, its editor
// data round-trips, its chrome sees the pointer first.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

class _RouteState {
  int edits = 0;
}

class _ClaimingOverlay extends DesignerOverlay with InteractiveOverlay {
  int presses = 0;
  @override
  String get id => 'test.claim';
  @override
  String get label => 'Claim';
  @override
  IconData get icon => Icons.pan_tool;
  @override
  void paint(OverlayPaintContext context) {}
  @override
  bool onPointerDown(OverlayPointerContext context) {
    presses++;
    return true;
  }
}

class _MagnetSnap extends SnapProvider {
  @override
  int get priority => 200;
  @override
  SnapResult snap(SnapRequest request) => const SnapResult(dx: 7, dy: 11);
}

class _Module extends EditorModule {
  int ran = 0;
  Map<String, Object?>? restored;
  @override
  String get id => 'test.module';
  @override
  String get name => 'Test';
  @override
  List<DesignerCommand> get commands => [
    DesignerCommand(id: 'test.hello', label: 'Hello', run: (_) => ran++),
  ];
  // Z is the built-in quarter turn; the module takes it over.
  @override
  List<KeyBinding> get keyBindings => const [
    KeyBinding(LogicalKeyboardKey.keyZ, 'test.hello'),
  ];
  @override
  List<SnapProvider> createSnapProviders(DesignerToolContext context) => [
    _MagnetSnap(),
  ];
  @override
  Object? createSessionState(DesignerToolContext context) => _RouteState();
  @override
  Map<String, Object?>? saveEditorData(LevelDesignerSession session) => {
    'edits': session.stateOf<_RouteState>()!.edits,
  };
  @override
  void restoreEditorData(
    LevelDesignerSession session,
    Map<String, Object?> data,
  ) => restored = data;
  @override
  List<StatusBarControl> get statusControls => [
    StatusBarControl(id: 'test.status', build: (_, _) => const Text('STATUS')),
  ];
  @override
  List<SidePanelSection> get designerPanels => [
    SidePanelSection(
      id: 'test.panel',
      title: 'Test panel',
      build: (_, _) => const Text('PANEL'),
    ),
  ];
  @override
  List<DesignerOverlay> get overlays => [_ClaimingOverlay()];
}

LevelDesignerSession _open(EditorScope scope) {
  // The module's designer is the one under test.
  if (scope.designers.isNotEmpty) {
    scope.selectDesigner(scope.designers.first.id);
  }
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
  test("a module's key binding overrides a built-in's", () {
    final module = _Module();
    final session = _open(testScope(modules: [module]));
    expect(session.handleKey(LogicalKeyboardKey.keyZ, gridSize: 32), isTrue);
    expect(module.ran, 1);
    expect(session.scope.commands.byId('designer.rotateClockwise'), isNotNull);
  });

  test("a module's snap provider wins at its priority", () {
    final session = _open(testScope(modules: [_Module()]));
    final result = session.snapper.resolve(
      const SnapRequest(moving: Rect.fromLTWH(3, 5, 10, 10), gridSize: 32),
    );
    expect(result.dx, 7);
    expect(result.dy, 11);
  });

  test('session state survives a module reload', () {
    final session = _open(testScope(modules: [_Module()]));
    final state = session.stateOf<_RouteState>()!;
    state.edits = 3;
    session.reloadModules();
    expect(session.stateOf<_RouteState>(), same(state));
  });

  test("a module's editor data round-trips under its id", () {
    final module = _Module();
    final session = _open(testScope(modules: [module]));
    session.stateOf<_RouteState>()!.edits = 5;
    final saved = session.editorData();
    expect((saved['modules'] as Map)['test.module'], {'edits': 5});
    session.restoreEditorData(saved);
    expect(module.restored, {'edits': 5});
  });

  test("a module's interactive overlay sees the press before any tool", () {
    final module = _Module();
    final session = _open(testScope(modules: [module]));
    session.camera.viewportSize = const Size(800, 600);
    expect(
      session.onChromePointerDown(const Offset(400, 300), const Size(800, 600)),
      isTrue,
    );
    expect(session.hasChromeGesture, isTrue);
    expect(
      (module.overlays.single as _ClaimingOverlay).presses,
      0,
      reason: 'the session builds its own overlay instances',
    );
    session.onChromePointerUp(const Offset(400, 300), const Size(800, 600));
    expect(session.hasChromeGesture, isFalse);
  });

  testWidgets("a module's status control and side panel appear", (
    tester,
  ) async {
    final session = _open(testScope(modules: [_Module()]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 400,
                height: 500,
                child: LevelDesignerWorkspace(
                  session: session,
                  gridSize: 32,
                  onClose: () {},
                  onGridSizeChanged: (_) {},
                ),
              ),
              DesignerStatusBar(
                session: session,
                gridSize: 32,
                onGridSizeChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('STATUS'), findsOneWidget);
    expect(find.text('PANEL'), findsOneWidget);
    expect(find.text('TEST PANEL'), findsOneWidget);
  });
}
