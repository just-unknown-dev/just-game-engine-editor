// What a Level Designer tool can hear besides a left-button drag: the
// pointer hovering, the right button when it asks for it, keys before the
// designer's own commands, and being switched to and from. The tile tools
// are built on these.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';

class _Keys {
  bool shift = false;
  ModifierKeys read() => ModifierKeys(shift: shift);
}

class _Probe extends LevelToolHandler {
  final log = <String>[];
  bool takesRight = true;
  bool takesKeys = true;

  @override
  String get id => 'test.probe';
  @override
  String get label => 'Probe';
  @override
  IconData get icon => Icons.circle;
  @override
  String get group => ToolGroups.tiles;
  @override
  bool get acceptsSecondaryButton => takesRight;

  @override
  bool onPointerDown(ToolContext context) {
    log.add('down ${context.button.name}');
    return true;
  }

  @override
  void onPointerUp(ToolContext context) => log.add('up ${context.button.name}');

  @override
  void onPointerHover(ToolContext context) =>
      log.add('hover ${context.worldPosition.dx.round()}');

  @override
  void onPointerExit() => log.add('exit');

  @override
  bool onKey(LogicalKeyboardKey key, ToolContext context) {
    log.add('key ${key.keyLabel} at ${context.worldPosition.dx.round()}');
    return takesKeys;
  }

  @override
  void onActivate() => log.add('on');

  @override
  void onDeactivate() => log.add('off');
}

