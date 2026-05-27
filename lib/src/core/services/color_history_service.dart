import 'package:flutter/material.dart';
import 'package:just_database/just_database.dart';

/// Persists recently used editor colors using [JustDatabase].
///
/// Colors are stored as ARGB integers, ordered by most-recently-used.
/// At most [maxColors] entries are kept; adding a duplicate bumps it to front.
class ColorHistoryService {
  static const int maxColors = 16;
  static const String _dbName = 'just_game_editor';
  static const String _table = 'editor_color_history';

  JustDatabase? _db;

  Future<void> _ensureInit() async {
    if (_db != null) return;
    _db = await DatabaseManager.open(_dbName, persist: true);
    await _db!.execute(
      'CREATE TABLE IF NOT EXISTS $_table '
      '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'argb INTEGER NOT NULL UNIQUE, '
      'used_at INTEGER NOT NULL)',
    );
  }

  Future<List<Color>> load() async {
    await _ensureInit();
    final result = await _db!.execute(
      'SELECT argb FROM $_table ORDER BY used_at DESC LIMIT $maxColors',
    );
    return result.rows.map((r) => Color(r['argb'] as int)).toList();
  }

  Future<void> add(Color color) async {
    await _ensureInit();
    final argb = color.toARGB32();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.execute('DELETE FROM $_table WHERE argb = $argb');
    await _db!.execute(
      'INSERT INTO $_table (argb, used_at) VALUES ($argb, $now)',
    );
    // Trim oldest entries beyond the limit.
    await _db!.execute(
      'DELETE FROM $_table WHERE id NOT IN '
      '(SELECT id FROM $_table ORDER BY used_at DESC LIMIT $maxColors)',
    );
  }
}
