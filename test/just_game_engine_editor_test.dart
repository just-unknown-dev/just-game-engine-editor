import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';

import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('plugin defaults to hidden editor state', () {
    Engine.resetInstance();
    final plugin = JustGameEditorPlugin(engine: Engine());

    expect(plugin.isVisible, isFalse);

    plugin.dispose();
    Engine.resetInstance();
  });

  test('plugin toggles editor visibility', () {
    Engine.resetInstance();
    final plugin = JustGameEditorPlugin(engine: Engine());

    plugin.toggleVisibility();
    expect(plugin.isVisible, isTrue);

    plugin.toggleVisibility();
    expect(plugin.isVisible, isFalse);

    plugin.dispose();
    Engine.resetInstance();
  });

  test(
    'serialization service returns non-blocking draft payload shape',
    () async {
      const service = EditorSerializationService();

      final result = await service.saveDraft(
        const EditorSerializationRequest(
          levelId: 'level_runtime_01',
          ecsSnapshot: <String, dynamic>{
            'entities': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'e_player',
                'components': <String>['Transform', 'Velocity'],
              },
            ],
          },
        ),
      );

      expect(result.jsonDraft, contains('level_runtime_01'));
      expect(result.todos, isNotEmpty);
    },
  );
}
