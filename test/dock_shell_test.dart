// The bottom dock panel: tabs, what it remembers, where it shows, and what
// it costs to keep open.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/docks/shell/dock_panel.dart';
import 'package:just_game_engine_editor/src/ui/overlay/editor_overlay.dart'
    show GameCanvasArea;

class _WavesModule extends EditorModule {
  int builds = 0;
  int waves = 3;

  @override
  String get id => 'test.waves';

  @override
  String get name => 'Waves';

  @override
  List<DockDefinition> get docks => [
    DockDefinition(
      id: 'test.waves',
      label: 'Waves',
      icon: Icons.waves,
      order: 200,
      defaultHeight: 240,
      tabBadge: (_) => DockBadge('$waves', DockSeverity.warning),
      readout: DockReadout(label: 'Waves', value: (_) => '$waves left'),
      headerActions: (context, dock) => [
        IconButton(
          tooltip: 'Skip a wave',
          icon: const Icon(Icons.skip_next),
          onPressed: () => waves--,
        ),
      ],
      build: (context, dock) {
        builds++;
        final filter = dock.memory?.read<String>('filter') ?? 'none';
        return Column(
          children: [
            Text('WAVES BODY filter=$filter arg=${dock.args['from']}'),
            TextButton(
              onPressed: () => dock.memory?.write('filter', 'bosses'),
              child: const Text('Only bosses'),
            ),
          ],
        );
      },
    ),
    DockDefinition(
      id: 'test.hidden',
      label: 'Hidden',
      icon: Icons.visibility_off,
      order: 210,
      pinnedByDefault: false,
      build: (context, dock) => const Text('HIDDEN BODY'),
    ),
  ];
}

DockDefinition _dock(String id, {bool pinned = true, double height = 280}) =>
    DockDefinition(
      id: id,
      label: id,
      icon: Icons.circle,
      pinnedByDefault: pinned,
      defaultHeight: height,
      build: (context, dock) => const SizedBox(),
    );

