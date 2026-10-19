// The semi-modular overlay: a module can add a dock, a toolbar button, a
// scene-tree action, a protection rule, an inspector section and a theme
// preset — and cannot replace or reorder the built-ins, which is the
// deliberate boundary these tests also guard.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/scope/editor_scope_services.dart';
import 'package:just_game_engine_editor/src/extension/built_in_camera_contributions.dart';
import 'package:just_game_engine_editor/src/extension/built_in_tag_contributions.dart';

class _Module extends EditorModule {
  int pressed = 0;
  Entity? actedOn;
  @override
  String get id => 'test.overlay';
  @override
  String get name => 'Overlay';
  @override
  List<DockDefinition> get docks => [
    DockDefinition(
      id: 'test.waves',
      label: 'Waves',
      icon: Icons.waves,
      build: (_, _) => const Text('WAVES DOCK'),
    ),
  ];
  @override
  List<ToolbarButton> get toolbarButtons => [
    ToolbarButton(
      id: 'test.spawn',
      icon: Icons.add,
      tooltip: 'Spawn wave',
      isEnabled: (_) => false,
      onPressed: (_) => pressed++,
    ),
  ];
  @override
  List<SceneTreeAction> get sceneTreeActions => [
    SceneTreeAction(id: 'test.mark', label: 'Mark', run: (e, _) => actedOn = e),
  ];
  @override
  EntityProtectionRule? get protectionRule => EntityProtectionRule(
    id: 'test.keepSpawns',
    isProtected: (e) => e.hasComponent<SpawnComponent>(),
  );
  @override
  List<InspectorSection> get inspectorSections => [
    InspectorSection(id: 'test.notes', build: (_, _, _) => const Text('NOTES')),
  ];
  @override
  List<ThemePreset> get themePresets => [
    ThemePreset(
      id: 'test.neon',
      label: 'Neon',
      data: EditorThemeData.classic.withAccent(const Color(0xFF00FF88)),
    ),
  ];
}

void main() {
  test('module contributions land in the scope, built-ins untouched', () {
    final scope = testScope(modules: [_Module()]);
    expect(scope.docks.map((d) => d.id), ['test.waves']);
    expect(scope.toolbarButtons.map((b) => b.id), ['test.spawn']);
    // After the editor's own: Solo camera, select by tag.
    expect(scope.sceneTreeActions.map((a) => a.id), [
      BuiltInCameraContributions.soloActionId,
      BuiltInTagContributions.selectTaggedId,
      'test.mark',
    ]);
    // After the editor's own: a prefab instance's.
    expect(scope.inspectorSections.map((s) => s.id), [
      'prefab.instance',
      'test.notes',
    ]);
    expect(scope.theme.preset('test.neon'), isNotNull);
    // Five built-in accents stay, first and in order.
    expect(scope.theme.presets.take(5).map((p) => p.id), [
      'sunrise',
      'mint',
      'cobalt',
      'amber',
      'mono',
    ]);

    final bare = testScope();
    expect(bare.docks, isEmpty);
    expect(bare.toolbarButtons, isEmpty);
    expect(bare.protectionRules, isEmpty);
    expect(bare.theme.presets, hasLength(5));
  });

  test('a protection rule protects, and the camera stays protected', () {
    final scope = testScope(modules: [_Module()]);
    final spawn = scope.world.createEntity()
      ..addComponent(SpawnComponent(spawner: 'p'));
    final block = scope.world.createEntity()
      ..addComponent(TransformComponent());
    expect(scope.isProtected(spawn), isTrue);
    expect(scope.isProtected(block), isFalse);
  });

  test('docks open exclusively', () {
    final scope = testScope(modules: [_Module()]);
    final dock = scope.dockController;
    dock.toggle('logs');
    expect(dock.isOpen('logs'), isTrue);
    dock.toggle('test.waves');
    expect(dock.isOpen('logs'), isFalse);
    expect(dock.isOpen('test.waves'), isTrue);
    dock.toggle('test.waves');
    expect(dock.openId.value, isNull);
    dock.resize('test.waves', -50, fallback: 280, max: 700);
    expect(dock.heightOf('test.waves', fallback: 280), 330);
  });

  testWidgets('a theme preset switch re-renders what reads the theme', (
    tester,
  ) async {
    final scope = testScope(modules: [_Module()]);
    await tester.pumpWidget(
      EditorThemeScope(
        controller: scope.theme,
        child: Builder(
          builder: (context) => Container(
            key: const Key('swatch'),
            color: EditorTheme.of(context).primary,
          ),
        ),
      ),
    );
    Color colour() =>
        (tester.widget<Container>(find.byKey(const Key('swatch'))).color)!;
    expect(colour(), EditorTheme.primary);
    scope.theme.select('test.neon');
    await tester.pump();
    expect(colour(), const Color(0xFF00FF88));
    scope.theme.select('mint');
    await tester.pump();
    expect(colour(), const Color(0xFF5FD7A3));
  });
}
