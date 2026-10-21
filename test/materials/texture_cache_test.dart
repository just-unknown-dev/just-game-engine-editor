// What a material picture keeps of the maps it uploaded: held to a budget,
// the least recently used let go first, never one the same drawing uses;
// a failed upload kept for no one; one asked for twice made once.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/materials/texture_cache.dart';

// A stand-in for a texture: its size in bytes.
final class _Texture {
  _Texture(this.bytes);
  final int bytes;
}

void main() {
  late List<String> loads;
  late TextureCache<String, _Texture> cache;

  setUp(() {
    loads = [];
    cache = TextureCache(budget: 100, sizeOf: (t) => t.bytes);
  });

  Future<_Texture?> get(String key, int bytes, {Set<String> keep = const {}}) =>
      cache.get(key, () async {
        loads.add(key);
        return _Texture(bytes);
      }, keep: keep);

  test('kept until the budget: the least recently used go first', () async {
    await get('a', 40);
    await get('b', 40);
    expect(cache.bytes, 80);
    // Using a makes b the least recently used.
    await get('a', 40);
    expect(loads, ['a', 'b'], reason: 'a was kept, not made again');
    await get('c', 40);
    expect(cache.keys, ['a', 'c'], reason: 'b went to make room');
    expect(cache.bytes, 80);
    await get('b', 40);
    expect(loads, ['a', 'b', 'c', 'b'], reason: 'made again once let go');
  });

  test("a drawing's own maps are kept, whatever they come to", () async {
    final drawing = <String>{};
    for (final key in ['x', 'y', 'z']) {
      drawing.add(key);
      await get(key, 60, keep: drawing);
    }
    expect(cache.keys, ['x', 'y', 'z'], reason: 'over the budget, all kept');
    expect(cache.bytes, 180);
    // The next drawing finds them all.
    for (final key in ['x', 'y', 'z']) {
      await get(key, 60, keep: drawing);
    }
    expect(loads, ['x', 'y', 'z']);
    // Another drawing: the old ones make room for it.
    await get('w', 60);
    expect(cache.keys, ['w']);
    expect(cache.bytes, 60);
  });

  test('asked for twice while being made: made once', () async {
    final gate = Completer<void>();
    var made = 0;
    Future<_Texture?> slow() => cache.get('a', () async {
      made++;
      await gate.future;
      return _Texture(10);
    });
    final first = slow(), second = slow();
    gate.complete();
    expect(await first, same(await second));
    expect(made, 1);
  });

  test('a failed upload keeps nothing; a null one is kept', () async {
    await expectLater(
      cache.get('bad', () async => throw StateError('no file')),
      throwsStateError,
    );
    expect(cache.contains('bad'), isFalse, reason: 'tried again next time');
    expect(await cache.get('none', () async => null), isNull);
    expect(cache.contains('none'), isTrue);
    expect(cache.bytes, 0);
  });

  test('let go by key, and all at once', () async {
    await get('a.png|small', 10);
    await get('a.png|full', 10);
    await get('b.png|full', 10);
    cache.removeWhere((k) => k.startsWith('a.png'));
    expect(cache.keys, ['b.png|full']);
    expect(cache.bytes, 10);
    cache.clear();
    expect(cache.keys, isEmpty);
    expect(cache.bytes, 0);
  });
}