void main() {
  group('the controller', () {
    late DockController c;
    setUp(() {
      c = DockController()
        ..reconcile([_dock('a'), _dock('b'), _dock('c', pinned: false)]);
    });
    tearDown(() => c.dispose());

    test('tabs are the docks that pin by default, in order', () {
      expect(c.order.value, ['a', 'b']);
      c.open('c');
      expect(c.order.value, ['a', 'b', 'c'], reason: 'opening one pins it');
      c.unpin('c');
      expect(c.order.value, ['a', 'b']);
      expect(c.activeDock, 'a', reason: 'the panel does not go blank');
      // Unpinned stays unpinned when the docks are looked at again…
      c.reconcile([_dock('a'), _dock('b'), _dock('c')]);
      expect(c.order.value, ['a', 'b']);
      // …but a dock that is new joins the bar.
      c.reconcile([_dock('a'), _dock('b'), _dock('c'), _dock('d')]);
      expect(c.order.value, ['a', 'b', 'd']);
    });

    test('reorder, cycle, and a dock that goes away', () {
      c
        ..move('b', 0)
        ..open('b')
        ..cycle(1);
      expect(c.order.value, ['b', 'a']);
      expect(c.activeDock, 'a');
      c.cycle(1);
      expect(c.activeDock, 'b', reason: 'wraps');
      c.reconcile([_dock('a')]);
      expect(c.activeDock, isNull);
      expect(c.order.value, ['a']);
    });

    test('the panel toggles back to the dock last shown', () {
      c
        ..open('b')
        ..togglePanel();
      expect(c.activeDock, isNull);
      c.togglePanel();
      expect(c.activeDock, 'b');
      c
        ..open(DockController.settingsId)
        ..togglePanel();
      expect(c.activeDock, 'b', reason: 'settings is not a dock');
    });

    test('height: resized, clamped, reset, and all of it when maximised', () {
      c.open('a');
      expect(c.panelHeight(600), 280);
      c.resize('a', -100, fallback: 280, max: 700);
      expect(c.panelHeight(600), 380);
      expect(c.panelHeight(300), 300, reason: 'never more than there is');
      c.maximised.value = true;
      expect(c.panelHeight(600), 600);
      c.close();
      expect(c.maximised.value, isFalse);
      expect(c.panelHeight(600), 0);
      c
        ..open('a')
        ..resetHeight('a');
      expect(c.panelHeight(600), 280);
    });

    test('popping out takes a dock off the bar\'s hands, and back', () {
      c
        ..open('a')
        ..popOut('a');
      expect(c.poppedOut.value, {'a'});
      expect(c.activeDock, 'b');
      c.popIn('a');
      expect(c.poppedOut.value, isEmpty);
      expect(c.activeDock, 'a');
    });

    test('the panel is collapsed on a fresh start', () {
      // Nothing saved at all: no dock, and the status strip is all that
      // is at the foot of the editor.
      final fresh = DockController()..attach(saved: '', store: (_) {});
      addTearDown(fresh.dispose);
      fresh.reconcile([_dock('a'), _dock('b')]);

      expect(fresh.activeDock, isNull);
      expect(fresh.panelHeight(600), 0);

      // And F2 opens one, which is when the panel takes any room.
      fresh.togglePanel();
      expect(fresh.activeDock, 'a');
      expect(fresh.panelHeight(600), greaterThan(0));
    });

    test('everything survives a restart', () {
      String? stored;
      c
        ..attach(saved: '', store: (json) => stored = json)
        ..open('b')
        ..move('b', 0)
        ..unpin('a')
        ..resize('b', -40, fallback: 280, max: 700);
      c.memoryOf('b')
        ..write('filter', 'errors')
        ..write('zoom', 2);
      c.flush();
      expect(stored, isNotNull);

      final next = DockController()..attach(saved: stored!, store: (_) {});
      addTearDown(next.dispose);
      next.reconcile([_dock('a'), _dock('b')]);
      // The panel opens collapsed, whatever was showing when the editor
      // was last shut: the level is what an editor opens on.
      expect(next.activeDock, isNull);
      // But it remembers which dock it was, so F2 brings that one back
      // rather than whichever happens to be first.
      next.togglePanel();
      expect(next.activeDock, 'b');
      expect(next.order.value, ['b'], reason: 'a stays unpinned');
      expect(next.heightOf('b', fallback: 280), 320);
      expect(next.memoryOf('b').read<String>('filter'), 'errors');
      expect(next.memoryOf('b').read<double>('zoom'), 2.0);
      expect(next.memoryOf('a').read<String>('filter'), isNull);

      // A damaged preference is ignored, not fatal.
      final broken = DockController()..attach(saved: '{oops', store: (_) {});
      addTearDown(broken.dispose);
      expect(broken.activeDock, isNull);
    });
  });

  group('in the editor', () {
    late JustGameEditorPlugin plugin;
    late _WavesModule module;

    Future<void> pump(WidgetTester tester, {bool designer = false}) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Engine.resetInstance();
      final engine = Engine();
      await tester.runAsync(engine.initialize);
      module = _WavesModule();
      plugin = JustGameEditorPlugin(engine: engine, modules: [module]);
      await tester.runAsync(plugin.onInitialize);
      plugin.setVisible(true);
      if (!plugin.isStatusPanelVisible.value) {
        plugin.toggleStatusPanelVisibility();
      }
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
      await tester.pump();
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      plugin.dispose();
      Engine.resetInstance();
    }

    DockController dock() => plugin.scope.dockController;

    /// The panel slides open, and until it has, its upper part cannot be
    /// clicked: let it finish.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump(); // the frame the slide starts on
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('a module\'s dock is a tab like the built-in ones', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      expect(dock().order.value, [
        'logs',
        'assets',
        'timeline',
        'uitheme',
        'fps',
        'entities',
        'problems',
        'search',
        'test.waves',
      ]);
      expect(find.byType(DockPanel), findsNothing, reason: 'collapsed');
      // Its readout is a fact on the status bar. The bar is one button: a
      // click anywhere opens the panel, and the tab picks the dock.
      expect(find.text('Waves  3 left'), findsOneWidget);
      await tester.tap(find.text('Waves  3 left'));
      await settle(tester);
      expect(find.byType(DockPanel), findsOneWidget);
      expect(dock().activeDock, 'logs', reason: 'the first tab, not Waves');
      await tester.tap(
        find.descendant(
          of: find.byType(DockPanel),
          matching: find.text('Waves'),
        ),
      );
      await tester.pump();
      expect(find.textContaining('WAVES BODY'), findsOneWidget);

      // Another click on the bar shuts it; F2 is the same switch.
      await tester.tap(find.text('Waves  3 left'));
      await settle(tester);
      expect(dock().activeDock, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await settle(tester);
      expect(dock().activeDock, 'test.waves', reason: 'back where it was');
      for (final tab in [
        'Console',
        'Assets',
        'Timeline',
        'Profiler',
        'World',
      ]) {
        expect(find.text(tab), findsWidgets, reason: tab);
      }
      // Its badge is on its tab, and its own buttons are in the header.
      expect(
        find.descendant(of: find.byType(DockPanel), matching: find.text('3')),
        findsOneWidget,
      );
      expect(find.byTooltip('Skip a wave'), findsOneWidget);

      // The dock kept out of the bar is in the + menu.
      expect(find.text('Hidden'), findsNothing);
      await tester.tap(find.byTooltip('More docks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hidden'));
      await tester.pumpAndSettle();
      expect(find.text('HIDDEN BODY'), findsOneWidget);
      expect(dock().order.value.last, 'test.hidden');
      await done(tester);
    });

    testWidgets('a dock remembers, and a refresh does not rebuild it', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      dock().open('test.waves', args: {'from': 'test'});
      await settle(tester);
      expect(find.textContaining('arg=test'), findsOneWidget);
      await tester.tap(find.text('Only bosses'));
      expect(dock().memoryOf('test.waves').read<String>('filter'), 'bosses');

      final before = module.builds;
      module.waves = 1;
      // Several strip refreshes: the readout follows, the dock is left alone.
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Waves  1 left'), findsOneWidget);
      expect(module.builds - before, lessThanOrEqualTo(8));
      await done(tester);
    });

    testWidgets('keys: Ctrl+` for the panel, Ctrl+Shift+A for Assets', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      Future<void> chord(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await chord(LogicalKeyboardKey.keyA, shift: true);
      expect(dock().activeDock, 'assets');
      await chord(LogicalKeyboardKey.backquote);
      expect(dock().activeDock, isNull);
      await chord(LogicalKeyboardKey.backquote);
      expect(dock().activeDock, 'assets', reason: 'back to the last one');
      await chord(LogicalKeyboardKey.keyM, shift: true);
      expect(dock().maximised.value, isTrue);
      await done(tester);
    });

    testWidgets('maximise fills the viewport; pop-out floats and comes back', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      dock().open('test.waves');
      await settle(tester);
      final normal = tester.getSize(find.byType(DockPanel)).height;
      expect(normal, 240);
      await tester.tap(find.byTooltip('Maximise'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(DockPanel)).height, greaterThan(800));
      await tester.tap(find.byTooltip('Restore'));
      await tester.pumpAndSettle();

      // Whatever is first on the bar takes the panel when a dock leaves it.
      dock()
        ..pin('test.hidden', at: 0)
        ..open('test.waves');
      await settle(tester);
      await tester.tap(find.byTooltip('Pop out into its own window'));
      await tester.pumpAndSettle();
      expect(dock().poppedOut.value, {'test.waves'});
      expect(find.textContaining('WAVES BODY'), findsOneWidget);
      expect(dock().activeDock, 'test.hidden');
      expect(find.text('HIDDEN BODY'), findsOneWidget, reason: 'two at once');
      await tester.tap(find.byTooltip('Put it back in the panel'));
      await tester.pumpAndSettle();
      expect(dock().poppedOut.value, isEmpty);
      expect(dock().activeDock, 'test.waves');
      await done(tester);
    });

    testWidgets('opening a dock makes the game smaller, not covered', (
      tester,
    ) async {
      if (!kDebugMode) return;
      await pump(tester);
      Rect canvas() => tester.getRect(find.byType(GameCanvasArea));
      final window = tester.getRect(find.byType(JustGameEditorOverlay));

      // With the editor open the game already gives up the right panel and
      // the status bar at its foot.
      final shut = canvas();
      expect(shut.width, lessThan(window.width));
      expect(shut.height, lessThan(window.height));
      expect(
        window.bottom - shut.bottom,
        OverlayLayout.compactDockPanelHeight,
        reason: 'the status bar',
      );

      // Opening a dock takes its height from the game as well, rather than
      // standing over it.
      dock().open('test.waves');
      await tester.pump();
      await tester.pump();
      final open = canvas();
      expect(open.height, lessThan(shut.height));
      expect(shut.height - open.height, 240);
      expect(open.width, shut.width, reason: 'nothing changed sideways');

      // The panel stands in the room the game gave up, not on top of it.
      final panel = tester.getRect(find.byType(DockPanel));
      expect(panel.top, greaterThanOrEqualTo(open.bottom - 1));

      // Which is the point of laying it out rather than painting over it:
      // the canvas is smaller, so the camera's viewport is too.
      expect(plugin.viewport.canvasSize.height, closeTo(open.height, 1));

      dock().close();
      await tester.pump();
      await tester.pump();
      expect(canvas().height, shut.height, reason: 'and it comes back');
      await done(tester);
    });

    testWidgets('the docks are there in the Level Designer, and it makes '
        'room for them', (tester) async {
      if (!kDebugMode) return;
      await pump(tester);
      plugin.sceneState.openScene(Scene(name: 'level'), const {});
      plugin.openLevelDesigner();
      await tester.pump();
      await tester.pump();
      final session = plugin.designer.value!;
      expect(
        find.textContaining(' fps · '),
        findsOneWidget,
        reason: 'the status bar is there',
      );
      // The game is laid out in what the chrome leaves, so opening a panel
      // makes the canvas itself shorter rather than covering it.
      double canvasHeight() =>
          tester.getRect(find.byType(GameCanvasArea)).height;
      final collapsed = canvasHeight();
      expect(
        session.controller.viewportInsets,
        EdgeInsets.zero,
        reason: 'the canvas is the visible area; nothing is inset twice',
      );

      dock().open('test.waves');
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('WAVES BODY'), findsOneWidget);
      expect(
        collapsed - canvasHeight(),
        240,
        reason: 'the level is not hidden behind the panel',
      );
      plugin.closeLevelDesigner();
      await done(tester);
    });
  });
}
