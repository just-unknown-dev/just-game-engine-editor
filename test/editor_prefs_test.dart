// A module's preference is a typed key in the same store the editor always
// used, and its settings section gets a page of its own in the settings
// dialog, under a Modules caption that only exists when someone contributed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_editor_core/host.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/settings_dialog.dart';
import 'package:just_storage/just_storage.dart';

/// The store, in memory: what the real one does, minus the disk.
class _MemoryStore extends OverlaySettingsStore {
  _MemoryStore() : super(Completer<JustStandardStorage>().future);
  final Map<String, String> values = {};
  OverlayUiSettings saved = const OverlayUiSettings.defaults();

  @override
  Future<OverlayUiSettings> loadSettings() async => saved;
  @override
  Future<void> saveSettings(OverlayUiSettings settings) async =>
      saved = settings;
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> writeRaw(String key, String value) async => values[key] = value;
  @override
  Future<int> readIntByKey(String key, {required int fallback}) async =>
      int.tryParse(values[key] ?? '') ?? fallback;
  @override
  Future<void> writeIntByKey(String key, int value) async =>
      values[key] = '$value';
  @override
  Future<bool> readBoolByKey(String key, {required bool fallback}) async =>
      values.containsKey(key) ? values[key] == 'true' : fallback;
  @override
  Future<void> writeBoolByKey(String key, bool value) async =>
      values[key] = '$value';
}

class _WavesModule extends EditorModule {
  static final showWaves = SettingPref.boolean('test.showWaves', false);
  @override
  String get id => 'test.waves';
  @override
  String get name => 'Waves';
  @override
  List<SettingsSection> get settingsSections => [
    SettingsSection(
      id: 'test.waves',
      title: 'Waves',
      build: (context, prefs) => ValueListenableBuilder<bool>(
        valueListenable: prefs.watch(showWaves),
        builder: (context, on, _) => Text('WAVES ${on ? 'ON' : 'OFF'}'),
      ),
    ),
  ];
}

void main() {
  test('a module preference round-trips through the store', () async {
    final store = _MemoryStore()..values['test.showWaves'] = 'true';
    final scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: World()..initialize(),
      settingsStore: store,
    );
    addTearDown(scope.dispose);
    final prefs = scope.prefs;
    final pref = _WavesModule.showWaves;

    expect(prefs.get(pref), isFalse, reason: 'default before load');
    await prefs.load();
    expect(prefs.get(pref), isTrue, reason: 'stored value after load');

    var notified = 0;
    prefs.watch(pref).addListener(() => notified++);
    await prefs.set(pref, false);
    expect(prefs.get(pref), isFalse);
    expect(store.values['test.showWaves'], 'false');
    expect(notified, 1);

    await prefs.update(prefs.settings.value.copyWith(gridSize: 48));
    expect(store.saved.gridSize, 48);
  });

  test('settings compare by value, and read their density', () {
    const d = OverlayUiSettings.defaults();
    expect(d.copyWith(), d);
    expect(d.copyWith(gridSize: 48), isNot(d));
    expect(d.copyWith(compactness: 0.83).density, OverlayDensity.compact);
    expect(d.density, OverlayDensity.standard);
  });

  Widget host(EditorScope scope) => MaterialApp(
    home: Scaffold(
      body: EditorScopeProvider(
        scope: scope,
        child: EditorSettingsDialog(scope: scope, onClose: () {}),
      ),
    ),
  );

  EditorScope scopeWith({List<EditorModule> modules = const []}) {
    final scope = EditorScope(
      builtIns: const [BuiltInEditorModule.new],
      world: World()..initialize(),
      modules: modules,
      settingsStore: _MemoryStore(),
    );
    addTearDown(scope.dispose);
    return scope;
  }

  testWidgets("a module's settings section gets a page under Modules", (
    tester,
  ) async {
    final scope = scopeWith(modules: [_WavesModule()]);
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();
    expect(find.text('MODULES'), findsOneWidget);
    await tester.tap(find.text('Waves'));
    await tester.pumpAndSettle();
    expect(find.text('WAVES OFF'), findsOneWidget);
  });

  testWidgets('with no modules there is no Modules caption', (tester) async {
    final scope = scopeWith();
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();
    expect(find.text('MODULES'), findsNothing);
    // In the list on the left, and as the open page's title.
    expect(find.text('Appearance'), findsNWidgets(2));
  });

  testWidgets('a change saves, and marks the setting and its page', (
    tester,
  ) async {
    final scope = scopeWith();
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to the default'), findsNothing);

    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.compactness, 0.85);
    expect(
      (scope.prefs.store as _MemoryStore).saved.compactness,
      0.85,
      reason: 'kept for next time',
    );
    expect(find.byTooltip('Back to the default'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to the default'));
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.compactness, 1.0);
  });

  testWidgets('search finds settings on every page', (tester) async {
    final scope = scopeWith();
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();
    expect(find.text('Grid size'), findsNothing, reason: 'another page');

    await tester.enterText(find.byType(TextField).first, 'grid');
    await tester.pumpAndSettle();
    expect(find.text('Grid size'), findsOneWidget);
    expect(find.text('Show grid'), findsOneWidget);
    expect(find.text('Corner radius'), findsNothing);
  });

  testWidgets('reset all asks first', (tester) async {
    final scope = scopeWith();
    await scope.prefs.update(
      scope.prefs.settings.value.copyWith(gridSize: 64, showGrid: false),
    );
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reset all…'));
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value.gridSize, 64, reason: 'not yet');
    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();
    expect(scope.prefs.settings.value, const OverlayUiSettings.defaults());
  });
}
