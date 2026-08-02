import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_debugger/just_debugger.dart';

import 'editor_log_entry.dart';
import 'editor_log_storage.dart';

typedef _PlatformErrorHandler = bool Function(Object error, StackTrace stack);

class EditorLogService extends ChangeNotifier {
  EditorLogService._({EditorLogStorage? storage})
    : _storage = storage ?? createEditorLogStorage();

  static final EditorLogService instance = EditorLogService._();

  @visibleForTesting
  factory EditorLogService.withStorage(EditorLogStorage storage) =>
      EditorLogService._(storage: storage);

  static const int _maxEntries = 1000;

  final EditorLogStorage _storage;
  final List<EditorLogEntry> _entries = <EditorLogEntry>[];

  JustDebuggerController? _controller;
  DebugPrintCallback? _previousDebugPrint;
  FlutterExceptionHandler? _previousFlutterError;
  _PlatformErrorHandler? _previousPlatformError;
  String? _activeConsoleCategory;
  bool _sessionActive = false;
  bool _globalCaptureInstalled = false;
  bool _zoneCaptureInstalled = false;
  bool _keepGlobalCaptureInstalled = false;
  bool _loadedPersistedEntries = false;
  // Set on the first storage write failure (e.g. read-only/full disk) so we
  // stop retrying for the rest of the session. Without this, a failing
  // appendEntry() would otherwise get reported right back through log() ->
  // appendEntry() on every call, spiralling into an ever-growing chain of
  // "failed to persist log" entries that themselves fail to persist.
  bool _storageWriteFailed = false;

  // Deferred notification state — prevents "Build scheduled during frame" when
  // log() is called during Flutter's transient/persistent callback phases
  // (e.g. from an ECS system running on the vsync Ticker).
  bool _flushScheduled = false;
  final List<VoidCallback> _pendingNotifies = [];

  List<EditorLogEntry> get entries =>
      List<EditorLogEntry>.unmodifiable(_entries);

  String? get persistencePath => _storage.filePath;

  // ── Frame-safe notification ────────────────────────────────────────────────

  /// True when the Dart scheduler is in a build/layout/paint or transient
  /// callback phase — i.e. when calling [setState] would throw
  /// "Build scheduled during frame".
  bool get _isInsideFrame {
    try {
      final phase = SchedulerBinding.instance.schedulerPhase;
      return phase != SchedulerPhase.idle &&
          phase != SchedulerPhase.postFrameCallbacks;
    } catch (_) {
      return false;
    }
  }

