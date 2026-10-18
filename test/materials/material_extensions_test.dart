// What another module adds to the material windows — a tool on the
// toolbar, a section in the panel, an overlay over the preview — built from
// the window's view, and editing the material through it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_editor_core/just_editor_core.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/src/materials/materials.dart';

class _Extras extends EditorModule {
  @override
  String get id => 'extras';

  @override
  String get name => 'Extras';

  @override
  List<WorkspaceContribution> get workspaceContributions => [
    WorkspaceTool(
      workspaceId: WorkspaceIds.material2D,
      id: 'flash',
      icon: Icons.bolt,
      tooltip: 'Flash it',
      isActive: (v) => (v as Material2DWorkspaceView).shown.isOn('flash'),
      onTap: (v) => (v as Material2DWorkspaceView).change(
        (m) => m.withEffect('flash', true),
      ),
    ),
    WorkspaceSection(
      workspaceId: WorkspaceIds.material2D,
      id: 'about',
      title: 'Graph',
      build: (context, v) => Text(
        'Effects on: ${(v as Material2DWorkspaceView).shown.effects.length}',
      ),
    ),
    WorkspaceOverlay(
      workspaceId: WorkspaceIds.material2D,
      id: 'badge',
      build: (context, v, size) => const IgnorePointer(child: Text('Badge')),
    ),
    WorkspaceTool(
      workspaceId: WorkspaceIds.material,
      id: 'gold',
      icon: Icons.star,
      tooltip: 'Make it gold',
      onTap: (v) => (v as Material3DWorkspaceView).change(
        (m) => m.copyWith(color: 0xFFFFD700, metallic: 1),
      ),
    ),
    WorkspaceSection(
      workspaceId: WorkspaceIds.material,
      id: 'notes',
      title: 'Notes',
      build: (context, v) => Text('About ${v.path}'),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late EditorScope scope;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('jge_material_extras');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Left for the system's own clean-up.
      }
    });
  });

  Future<void> host(WidgetTester tester, Widget window) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: window)));
  }

  testWidgets('the 2-D window: a tool, a section and an overlay', (
    tester,
  ) async {
    File('${dir.path}/a.material2d.json').writeAsStringSync('{}');
    scope = EditorScope(world: World()..initialize(), modules: [_Extras()]);
    addTearDown(scope.dispose);
    final key = GlobalKey<Material2DWorkspaceState>();
    await host(
      tester,
      Material2DWorkspace(
        key: key,
        path: 'a.material2d.json',
        root: dir.path,
        workspace: WorkspaceContext(
          scope: scope,
          onClose: () {},
          path: 'a.material2d.json',
        ),
        loadOnStart: false,
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    expect(state.view.workspaceId, WorkspaceIds.material2D);
    expect(find.text('GRAPH'), findsOneWidget);
    expect(find.text('Effects on: 0'), findsOneWidget);
    expect(find.text('Badge'), findsOneWidget, reason: 'over the preview');

    await tester.tap(find.byTooltip('Flash it'));
    await tester.pump();
    expect(state.material.isOn('flash'), isTrue, reason: 'through the view');
    expect(find.text('Effects on: 1'), findsOneWidget, reason: 'built again');
  });

  testWidgets('the 3-D window: a tool and a section', (tester) async {
    File(
      '${dir.path}/a.material.json',
    ).writeAsStringSync(const MaterialFile().encode());
    scope = EditorScope(world: World()..initialize(), modules: [_Extras()]);
    addTearDown(scope.dispose);
    final key = GlobalKey<MaterialWorkspaceState>();
    await host(
      tester,
      MaterialWorkspace(
        key: key,
        path: 'a.material.json',
        root: dir.path,
        pictures: MaterialPictures(root: dir.path),
        workspace: WorkspaceContext(
          scope: scope,
          onClose: () {},
          path: 'a.material.json',
        ),
        loadOnStart: false,
      ),
    );
    final state = key.currentState!;
    await tester.runAsync(state.load);
    await tester.pump();
    expect(find.text('NOTES'), findsOneWidget);
    expect(find.text('About a.material.json'), findsOneWidget);
    await tester.tap(find.byTooltip('Make it gold'));
    await tester.pump();
    expect(state.shown.color, 0xFFFFD700);
    expect(state.shown.metallic, 1);
  });

  test("the editor's own module brings the material windows", () {
    final module = BuiltInMaterialsModule();
    expect(module.id, 'materials');
    expect(
      [for (final w in module.workspaces) w.id],
      [WorkspaceIds.material, WorkspaceIds.material2D],
    );
  });
}
