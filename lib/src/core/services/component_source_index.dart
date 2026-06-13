import 'dart:convert';

class DiscoveredComponentSource {
  const DiscoveredComponentSource({
    required this.typeName,
    required this.sourcePath,
    required this.displayName,
    required this.group,
    required this.description,
    required this.isEditorComponent,
  });

  final String typeName;
  final String sourcePath;
  final String displayName;
  final String group;
  final String description;
  final bool isEditorComponent;
}

class ComponentSourceIndex {
  ComponentSourceIndex._();

  static final ComponentSourceIndex instance = ComponentSourceIndex._();

  final Map<String, String> _sourcePathByType = <String, String>{};
  final Map<String, DiscoveredComponentSource> _discoveredByType =
      <String, DiscoveredComponentSource>{};

  void clear() {
    _sourcePathByType.clear();
    _discoveredByType.clear();
  }

  String? sourcePathForType(String typeName) => _sourcePathByType[typeName];

  Iterable<DiscoveredComponentSource> get discoveredComponents =>
      _discoveredByType.values;

  void updateFromScanJson(String output) {
    final decoded = _decodeScanPayload(output);
    if (decoded == null) {
      return;
    }
    final classesRaw = decoded['classes'];
    if (classesRaw is! List) {
      return;
    }

    clear();
    for (final raw in classesRaw) {
      if (raw is! Map) {
        continue;
      }
      final name = raw['name'] as String?;
      final path = raw['path'] as String?;
      if (name == null || path == null || name.isEmpty || path.isEmpty) {
        continue;
      }
      _sourcePathByType[name] = path;

      final scope = raw['scope'] as String?;
      final annotations = raw['annotations'];
      final customAnnotation = _findCustomAnnotation(annotations);
      final namedArgs =
          (customAnnotation?['namedArguments'] as Map?)
              ?.cast<String, dynamic>() ??
          const <String, dynamic>{};

      final displayName = namedArgs['name'] as String?;
      final group = namedArgs['group'] as String?;
      final description = namedArgs['description'] as String?;

      _discoveredByType[name] = DiscoveredComponentSource(
        typeName: name,
        sourcePath: path,
        displayName: (displayName == null || displayName.isEmpty)
            ? name
            : displayName,
        group: (group == null || group.isEmpty) ? 'Custom' : group,
        description: (description == null || description.isEmpty)
            ? 'Custom component.'
            : description,
        isEditorComponent: scope == 'editorComponents',
      );
    }
  }

  Map<String, dynamic>? _decodeScanPayload(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final direct = _tryDecodeMap(trimmed);
    if (direct != null) {
      return direct;
    }

    final objectStart = trimmed.indexOf('{');
    if (objectStart == -1) {
      return null;
    }

    final candidate = trimmed.substring(objectStart);
    final fromStart = _tryDecodeMap(candidate);
    if (fromStart != null) {
      return fromStart;
    }

    final extracted = _extractFirstJsonObject(candidate);
    if (extracted == null) {
      return null;
    }
    return _tryDecodeMap(extracted);
  }

  Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? _extractFirstJsonObject(String input) {
    var depth = 0;
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < input.length; i++) {
      final char = input[i];

      if (inString) {
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == r'\\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        depth++;
        continue;
      }
      if (char == '}') {
        depth--;
        if (depth == 0) {
          return input.substring(0, i + 1);
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _findCustomAnnotation(dynamic annotationsRaw) {
    if (annotationsRaw is! List) {
      return null;
    }
    for (final raw in annotationsRaw) {
      if (raw is! Map) {
        continue;
      }
      final annotation = raw.cast<String, dynamic>();
      final annotationName = annotation['name'];
      if (annotationName == 'ECSComponent' ||
          annotationName == 'Component' ||
          annotationName == 'CustomComponent') {
        return annotation;
      }
    }
    return null;
  }
}
