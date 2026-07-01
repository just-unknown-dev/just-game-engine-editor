import 'package:flutter/foundation.dart';
import 'package:just_debugger/just_debugger.dart';

@immutable
class EditorLogEntry {
  const EditorLogEntry({
    required this.message,
    required this.source,
    required this.category,
    required this.level,
    required this.timestamp,
    this.details,
  });

  final String message;
  final String source;
  final String category;
  final DebuggerLogLevel level;
  final DateTime timestamp;
  final String? details;

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    'source': source,
    'category': category,
    'level': level.name,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };

  factory EditorLogEntry.fromJson(Map<String, dynamic> json) {
    return EditorLogEntry(
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? 'general',
      category: json['category'] as String? ?? 'general',
      level: _parseLevel(json['level'] as String?),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      details: json['details'] as String?,
    );
  }

  static DebuggerLogLevel _parseLevel(String? raw) {
    return DebuggerLogLevel.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => DebuggerLogLevel.info,
    );
  }
}