void main() {
  late World world;
  late _Keys keys;
  late LevelDesignerSession session;
  late _Probe probe;

  setUp(() {
    world = World()..initialize();
    keys = _Keys();
    session = LevelDesignerSession(
      scope: testScope(world: world),
      uniqueName: (p) => p,
      onDuplicate: () {},
      onDelete: () {},
      onArray: (_, _) {},
      readModifiers: keys.read,
    );
    addTearDown(session.dispose);
    probe = _Probe();
    session.tools.register(probe);
    session.setTool(probe.id);
  });

  test('switching tools tells both of them', () {
    expect(probe.log, ['on']);
    session.setTool(BuiltInTools.select);
    expect(probe.log, ['on', 'off']);
  });

  test('hovering reaches the tool, with where the pointer is', () {
    session.onPointerHover(const Offset(40, 0), 32);
    session.onPointerExit();
    expect(probe.log.skip(1), ['hover 40', 'exit']);
  });

  test('a right-button press is the tool\'s when it asks for it', () {
    expect(session.claimsSecondary(), isTrue);
    expect(
      session.onPointerDown(Offset.zero, 32, button: ToolButton.secondary),
      isTrue,
    );
    session.onPointerUp(Offset.zero, 32);
    expect(probe.log.skip(1), ['down secondary', 'up secondary']);
  });

  test('…and the context menu\'s when it does not, or with Shift held', () {
    probe.takesRight = false;
    expect(session.claimsSecondary(), isFalse);
    expect(
      session.onPointerDown(Offset.zero, 32, button: ToolButton.secondary),
      isFalse,
    );
    probe.takesRight = true;
    keys.shift = true;
    expect(session.claimsSecondary(), isFalse);
  });

  test('keys reach the tool before the designer\'s commands', () {
    // V would switch to the select tool; the tool takes it first.
    session.onPointerHover(const Offset(64, 0), 32);

    expect(session.handleKey(LogicalKeyboardKey.keyV, gridSize: 32), isTrue);
    expect(probe.log.last, 'key V at 64');
    expect(session.controller.toolId.value, probe.id);

    // A key the tool lets go of carries on to the designer.
    probe.takesKeys = false;
    session.handleKey(LogicalKeyboardKey.keyV, gridSize: 32);
    expect(session.controller.toolId.value, BuiltInTools.select);
  });

  group('the viewport', () {
    late ViewportInput input;
    setUp(() {
      input = ViewportInput(
        world: () => world,
        sceneState: session.sceneState,
        camera: () => session.camera,
        designer: () => session,
        gridSize: () => 32,
        isActive: () => true,
        isAuthoring: () => true,
      )..updateCanvasSize(const Size(400, 300));
    });

    test('says a right-press was taken, so no menu opens', () {
      final claimed = input.onPointerDown(
        const PointerDownEvent(
          buttons: kSecondaryButton,
          position: Offset(10, 10),
        ),
      );
      expect(claimed, isTrue);
      expect(probe.log.last, 'down secondary');
    });

    test('says a right-press was not taken when the tool does not want it', () {
      probe.takesRight = false;
      final claimed = input.onPointerDown(
        const PointerDownEvent(
          buttons: kSecondaryButton,
          position: Offset(10, 10),
        ),
      );
      expect(claimed, isFalse);
    });

    test('passes hovering on, but not in the middle of a drag', () {
      input.onPointerHover(const PointerHoverEvent(position: Offset(200, 150)));
      expect(probe.log.last, startsWith('hover'));
      input.onPointerDown(
        const PointerDownEvent(
          buttons: kPrimaryButton,
          position: Offset(200, 150),
        ),
      );
      final before = probe.log.length;
      input.onPointerHover(const PointerHoverEvent(position: Offset(210, 150)));
      expect(probe.log.length, before);
    });
  });

  testWidgets('the tool strip captions each group, in order, and marks '
      'every key', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 1200, child: ToolPalette(session: session)),
        ),
      ),
    );
    final captions = tester
        .widgetList<ToolGroupCaption>(find.byType(ToolGroupCaption))
        .map((c) => c.label)
        .toList();
    expect(captions, ['SELECT', 'SHAPES', 'TILES', 'MEASURE']);
    // Group by group, top to bottom.
    double top(String label) => tester
        .getTopLeft(
          find.byWidgetPredicate(
            (w) => w is ToolGroupCaption && w.label == label,
          ),
        )
        .dy;
    expect(top('SELECT'), lessThan(top('SHAPES')));
    expect(top('SHAPES'), lessThan(top('TILES')));
    expect(top('TILES'), lessThan(top('MEASURE')));

    for (final key in ['V', 'B', 'P', 'I', 'S', 'G', 'T', 'D', 'W', 'M']) {
      expect(find.text(key), findsOneWidget, reason: 'the $key badge');
    }
    final active = tester
        .widgetList<ToolStripButton>(find.byType(ToolStripButton))
        .where((b) => b.isActive);
    expect(active.single.icon, probe.icon, reason: 'the tool in hand');
  });

  test('no two tools look alike', () {
    final icons = [for (final t in session.tools.all) t.icon]
      ..remove(probe.icon);
    expect(icons.toSet(), hasLength(icons.length));
  });

  test('tools sort by group first, and a module can add a group', () {
    final groups = [for (final t in session.tools.all) t.group];
    // Each group's tools are together.
    final seen = <String>[];
    for (final g in groups) {
      if (seen.isEmpty || seen.last != g) seen.add(g);
    }
    expect(seen, [
      ToolGroups.select,
      ToolGroups.shapes,
      ToolGroups.tiles,
      ToolGroups.measure,
    ]);

    session.tools
      ..registerGroup(const ToolGroup(id: 'wiring', label: 'WIRING', order: 5))
      ..register(_Grouped('wiring'));
    expect(session.tools.grouped.map((g) => g.$1.label), [
      'SELECT',
      'WIRING',
      'SHAPES',
      'TILES',
      'MEASURE',
    ]);
    // A group nobody registered is captioned with its id, before MEASURE.
    session.tools.register(_Grouped('misc'));
    expect(session.tools.grouped.map((g) => g.$1.label), contains('MISC'));
    expect(session.tools.grouped.last.$1.id, ToolGroups.measure);
  });
}

class _Grouped extends LevelToolHandler {
  _Grouped(this.group);

  @override
  final String group;

  @override
  String get id => 'test.$group';
  @override
  String get label => group;
  @override
  IconData get icon => Icons.cable;
}
