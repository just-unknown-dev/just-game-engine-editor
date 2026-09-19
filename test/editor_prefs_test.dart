// A module's preference is a typed key in the same store the editor always
// used, and its settings section lands on a Modules tab that only exists
// when someone contributed to it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/overlay/settings/overlay_settings_store.dart';
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

  Widget host(EditorScope scope, {List<SettingsSection> sections = const []}) =>
      MaterialApp(
        home: Scaffold(
          body: EditorScopeProvider(
            scope: scope,
            child: EditorSettingsPanel(
              initial: const OverlayUiSettings.defaults(),
              onChanged: (_) {},
              onClose: () {},
              maxHeight: 600,
              prefs: scope.prefs,
              sections: sections,
            ),
          ),
        ),
      );

  testWidgets("a module's settings section appears on a Modules tab", (
    tester,
  ) async {
    final scope = EditorScope(
      world: World()..initialize(),
      modules: [_WavesModule()],
      settingsStore: _MemoryStore(),
    );
    addTearDown(scope.dispose);
    await tester.pumpWidget(host(scope, sections: scope.settingsSections));
    await tester.pumpAndSettle();
    expect(find.text('Modules'), findsOneWidget);
    await tester.tap(find.text('Modules'));
    await tester.pumpAndSettle();
    expect(find.text('WAVES OFF'), findsOneWidget);
  });

  testWidgets('with no modules there is no Modules tab', (tester) async {
    final scope = EditorScope(
      world: World()..initialize(),
      settingsStore: _MemoryStore(),
    );
    addTearDown(scope.dispose);
    await tester.pumpWidget(host(scope));
    await tester.pumpAndSettle();
    expect(find.text('Modules'), findsNothing);
    expect(find.text('Presets'), findsOneWidget);
  });
}
