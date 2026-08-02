import 'package:flutter/material.dart';
import 'package:just_database/just_database.dart';

import '../constants/editor_constants.dart';

/// Persists recently used editor colors using [JustDatabase].
///
/// Colors are stored as ARGB integers, ordered by most-recently-used.
/// At most [ColorHistoryConstants.maxColors] entries are kept; adding a
/// duplicate bumps it to front.
class ColorHistoryService {
  JustDatabase? _db;

  Future<void> _ensureInit() async {
    if (_db != null) return;
    _db = await DatabaseManager.open(
      ColorHistoryConstants.dbName,
      persist: true,
    );
    await _db!.execute(
      'CREATE TABLE IF NOT EXISTS ${ColorHistoryConstants.table} '
      '(id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'argb INTEGER NOT NULL UNIQUE, '
      'used_at INTEGER NOT NULL)',
    );
  }

  Future<List<Color>> load() async {
    await _ensureInit();
    final result = await _db!.execute(
      'SELECT argb FROM ${ColorHistoryConstants.table} ORDER BY used_at DESC '
      'LIMIT ${ColorHistoryConstants.maxColors}',
    );
    return result.rows.map((r) => Color(r['argb'] as int)).toList();
  }

  Future<void> add(Color color) async {
    await _ensureInit();
    final argb = color.toARGB32();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db!.execute(
      'DELETE FROM ${ColorHistoryConstants.table} WHERE argb = $argb',
    );
    await _db!.execute(
      'INSERT INTO ${ColorHistoryConstants.table} (argb, used_at) '
      'VALUES ($argb, $now)',
    );
    // Trim oldest entries beyond the limit.
    await _db!.execute(
      'DELETE FROM ${ColorHistoryConstants.table} WHERE id NOT IN '
      '(SELECT id FROM ${ColorHistoryConstants.table} ORDER BY used_at DESC '
      'LIMIT ${ColorHistoryConstants.maxColors})',
    );
  }
}
