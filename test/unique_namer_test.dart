import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/core/state/unique_namer.dart';

void main() {
  test('a batch named before any of it exists gets distinct names', () {
    // What a paint stroke or a multi-entity duplicate does: name everything,
    // then create everything. Checking only the world handed out one name.
    final world = <String>{'Platform_0'};
    final name = UniqueNamer(() => world);
    final batch = [for (var i = 0; i < 3; i++) name('Platform')];
    expect(batch.toSet(), hasLength(3));
    expect(batch, isNot(contains('Platform_0')));
  });

  test('an undone entity\'s name is not reused, so its redo cannot clash', () {
    final world = <String>{};
    final name = UniqueNamer(() => world);
    final first = name('Coin'); // created, then undone: gone from the world
    final second = name('Coin');
    expect(second, isNot(first));
  });
}