  /// Runs [work] immediately when safe, or defers it to a single post-frame
  /// callback when called during a Flutter frame (e.g. from an ECS system
  /// running on the vsync Ticker).  Multiple in-frame calls are batched into
  /// one post-frame flush so only a single rebuild is scheduled.
  void _scheduleNotify(VoidCallback work) {
    if (!_isInsideFrame) {
      work();
      return;
    }
    _pendingNotifies.add(work);
    if (!_flushScheduled) {
      _flushScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _flushScheduled = false;
        final pending = List<VoidCallback>.from(_pendingNotifies);
        _pendingNotifies.clear();
        for (final fn in pending) {
          fn();
        }
      });
    }
  }

  Future<T> runWithCapture<T>(Future<T> Function() action) async {
    _keepGlobalCaptureInstalled = true;
    _installGlobalCapture();

    if (_zoneCaptureInstalled) {
      return action();
    }

    _zoneCaptureInstalled = true;
    final completer = Completer<T>();

    await runZonedGuarded(
      () async {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      },
      (Object error, StackTrace stack) {
        _recordUnhandledError(error, stack, source: 'dart', category: 'zone');
        if (!completer.isCompleted) {
          completer.completeError(error, stack);
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          parent.print(zone, line);
          _recordConsoleLine(line, category: _activeConsoleCategory ?? 'print');
        },
      ),
    );

    return completer.future;
  }

  Future<void> startSession({
    required JustDebuggerController controller,
  }) async {
    _controller = controller;

    if (!_loadedPersistedEntries) {
      _loadedPersistedEntries = true;
      final restored = await _storage.loadEntries();
      _entries
        ..clear()
        ..addAll(_mergeEntries(restored, _entries));
      notifyListeners();
    }

    if (_sessionActive) {
      return;
    }
    _sessionActive = true;
    _installGlobalCapture();
    log(
      'Editor log capture session started.',
      source: 'session',
      category: 'lifecycle',
      mirrorToDebugger: false,
    );
  }

  void stopSession() {
    if (!_sessionActive) {
      _controller = null;
      return;
    }
    _sessionActive = false;
    if (!_keepGlobalCaptureInstalled) {
      _restoreGlobalCapture();
    }
    _controller = null;
  }

  void log(
    String message, {
    String source = 'editor',
    String category = 'general',
    DebuggerLogLevel level = DebuggerLogLevel.info,
    String? details,
    bool mirrorToDebugger = true,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return;
    }

    final entry = EditorLogEntry(
      message: normalized,
      source: source,
      category: category,
      level: level,
      timestamp: DateTime.now(),
      details: details,
    );

    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }

    if (!_storageWriteFailed) {
      unawaited(
        _storage.appendEntry(entry).catchError((Object error, StackTrace _) {
          // Flip the flag before logging the notice below — its own log()
          // call must see _storageWriteFailed already true so it doesn't
          // attempt (and fail) another appendEntry itself.
          _storageWriteFailed = true;
          debugPrint(
            '[EditorLogService] Disabling log persistence after a write '
            'failure: $error',
          );
        }),
      );
    }

    _scheduleNotify(() {
      if (mirrorToDebugger) {
        _controller?.log(normalized, category: source, level: level);
      }
      notifyListeners();
    });
  }

  void logProcessChunk(
    String chunk, {
    String source = 'codegen',
    String category = 'process',
  }) {
    for (final rawLine in chunk.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      final lower = line.toLowerCase();
      final level = lower.contains('error')
          ? DebuggerLogLevel.error
          : (lower.contains('warn') || lower.contains('could not find'))
          ? DebuggerLogLevel.warning
          : DebuggerLogLevel.info;
      log(line, source: source, category: category, level: level);
    }
  }

  Future<void> clear() async {
    _entries.clear();
    _scheduleNotify(() {
      _controller?.clearLogs();
      notifyListeners();
    });
    await _storage.clear();
  }

  @visibleForTesting
  void resetForTesting() {
    _controller = null;
    _activeConsoleCategory = null;
    _sessionActive = false;
    _keepGlobalCaptureInstalled = false;
    _zoneCaptureInstalled = false;
    _loadedPersistedEntries = false;
    _entries.clear();
    _restoreGlobalCapture();
  }

  void _installGlobalCapture() {
    if (_globalCaptureInstalled) {
      return;
    }
    _globalCaptureInstalled = true;

    _previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      final normalized = message?.trim();
      if (normalized == null || normalized.isEmpty) {
        _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
        return;
      }

      final previousCategory = _activeConsoleCategory;
      _activeConsoleCategory = 'debugPrint';
      try {
        _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
      } finally {
        _activeConsoleCategory = previousCategory;
      }

      if (!_zoneCaptureInstalled) {
        _recordConsoleLine(normalized, category: 'debugPrint');
      }
    };

    _previousFlutterError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _previousFlutterError?.call(details);
      _recordUnhandledError(
        details.exception,
        details.stack,
        source: 'flutter',
        category: 'framework',
        fallbackMessage: details.exceptionAsString(),
      );
    };

    _previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final handled = _previousPlatformError?.call(error, stack) ?? false;
      _recordUnhandledError(error, stack, source: 'dart', category: 'uncaught');
      return handled;
    };
  }

  void _restoreGlobalCapture() {
    if (!_globalCaptureInstalled) {
      return;
    }
    _globalCaptureInstalled = false;

    if (_previousDebugPrint != null) {
      debugPrint = _previousDebugPrint!;
      _previousDebugPrint = null;
    }
    FlutterError.onError = _previousFlutterError;
    _previousFlutterError = null;
    PlatformDispatcher.instance.onError = _previousPlatformError;
    _previousPlatformError = null;
  }

  void _recordConsoleLine(String line, {required String category}) {
    final normalized = line.trim();
    if (normalized.isEmpty) {
      return;
    }

    log(
      normalized,
      source: 'console',
      category: category,
      mirrorToDebugger: true,
    );
  }

  void _recordUnhandledError(
    Object error,
    StackTrace? stack, {
    required String source,
    required String category,
    String? fallbackMessage,
  }) {
    log(
      fallbackMessage ?? error.toString(),
      source: source,
      category: category,
      level: DebuggerLogLevel.error,
      details: stack?.toString(),
    );
  }

  List<EditorLogEntry> _mergeEntries(
    List<EditorLogEntry> restored,
    List<EditorLogEntry> inMemory,
  ) {
    final merged = <EditorLogEntry>[];
    final seen = <String>{};

    for (final entry in <EditorLogEntry>[...restored, ...inMemory]) {
      if (seen.add(_entryFingerprint(entry))) {
        merged.add(entry);
      }
    }

    if (merged.length <= _maxEntries) {
      return merged;
    }

    return merged.sublist(merged.length - _maxEntries);
  }

  String _entryFingerprint(EditorLogEntry entry) {
    return '${entry.timestamp.toIso8601String()}|${entry.level.name}|${entry.source}|${entry.category}|${entry.message}|${entry.details ?? ''}';
  }
}
