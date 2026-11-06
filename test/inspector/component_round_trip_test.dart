// Every placement in the Level Designer round-trips its components through
// JSON — CreateEntitiesCommand has to rebuild them from scratch after an undo
// has destroyed the originals.
//
// A field missing from a component's editor descriptor is silently dropped by
// that round trip and comes back as the constructor default. Nothing throws;
// the entity is simply not what was drawn. That is how camera zones ended up
// ignoring their drag and appearing at a fixed size and position.
//
// So: author each component with values that differ from every default, send
// it through the round trip, and check what comes back.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

/// Sends [component] through the same encode/decode the designer uses.
final _scope = EditorScope(
  builtIns: const [BuiltInEditorModule.new],
  world: World()..initialize(),
);

T roundTrip<T extends Component>(T component) {
  final json = _scope.codec.encode(component);
  expect(json, isNotNull, reason: '${component.runtimeType} did not encode');
  final restored = _scope.codec.decode(json!);
  expect(restored, isA<T>(), reason: '${component.runtimeType} did not decode');
  return restored! as T;
}

void main() {
  test('LayerComponent keeps every authored field', () {
    final restored = roundTrip(
      LayerComponent(layerId: 'foreground', layer: 100, zOrder: 7),
    );

    expect(restored.layerId, 'foreground');
    expect(restored.layer, 100);
    expect(restored.zOrder, 7);
  });
}
