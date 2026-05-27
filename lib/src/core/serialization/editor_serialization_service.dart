import 'dart:convert';

import 'package:flutter/foundation.dart';

class EditorSerializationRequest {
  const EditorSerializationRequest({
    required this.levelId,
    required this.ecsSnapshot,
    this.includeTmxPreview = false,
  });

  final String levelId;
  final Map<String, dynamic> ecsSnapshot;
  final bool includeTmxPreview;

  Map<String, dynamic> toMessage() {
    return <String, dynamic>{
      'levelId': levelId,
      'ecsSnapshot': ecsSnapshot,
      'includeTmxPreview': includeTmxPreview,
    };
  }
}

class EditorSerializationResult {
  const EditorSerializationResult({
    required this.jsonDraft,
    required this.tmxPreview,
    required this.todos,
  });

  final String jsonDraft;
  final String? tmxPreview;
  final List<String> todos;

  factory EditorSerializationResult.fromMessage(Map<String, dynamic> message) {
    return EditorSerializationResult(
      jsonDraft: (message['jsonDraft'] as String?) ?? '{}',
      tmxPreview: message['tmxPreview'] as String?,
      todos: ((message['todos'] as List?) ?? const <Object>[])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class EditorSerializationService {
  const EditorSerializationService();

  Future<EditorSerializationResult> saveDraft(
    EditorSerializationRequest request,
  ) async {
    final resultMessage =
        await compute<Map<String, dynamic>, Map<String, dynamic>>(
          _serializeDraftOnBackground,
          request.toMessage(),
        );
    return EditorSerializationResult.fromMessage(resultMessage);
  }
}

Map<String, dynamic> _serializeDraftOnBackground(Map<String, dynamic> message) {
  final levelId = (message['levelId'] as String?) ?? 'unknown_level';
  final ecsSnapshot =
      (message['ecsSnapshot'] as Map?)?.cast<String, dynamic>() ??
      const <String, dynamic>{};
  final includeTmxPreview = (message['includeTmxPreview'] as bool?) ?? false;

  final nowIso = DateTime.now().toUtc().toIso8601String();
  final draft = <String, dynamic>{
    'schemaVersion': 1,
    'format': 'just_game_engine_editor_draft',
    'levelId': levelId,
    'savedAt': nowIso,
    'ecsSnapshot': ecsSnapshot,
  };

  final todos = <String>[
    'TODO: Map ECS entities/components to TMX layers and object groups.',
    'TODO: Resolve tileset/global tile id references for TMX export.',
    'TODO: Add engine-side round trip validation against LevelBuilder.',
  ];

  return <String, dynamic>{
    'jsonDraft': jsonEncode(draft),
    'tmxPreview': includeTmxPreview ? '<!-- TMX preview TODO -->' : null,
    'todos': todos,
  };
}
