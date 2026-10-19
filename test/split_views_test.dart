// The 3-D viewport split four ways: top, front and side orthographic
// beside the perspective view; each pane in its quarter, the pointer sent
// to the pane it is over in that pane's own coordinates and through its
// view, the game's own picture not drawn under them, and the VIEW
// section's switch.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine/graphics_3d.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/panels/view_3d_panel.dart';
import 'package:just_game_engine_editor/src/ui/level_designer_3d/split/split_views.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the panes', () {
    final main = OrbitFlyEditorView.of(Camera(viewportSize: const Size(400, 300)))
      ..distance = 15;
    main.pivot.setValues(1, -2, 3);
    late SplitViews split;

    setUp(() => split = SplitViews(() => main));
    tearDown(() => split.dispose());

    test('top, front, side and perspective, each in its quarter', () {
      split.layout(const Size(402, 302));
      final panes = split.panes;
      expect(panes.map((p) => p.kind), [PaneKind.top, PaneKind.front, PaneKind.side, PaneKind.perspective]);
      expect(panes[0].rect, const Rect.fromLTWH(0, 0, 200, 150));
      expect(panes[3].rect, const Rect.fromLTWH(202, 152, 200, 150));
      expect(identical(panes[3].view, main), isTrue, reason: 'the editor\'s own view');
      expect(split.paneAt(const Offset(10, 10))?.kind, PaneKind.top);
      expect(split.paneAt(const Offset(300, 200))?.kind, PaneKind.perspective);
      expect(split.paneAt(const Offset(201, 10)), isNull, reason: 'the gap');
    });

    test('split, the flat views look where the editor was looking, from as far', () {
      split.toggle();
      expect(split.on.value, isTrue);
      for (final pane in split.panes.take(3)) {
        expect(pane.view.orthographic, isTrue);
        expect([pane.view.pivot.x, pane.view.pivot.y, pane.view.pivot.z], [1, -2, 3]);
        expect(pane.view.distance, 15);
      }
      expect(split.panes[0].view.pitch, lessThan(-1.5), reason: 'the top looks down');
    });

    test('a flat pane sized after the split shows what perspective would at its height', () {
      // Split before the panes had a size, their zoom was worked out for a
      // view one pixel high: the level shrank to a dot under the gizmo.
      split.toggle();
      split.layout(const Size(402, 302));
      final top = split.panes.first;
      top.view.viewportSize = top.rect.size;
      expect(top.view.camera.zoom, closeTo(top.view.zoom, 1e-9));
      expect(top.view.camera.zoom, greaterThan(5), reason: 'pixels a metre at 15 m, 150 high');
    });
  });

  test('a pane stands in for the editor\'s view while it is drawn or handled', () {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final scope = EditorScope(builtIns: const [BuiltInEditorModule.new], world: world);
    addTearDown(scope.dispose);
    scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    final main = scope.editorView as OrbitFlyEditorView;
    final split = SplitViews(() => main);
    addTearDown(split.dispose);
    split.layout(const Size(400, 300));
    final top = split.panes.first;
    final seen = scope.throughPane(top, () => scope.editorView);
    expect(identical(seen, top.view), isTrue);
    expect(top.view.viewportSize, top.rect.size);
    expect(identical(scope.editorView, main), isTrue, reason: 'given back');
    expect(identical(scope.sceneView, main), isTrue);
  });

  group('in the editor', () {
    late Engine engine;
    late Graphics3D graphics;
    late JustGameEditorPlugin plugin;

    setUp(() async {
      graphics = Graphics3D(device: NullGpuDevice(shaders: rendererNullShaders), keepEdges: true);
      engine = Engine(config: EngineConfig(graphics3D: graphics));
      await engine.initialize();
      plugin = JustGameEditorPlugin(engine: engine, startVisible: false);
      await plugin.attach(plugin.engine);
      plugin
        ..setVisible(true)
        ..viewport.updateCanvasSize(const Size(402, 302));
      plugin.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    });
    tearDown(() {
      plugin.dispose();
      engine.dispose();
    });

    test('the pointer goes to the pane it is over, in that pane\'s coordinates', () {
      plugin.toggleSplitViews();
      expect(plugin.activeSplit, isNotNull);
      plugin.splitViews.layout(const Size(402, 302));
      Offset? seenAt;
      EditorView? seenThrough;
      plugin.viewport.openMenu = (local, _) {
        seenAt = local;
        seenThrough = plugin.scope.editorView;
      };
      // A right-click that never moves opens the menu where it was, in the
      // front pane (top right).
      plugin
        ..pointerDown(const PointerDownEvent(position: Offset(252, 60), buttons: kSecondaryButton))
        ..pointerUp(const PointerUpEvent(position: Offset(252, 60)));
      expect(plugin.splitViews.active?.kind, PaneKind.front);
      expect(seenAt, const Offset(50, 60), reason: 'its own corner is 0, 0');
      expect(identical(seenThrough, plugin.splitViews.panes[1].view), isTrue);
      expect(plugin.viewport.canvasSize, const Size(402, 302), reason: 'given back');
    });

    test('the game\'s own picture is not drawn under the panes', () {
      plugin.toggleSplitViews();
      plugin.update(1 / 60);
      expect(plugin.sceneAids.skippedViews, contains(engine.rendering.view));
      expect(identical(plugin.scope.editorView, plugin.splitViews.panes.last.view), isTrue, reason: 'keys go to the pane in use');
      plugin.toggleSplitViews();
      plugin.update(1 / 60);
      expect(plugin.sceneAids.skippedViews, isEmpty);
      expect(plugin.scope.viewOverride, isNull);
    });

    test('each pane is drawn in its quarter', () {
      plugin.toggleSplitViews();
      final recorder = ui.PictureRecorder();
      plugin.renderOverlay(Canvas(recorder), const Size(402, 302));
      recorder.endRecording().dispose();
      expect(plugin.splitViews.panes.last.rect, const Rect.fromLTWH(202, 152, 200, 150));
    });

    test('not in a 2-D scene', () {
      plugin.sceneState.openScene(EditorScene(name: 'flat'));
      plugin.toggleSplitViews();
      expect(plugin.activeSplit, isNull);
    });
  });

  testWidgets('the VIEW section switches the four views', (tester) async {
    final world = World()..initialize();
    addTearDown(world.dispose);
    final scope = EditorScope(builtIns: const [BuiltInEditorModule.new], world: world);
    addTearDown(scope.dispose);
    scope.sceneState.openScene(EditorScene(name: 'deep', mode: SceneMode.threeD));
    final split = SplitViews(() => scope.sceneView as OrbitFlyEditorView);
    addTearDown(split.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: View3DPanel(scope: scope, split: split))));
    expect(find.text('Four views'), findsOneWidget);
    await tester.tap(find.byType(EditorToggle).at(1));
    await tester.pump();
    expect(split.on.value, isTrue);
  });
}
