// Authoring the interface: the rows that edit it, the menu that makes it,
// and the checks that say what is wrong with it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/core/state/play_snapshot.dart';
import 'package:just_game_engine_editor/src/core/validation/scene_validator.dart';
import 'package:just_game_engine_editor/src/ui/inspector/field_style.dart';
import 'package:just_game_engine_editor/src/ui/inspector/ui_field_editors.dart';

import 'support/test_scope.dart';

void main() {
  setUpAll(registerCoreCodecs);
  setUp(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
  });
  tearDown(() {
    UiBindings.clear();
    UiActions.clear();
    UiWidgets.clear();
  });

  /// One row on its own, at inspector width.
  Future<void> pumpRow(WidgetTester tester, Widget row) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(8), child: row),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('the anchor grid', () {
    testWidgets('a preset sets both corners', (tester) async {
      UiAnchor? chosen;
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.topLeft,
          onChanged: (a) => chosen = a,
        ),
      );

      // Open it, then pick the bottom-right cell.
      await tester.tap(find.text('Anchor'));
      await tester.pump();
      await tester.tap(find.byTooltip('bottomRight'));
      await tester.pump();

      expect(chosen, UiAnchor.bottomRight);
      expect(chosen!.min, const Offset(1, 1));
      expect(chosen!.max, const Offset(1, 1));
    });

    testWidgets('a stretch is one of the choices', (tester) async {
      UiAnchor? chosen;
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.topLeft,
          onChanged: (a) => chosen = a,
        ),
      );
      await tester.tap(find.text('Anchor'));
      await tester.pump();

      await tester.tap(find.text('The whole parent'));
      await tester.pump();

      expect(chosen, UiAnchor.stretch);
      expect(chosen!.stretchesX, isTrue);
      expect(chosen!.stretchesY, isTrue);
    });

    testWidgets('the row says which preset it is on', (tester) async {
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.centerRight,
          onChanged: (_) {},
        ),
      );

      expect(find.text('centerRight'), findsOneWidget);
    });

    testWidgets('an anchor off every preset reads as custom', (tester) async {
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: const UiAnchor(Offset(0.3, 0.7), Offset(0.3, 0.7)),
          onChanged: (_) {},
        ),
      );

      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('the row does not overflow at inspector width', (tester) async {
      await pumpRow(
        tester,
        UiAnchorEditorRow(
          label: 'Anchor',
          anchor: UiAnchor.stretch,
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.text('Anchor'));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('the text row', () {
    testWidgets('a tag button writes the markup at the caret', (tester) async {
      var written = '';
      await pumpRow(
        tester,
        UiTextEditorRow(
          label: 'Text',
          value: 'Go',
          onChanged: (v) => written = v,
        ),
      );
      await tester.tap(find.text('Text'));
      await tester.pump();

      await tester.tap(find.text('B'));
      await tester.pump();

      expect(written, 'Go[b][/b]');
    });

    testWidgets('what the game reads is offered, and the rest is flagged', (
      tester,
    ) async {
      var written = '';
      await pumpRow(
        tester,
        UiTextEditorRow(
          label: 'Text',
          value: 'Coins: {gems}',
          bindings: const ['coins', 'time'],
          onChanged: (v) => written = v,
        ),
      );

      expect(
        find.textContaining('Nothing in the game reads {gems}'),
        findsOneWidget,
      );

      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.tap(find.text('{coins}'));
      await tester.pump();

      expect(written, contains('{coins}'));
    });

    testWidgets('a text beginning @ says it is a key', (tester) async {
      await pumpRow(
        tester,
        UiTextEditorRow(label: 'Text', value: '@hud.coins', onChanged: (_) {}),
      );

      expect(find.textContaining('hud.coins'), findsWidgets);
      expect(find.textContaining('current language'), findsOneWidget);
    });

    testWidgets('a label column as wide as every other row', (tester) async {
      await pumpRow(
        tester,
        UiTextEditorRow(label: 'Text', value: 'Hi', onChanged: (_) {}),
      );

      final field = tester.getRect(find.byType(TextField));
      expect(field.left, closeTo(8 + InspectorField.labelWidth, 1));
    });
  });

  group('the inspector over a screen', () {
    testWidgets('a slot shows its anchor as a grid', (tester) async {
      final scope = testScope();
      final entity = scope.world.createEntityWithComponents([
        UiSlotComponent(mode: UiSlotMode.anchored),
      ], name: 'Badge');
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(UiAnchorEditorRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom widget offers the properties it said it takes', (
      tester,
    ) async {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'inventory_grid',
          label: 'Inventory',
          props: const [
            UiWidgetProp(
              'columns',
              'Columns',
              UiPropKind.number,
              defaultValue: '4',
            ),
            UiWidgetProp('title', 'Title', UiPropKind.text),
          ],
          build: (context) => const SizedBox.shrink(),
        ),
      );
      final scope = testScope();
      final entity = scope.world.createEntityWithComponents([
        UiCustomComponent(widgetId: 'inventory_grid'),
      ], name: 'Bag');
      tester.view.physicalSize = const Size(360, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      // And the widget itself is chosen from what was registered.
      expect(find.text('inventory_grid'), findsWidgets);
    });
  });

  group('Create UI', () {
    late EditorScope scope;
    late EntityOps ops;

    setUp(() {
      scope = testScope();
      ops = EntityOps(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: Camera.new,
      );
      scope.sceneState.openScene(Scene(name: 'level_test'), const {});
    });

    test('a text made with no canvas gets one', () {
      final text = ops.createUi('text');

      expect(text, isNotNull);
      final canvases = scope.world.query([UiCanvasComponent]).toList();
      expect(canvases.length, 1);
      final parentId = text!.getComponent<ParentComponent>()?.parentId;
      expect(parentId, canvases.single.id);
      expect(
        canvases.single.getComponent<ChildrenComponent>()!.childIds,
        contains(text.id),
      );
    });

    test('what is selected is what the next thing goes under', () {
      final canvas = ops.createUi('canvas')!;
      final row = ops.createUi('row')!;
      // Creating selects, so the button lands in the row.
      final button = ops.createUi('button')!;

      expect(row.getComponent<ParentComponent>()!.parentId, canvas.id);
      expect(button.getComponent<ParentComponent>()!.parentId, row.id);
      expect(
        row.getComponent<ChildrenComponent>()!.childIds,
        contains(button.id),
      );
    });

    test('a screen is made closed, modal and ready to open', () {
      final screen = ops.createUi('screen')!;
      final canvas = screen.getComponent<UiCanvasComponent>()!;

      expect(canvas.isScreen, isTrue);
      expect(canvas.visible, isFalse);
      expect(canvas.modal, isTrue);
    });

    test('every kind in the menu makes something', () {
      for (final option in UiCreateOptions.builtIns) {
        final made = ops.createUi(option.id);
        expect(made, isNotNull, reason: option.id);
        expect(
          made!.components,
          isNotEmpty,
          reason: '${option.id} made an empty entity',
        );
      }
    });

    test("the menu offers the game's own widgets", () {
      expect(
        UiCreateOptions.all.map((o) => o.id),
        isNot(contains('custom:inventory_grid')),
      );

      UiWidgets.register(
        UiWidgetDefinition(
          id: 'inventory_grid',
          label: 'Inventory',
          build: (context) => const SizedBox.shrink(),
        ),
      );

      final option = UiCreateOptions.all.firstWhere(
        (o) => o.id == 'custom:inventory_grid',
      );
      expect(option.label, 'Inventory');

      final made = ops.createUi(option.id)!;
      expect(
        made.getComponent<UiCustomComponent>()!.widgetId,
        'inventory_grid',
      );
    });

    test('names do not collide', () {
      final first = ops.createUi('text')!;
      final second = ops.createUi('text')!;

      expect(first.name, isNot(second.name));
    });
  });

  group('what the checks say', () {
    late EditorScope scope;

    setUp(() => scope = testScope());

    List<SceneProblem> problems() => BuiltInValidators.run(
      ValidationContext(scope: scope, fileExists: (_) => true),
      const [BuiltInValidators.uiScreens],
    );

    Entity canvas({bool screen = false, String initialFocus = ''}) =>
        scope.world.createEntityWithComponents([
          UiCanvasComponent(isScreen: screen, initialFocus: initialFocus),
          ChildrenComponent(),
        ], name: screen ? 'Pause' : 'Hud');

    Entity under(Entity parent, List<Component> components, String name) {
      final child = scope.world.createEntityWithComponents([
        ...components,
        ParentComponent(parentId: parent.id),
      ], name: name);
      parent.getComponent<ChildrenComponent>()!.addChild(child.id);
      return child;
    }

    test('an action that is not an action', () {
      final hud = canvas();
      under(hud, [
        ButtonComponent(
          label: 'Go',
          onPressed: const UiActionList([UiAction('scene.lod', 'level_02')]),
        ),
      ], 'Go');

      expect(
        problems().map((p) => p.message),
        contains(contains('"scene.lod", which is not an action')),
      );
    });

    test('a custom action the game does not register', () {
      UiActions.register('cheer', (_) {});
      final hud = canvas();
      under(hud, [
        ButtonComponent(
          label: 'Go',
          onPressed: const UiActionList([UiAction('custom:explode')]),
        ),
      ], 'Go');

      expect(
        problems().map((p) => p.message),
        contains(contains('custom:explode')),
      );
    });

    test('nothing is said about custom actions when nothing is registered', () {
      final hud = canvas();
      under(hud, [
        ButtonComponent(
          label: 'Go',
          onPressed: const UiActionList([UiAction('custom:explode')]),
        ),
      ], 'Go');

      // The game is not running: an empty registry means "cannot tell".
      expect(
        problems().map((p) => p.message),
        isNot(contains(contains('custom:explode'))),
      );
    });

    test('a button nothing happens with', () {
      final hud = canvas();
      under(hud, [ButtonComponent(label: 'Go')], 'Go');

      expect(
        problems().map((p) => p.message),
        contains(contains('nothing happens when it is')),
      );
    });

    test('interface outside any canvas', () {
      scope.world.createEntityWithComponents([
        TextComponent(text: 'Lost'),
        UiSlotComponent(),
      ], name: 'Lost');

      final found = problems();
      expect(
        found.map((p) => p.message),
        contains(contains('sits under no UI Canvas')),
      );
      expect(found.first.severity, ProblemSeverity.error);
    });

    test('a screen nobody can use without a pointer', () {
      final pause = canvas(screen: true);
      under(pause, [TextComponent(text: 'Paused')], 'Title');

      expect(
        problems().map((p) => p.message),
        contains(contains('nothing to focus')),
      );
    });

    test('a screen that does not say what takes focus', () {
      final pause = canvas(screen: true);
      under(pause, [
        ButtonComponent(
          label: 'Resume',
          onPressed: const UiActionList([UiAction('ui.back')]),
        ),
      ], 'Resume');

      expect(
        problems().map((p) => p.message),
        contains(contains('does not say what takes focus')),
      );
    });

    test('a screen focusing something that is not under it', () {
      final pause = canvas(screen: true, initialFocus: 'Elsewhere');
      under(pause, [
        ButtonComponent(
          label: 'Resume',
          onPressed: const UiActionList([UiAction('ui.back')]),
        ),
      ], 'Resume');

      expect(
        problems().map((p) => p.message),
        contains(contains('which is not a control under it')),
      );
    });

    test('a screen that is set up right has nothing said about it', () {
      final pause = canvas(screen: true, initialFocus: 'Resume');
      under(pause, [
        ButtonComponent(
          label: 'Resume',
          onPressed: const UiActionList([UiAction('ui.back')]),
        ),
      ], 'Resume');

      expect(problems(), isEmpty);
    });

    test('a text reading something the game does not offer', () {
      UiBindings.register('coins', () => 0);
      final hud = canvas();
      under(hud, [TextComponent(text: '{coins} / {gems}')], 'Counter');

      expect(
        problems().map((p) => p.message),
        contains(contains('reads {gems}')),
      );
    });

    test('a widget the game does not have', () {
      UiWidgets.register(
        UiWidgetDefinition(
          id: 'inventory_grid',
          label: 'Inventory',
          build: (context) => const SizedBox.shrink(),
        ),
      );
      final hud = canvas();
      under(hud, [
        UiCustomComponent(widgetId: 'mini_map'),
        UiSlotComponent(),
      ], 'Map');

      expect(
        problems().map((p) => p.message),
        contains(contains('"mini_map", which this game does not register')),
      );
    });
  });
  group('sibling order', () {
    late EditorScope scope;
    late EntityOps ops;

    setUp(() {
      scope = testScope();
      ops = EntityOps(
        scope: scope,
        world: () => scope.world,
        sceneState: scope.sceneState,
        camera: Camera.new,
      );
      scope.sceneState.openScene(Scene(name: 'level_test'), const {});
    });

    test('a child moves before one of its siblings', () {
      final canvas = ops.createUi('canvas')!;
      final row = ops.createUi('row')!;
      final a = ops.createUi('text', parent: row)!;
      final b = ops.createUi('text', parent: row)!;
      final c = ops.createUi('text', parent: row)!;
      expect(row.getComponent<ChildrenComponent>()!.childIds, [
        a.id,
        b.id,
        c.id,
      ]);

      ops.reorderEntity(c, a, before: true);

      expect(row.getComponent<ChildrenComponent>()!.childIds, [
        c.id,
        a.id,
        b.id,
      ]);
      expect(canvas.getComponent<ChildrenComponent>()!.childIds, [row.id]);
    });

    test('a child dropped next to a stranger joins that parent', () {
      ops.createUi('canvas');
      final row = ops.createUi('row')!;
      final inRow = ops.createUi('text', parent: row)!;
      final column = ops.createUi('column', parent: ops.createUi('canvas'))!;
      final inColumn = ops.createUi('button', parent: column)!;

      ops.reorderEntity(inRow, inColumn, before: false);

      expect(inRow.getComponent<ParentComponent>()!.parentId, column.id);
      expect(column.getComponent<ChildrenComponent>()!.childIds, [
        inColumn.id,
        inRow.id,
      ]);
      expect(
        row.getComponent<ChildrenComponent>()!.childIds,
        isNot(contains(inRow.id)),
      );
    });

    test('an entity at the root has no order to change', () {
      final canvasA = ops.createUi('canvas')!;
      final canvasB = ops.createUi('canvas')!;

      expect(
        () => ops.reorderEntity(canvasB, canvasA, before: true),
        returnsNormally,
      );
    });

    test('the saved order is the order the children are in', () {
      ops.createUi('canvas');
      final row = ops.createUi('row')!;
      final a = ops.createUi('text', parent: row)!;
      final b = ops.createUi('button', parent: row)!;
      ops.reorderEntity(b, a, before: true);

      final saved = scope.codec.encodeEntities(scope.world.entities.toList());
      final names = [for (final e in saved) e['name'] as String?];

      // Parents before children, and the two siblings in their new order.
      expect(names.indexOf(row.name), lessThan(names.indexOf(b.name)));
      expect(names.indexOf(b.name), lessThan(names.indexOf(a.name)));
    });

    test('interface is saved at all, transform or no transform', () {
      ops.createUi('canvas');
      final text = ops.createUi('text')!;

      final saved = scope.codec.encodeEntities(
        PlaySnapshot.authored(scope.world),
      );

      expect([
        for (final e in saved) e['name'] as String?,
      ], contains(text.name));
    });
  });
  group('the role and what it decides', () {
    tearDown(() => UiThemes.evict());

    /// The inspector over a text entity, at inspector width.
    Future<EditorScope> pumpText(
      WidgetTester tester, {
      String role = 'body',
      UiTextStyle style = const UiTextStyle(),
    }) async {
      final scope = testScope();
      final entity = scope.world.createEntityWithComponents([
        TextComponent(text: 'hello', styleRole: role, style: style),
      ], name: 'Label');
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return scope;
    }

    /// The text style row's size box.
    Finder sizeField() => find.descendant(
      of: find.byType(UiTextStyleEditorRow),
      matching: find.byType(TextFormField),
    );

    testWidgets('the role is chosen from the ones a theme carries', (
      tester,
    ) async {
      await pumpText(tester);

      final dropdown = tester.widget<EditorDropdown<String>>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Role'),
                matching: find.byType(DropdownEditorRow),
              ),
              matching: find.byType(EditorDropdown<String>),
            )
            .first,
      );

      expect(dropdown.value, 'body');
      expect(
        dropdown.options.map((o) => o.value),
        containsAll(UiTheme.textRoles),
      );
    });

    testWidgets('a role the theme does not carry is kept, not rewritten', (
      tester,
    ) async {
      await pumpText(tester, role: 'hud.big');

      final dropdown = tester.widget<EditorDropdown<String>>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Role'),
                matching: find.byType(DropdownEditorRow),
              ),
              matching: find.byType(EditorDropdown<String>),
            )
            .first,
      );

      expect(dropdown.value, 'hud.big');
      expect(dropdown.options.map((o) => o.value), contains('hud.big'));
    });

    testWidgets("a style that says nothing shows the role's size", (
      tester,
    ) async {
      await pumpText(tester, role: 'title');

      // The title role is 32 by default, and the box says so without
      // claiming this text chose it.
      final field = tester.widget<TextFormField>(sizeField().first);
      expect(field.initialValue, '32');
      expect(find.text('all from the title role'), findsOneWidget);
      // Nothing to put back, so nothing offers to.
      expect(
        find.descendant(
          of: find.byType(UiTextStyleEditorRow),
          matching: find.byIcon(Icons.settings_backup_restore_rounded),
        ),
        findsNothing,
      );
    });

    testWidgets('a size set here is its own, and can be put back', (
      tester,
    ) async {
      final scope = await pumpText(
        tester,
        role: 'title',
        style: const UiTextStyle(size: 18),
      );
      final text = scope.world
          .findEntityByName('Label')!
          .getComponent<TextComponent>()!;

      expect(
        tester.widget<TextFormField>(sizeField().first).initialValue,
        '18',
      );
      expect(find.text('all from the title role'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(UiTextStyleEditorRow),
          matching: find.byIcon(Icons.settings_backup_restore_rounded),
        ),
      );
      await tester.pump();

      expect(text.style.size, isNull, reason: 'back to the role');
      expect(text.styleUnder(UiThemes.preview).size, 32);
    });

    testWidgets("the row reads the project's theme, not the defaults", (
      tester,
    ) async {
      UiThemes.preview = const UiTheme(
        textStyles: {'title': UiTextStyle(size: 44)},
      );
      addTearDown(() => UiThemes.preview = UiTheme.fallback);

      await pumpText(tester, role: 'title');

      expect(
        tester.widget<TextFormField>(sizeField().first).initialValue,
        '44',
      );
    });

    test('a style keeps saying nothing through a save', () {
      const bare = UiTextStyle();
      final definition = ComponentDefinitionRegistry.instance.definitionByType(
        'TextComponent',
      )!;
      final saved = {
        for (final f in definition.fields)
          f.name: f.encodeFrom(TextComponent(text: 'hi', styleRole: 'title')),
      };
      final loaded = TextComponent(text: '');
      for (final f in definition.fields) {
        f.decodeInto(loaded, saved[f.name]);
      }

      // The point of the whole arrangement: what the role decides is not
      // baked into the entity on the way through a file.
      expect(loaded.style, bare);
      expect(loaded.style.size, isNull);
      expect(loaded.styleRole, 'title');
    });
  });
  group('colour roles', () {
    tearDown(() => UiThemes.evict());

    /// The inspector over one component, at inspector width.
    Future<EditorScope> pumpOver(
      WidgetTester tester,
      List<Component> components,
    ) async {
      final scope = testScope();
      final entity = scope.world.createEntityWithComponents(
        components,
        name: 'Card',
      );
      tester.view.physicalSize = const Size(360, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: buildComponentSections(
                  entity: entity,
                  sceneState: scope.sceneState,
                  scope: scope,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return scope;
    }

    EditorDropdown<String> dropdownFor(WidgetTester tester, String label) =>
        tester.widget<EditorDropdown<String>>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.text(label),
                  matching: find.byType(DropdownEditorRow),
                ),
                matching: find.byType(EditorDropdown<String>),
              )
              .first,
        );

    ColorEditorRow colorRowFor(WidgetTester tester, String label) =>
        tester.widget<ColorEditorRow>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(ColorEditorRow),
              )
              .first,
        );

    testWidgets('the role is chosen from the palette', (tester) async {
      await pumpOver(tester, [UiPanelComponent()]);

      final dropdown = dropdownFor(tester, 'Colour role');
      expect(dropdown.value, 'surface');
      expect(
        dropdown.options.map((o) => o.value),
        containsAll(UiPalette.roles),
      );
    });

    testWidgets('a colour of its own wins, and can be put back', (
      tester,
    ) async {
      final panel = UiPanelComponent(color: const Color(0xFF223344));
      await pumpOver(tester, [panel]);

      final row = colorRowFor(tester, 'Colour');
      expect(row.inherited, isFalse);
      expect(row.paintStyle.color, const Color(0xFF223344));
      expect(row.onClear, isNotNull);

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Colour'),
            matching: find.byType(ColorEditorRow),
          ),
          matching: find.byIcon(Icons.settings_backup_restore_rounded),
        ),
      );
      await tester.pump();

      expect(panel.color, isNull, reason: 'back to the role');
    });

    testWidgets('an unset colour shows the role it comes from', (tester) async {
      UiThemes.preview = const UiTheme(
        palette: UiPalette(danger: Color(0xFFAA0000)),
      );
      addTearDown(() => UiThemes.preview = UiTheme.fallback);

      await pumpOver(tester, [UiPanelComponent(colorRole: 'danger')]);

      final row = colorRowFor(tester, 'Colour');
      expect(row.inherited, isTrue);
      expect(row.inheritedFrom, 'danger');
      // The swatch is what will actually be drawn.
      expect(row.paintStyle.color, const Color(0xFFAA0000));
      expect(row.onClear, isNull, reason: 'nothing to put back');
      expect(find.text('danger'), findsWidgets);
    });

    testWidgets('a border with nothing behind it says so', (tester) async {
      await pumpOver(tester, [UiPanelComponent()]);

      final row = colorRowFor(tester, 'Border');
      expect(row.inherited, isTrue);
      expect(row.inheritedFrom, 'outline');
    });

    testWidgets('a tint that is simply not set is not called white', (
      tester,
    ) async {
      await pumpOver(tester, [UiImageComponent()]);

      final row = colorRowFor(tester, 'Tint');
      expect(row.inherited, isTrue);
      expect(row.inheritedFrom, 'not set');
      expect(row.onClear, isNull);
    });

    test('the inspector and the screen agree on what a role means', () {
      const theme = UiTheme(
        palette: UiPalette(
          danger: Color(0xFFAA0000),
          outline: Color(0xFF111111),
        ),
      );

      final panel = UiPanelComponent(colorRole: 'danger');
      expect(panel.colorUnder(theme), const Color(0xFFAA0000));
      expect(panel.borderColorUnder(theme), const Color(0xFF111111));
      // Its own colour wins over the role.
      panel.color = const Color(0xFF00FF00);
      expect(panel.colorUnder(theme), const Color(0xFF00FF00));

      final bar = UiProgressComponent(colorRole: 'danger');
      expect(bar.colorUnder(theme), const Color(0xFFAA0000));
      expect(bar.trackColorUnder(theme), const Color(0xFF111111));
    });
  });
}
