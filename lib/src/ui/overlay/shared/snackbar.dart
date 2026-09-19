import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';

// ── Public types ───────────────────────────────────────────────────────────────

enum EditorSnackBarType { info, success, warning, error }

extension EditorSnackBarTypeX on EditorSnackBarType {
  Color get accentColor => switch (this) {
    EditorSnackBarType.info => const Color(0xFF4A9EFF),
    EditorSnackBarType.success => const Color(0xFF4ADE80),
    EditorSnackBarType.warning => EditorTheme.warning,
    EditorSnackBarType.error => EditorTheme.error,
  };

  IconData get iconData => switch (this) {
    EditorSnackBarType.info => Icons.info_outline_rounded,
    EditorSnackBarType.success => Icons.check_circle_outline_rounded,
    EditorSnackBarType.warning => Icons.warning_amber_rounded,
    EditorSnackBarType.error => Icons.error_outline_rounded,
  };
}

/// A single step update emitted into an [EditorSnackBarEntry.progressStream].
class EditorSnackBarStep {
  const EditorSnackBarStep({required this.message, this.isError = false});

  final String message;
  final bool isError;
}

/// Data object describing a snackbar to show.
///
/// For simple fire-and-forget messages, omit [progressStream] and set [duration].
/// For task-tracking snackbars, provide a [progressStream] — the bar stays
/// indeterminate until the stream closes, then auto-dismisses after ~2 s.
class EditorSnackBarEntry {
  const EditorSnackBarEntry({
    required this.message,
    this.title,
    this.type = EditorSnackBarType.info,
    this.duration = const Duration(seconds: 3),
    this.progressStream,
  });

  final String message;
  final String? title;
  final EditorSnackBarType type;

  /// Auto-dismiss delay for message-only snackbars. Ignored when
  /// [progressStream] is provided.
  final Duration duration;

  /// When non-null the snackbar enters progress mode: the bar is indeterminate
  /// and each emitted [EditorSnackBarStep] is listed in a scrollable step log.
  final Stream<EditorSnackBarStep>? progressStream;
}

// ── Controller ────────────────────────────────────────────────────────────────

class EditorSnackBarController {
  final _queue = <EditorSnackBarEntry>[];

  /// What is showing, or null.
  final Signal<EditorSnackBarEntry?> current = Signal(
    null,
    debugLabel: 'snack',
  );

  /// The progress steps of [current] so far; a new list on every step.
  final Signal<List<EditorSnackBarStep>> steps = Signal(
    const [],
    debugLabel: 'snackSteps',
  );
  final _steps = <EditorSnackBarStep>[];
  StreamSubscription<EditorSnackBarStep>? _sub;
  // Tracks the pending auto-dismiss Timer (started via Future.delayed
  // previously) so dispose() can cancel it — otherwise it fires `minimize()`
  // on this controller after it's been disposed, throwing.
  Timer? _autoDismissTimer;
  final Signal<bool> isProgressDone = Signal(false, debugLabel: 'snackDone');
  final Signal<bool> isMinimized = Signal(false, debugLabel: 'snackMinimized');

  bool get hasProgressStream => current.value?.progressStream != null;

  void showSnackBar(EditorSnackBarEntry entry) {
    if (isMinimized.value) {
      // Discard the minimized entry; show the new one immediately.
      _sub?.cancel();
      _sub = null;
      _autoDismissTimer?.cancel();
      _autoDismissTimer = null;
      current.value = null;
      _steps.clear();
      steps.value = const [];
      isProgressDone.value = false;
      isMinimized.value = false;
    }
    _queue.add(entry);
    if (current.value == null) _dequeue();
  }

  /// Collapses the active snackbar to the dock chip.
  /// If more items are queued, dequeues the next one instead (no chip shown).
  void minimize() {
    if (current.value == null) return;
    if (_queue.isNotEmpty) {
      _sub?.cancel();
      _sub = null;
      _autoDismissTimer?.cancel();
      _autoDismissTimer = null;
      _steps.clear();
      steps.value = const [];
      isProgressDone.value = false;
      isMinimized.value = false;
      _dequeue();
    } else {
      isMinimized.value = true;
    }
  }

  /// Re-expands the minimized chip back to the full snackbar.
  void expand() {
    if (current.value == null || !isMinimized.value) return;
    isMinimized.value = false;
  }

  /// Fully dismisses the current entry and moves to the next in queue.
  void dismiss() {
    _sub?.cancel();
    _sub = null;
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    isMinimized.value = false;
    _dequeue();
  }

  void _dequeue() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
    if (_queue.isEmpty) {
      current.value = null;
      _steps.clear();
      steps.value = const [];
      isProgressDone.value = false;
      isMinimized.value = false;
      return;
    }
    current.value = _queue.removeAt(0);
    _steps.clear();
    steps.value = const [];
    isProgressDone.value = false;
    isMinimized.value = false;

    final stream = current.value!.progressStream;
    if (stream != null) {
      _sub = stream.listen(
        (step) {
          _steps.add(step);
          steps.value = List.unmodifiable(_steps);
        },
        onDone: () {
          isProgressDone.value = true;
          _autoDismissTimer = Timer(const Duration(seconds: 2), minimize);
        },
        onError: (Object err) {
          _steps.add(EditorSnackBarStep(message: 'Error: $err', isError: true));
          steps.value = List.unmodifiable(_steps);
          isProgressDone.value = true;
          _autoDismissTimer = Timer(const Duration(seconds: 3), minimize);
        },
      );
    } else {
      _autoDismissTimer = Timer(current.value!.duration, minimize);
    }
  }

  void dispose() {
    _sub?.cancel();
    _autoDismissTimer?.cancel();
    for (final signal in [current, steps, isProgressDone, isMinimized]) {
      signal.dispose();
    }
  }
}

// ── InheritedWidget host ──────────────────────────────────────────────────────

/// Wraps the editor overlay and provides [EditorSnackBarController] to the
/// subtree. Renders queued snackbars in its own Stack at bottom-right.
///
/// Usage: `EditorMessenger.of(context).show(EditorSnackBarEntry(...))`
class EditorMessenger extends StatefulWidget {
  const EditorMessenger({super.key, required this.child});

  final Widget child;

  static EditorSnackBarController of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_EditorSnackBarScope>();
    assert(inherited != null, 'No EditorMessenger found in the widget tree');
    return inherited!.controller;
  }

  @override
  State<EditorMessenger> createState() => _EditorMessengerState();
}

class _EditorMessengerState extends State<EditorMessenger> {
  final _controller = EditorSnackBarController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EditorSnackBarScope(controller: _controller, child: widget.child);
  }
}

/// Drop this as a child of a [Stack] that lives inside the game-canvas area.
/// It renders nothing when no snackbar is active.
class EditorSnackBarLayer extends StatelessWidget {
  const EditorSnackBarLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = EditorMessenger.of(context);
    return SignalConsumer(
      signals: [
        controller.current,
        controller.isMinimized,
        controller.steps,
        controller.isProgressDone,
      ],
      builder: (context, _) {
        if (controller.current.value == null || controller.isMinimized.value) {
          return const SizedBox.shrink();
        }
        return _EditorSnackBarWidget(controller: controller);
      },
    );
  }
}

class _EditorSnackBarScope extends InheritedWidget {
  const _EditorSnackBarScope({required this.controller, required super.child});

  final EditorSnackBarController controller;

  @override
  bool updateShouldNotify(_EditorSnackBarScope old) =>
      controller != old.controller;
}

// ── Snackbar widget ───────────────────────────────────────────────────────────

class _EditorSnackBarWidget extends StatefulWidget {
  const _EditorSnackBarWidget({required this.controller});

  final EditorSnackBarController controller;

  @override
  State<_EditorSnackBarWidget> createState() => _EditorSnackBarWidgetState();
}

class _EditorSnackBarWidgetState extends State<_EditorSnackBarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _timer;
  late final Animation<double> _timerAnim;

  @override
  void initState() {
    super.initState();
    _timer = AnimationController(vsync: this);
    _timerAnim = _timer;
    _resetTimer();
  }

  @override
  void didUpdateWidget(_EditorSnackBarWidget old) {
    super.didUpdateWidget(old);
    if (old.controller.current.value != widget.controller.current.value) {
      _resetTimer();
    }
  }

  void _resetTimer() {
    final entry = widget.controller.current.value;
    if (entry == null || entry.progressStream != null) {
      _timer.stop();
      return;
    }
    _timer
      ..reset()
      ..duration = entry.duration
      ..forward();
  }

  @override
  void dispose() {
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.controller.current.value;
    if (entry == null) return const SizedBox.shrink();

    final accent = entry.type.accentColor;
    final steps = widget.controller.steps.value;
    final isDone = widget.controller.isProgressDone.value;
    final hasStream = widget.controller.hasProgressStream;

    final headerIcon = (isDone && hasStream)
        ? Icons.check_circle_outline_rounded
        : entry.type.iconData;
    final headerIconColor = (isDone && hasStream)
        ? const Color(0xFF4ADE80)
        : accent;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 400,
        constraints: const BoxConstraints(minHeight: 100, maxHeight: 200),
        decoration: BoxDecoration(
          color: EditorTheme.surfaceBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(-2, 0),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // ── Left accent bar ──────────────────────────────────────────────
              Container(width: 3, color: accent),
              // ── Content ──────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // ── Header ────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              headerIcon,
                              size: 15,
                              color: headerIconColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (entry.title != null) ...<Widget>[
                                  Text(
                                    entry.title!,
                                    style: const TextStyle(
                                      color: EditorTheme.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                Text(
                                  entry.message,
                                  style: TextStyle(
                                    color: entry.title != null
                                        ? EditorTheme.textMuted
                                        : EditorTheme.textSecondary,
                                    fontSize: entry.title != null ? 11 : 12,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Minimize to dock',
                            child: InkWell(
                              onTap: widget.controller.minimize,
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 16,
                                  color: EditorTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Progress bar ──────────────────────────────────────────
                    if (hasStream)
                      _SnackProgressBar(color: accent, isIndeterminate: !isDone)
                    else
                      AnimatedBuilder(
                        animation: _timerAnim,
                        builder: (context, _) => _SnackProgressBar(
                          color: accent,
                          value: 1 - _timerAnim.value,
                        ),
                      ),
                    // ── Steps log ─────────────────────────────────────────────
                    Expanded(
                      child: SingleChildScrollView(
                        reverse: steps.isNotEmpty,
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: steps
                              .map((s) => _SnackStepRow(step: s))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnackProgressBar extends StatelessWidget {
  const _SnackProgressBar({
    required this.color,
    this.value,
    this.isIndeterminate = false,
  });

  final Color color;
  final double? value;
  final bool isIndeterminate;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: isIndeterminate ? null : (value ?? 1.0),
      minHeight: 3,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      valueColor: AlwaysStoppedAnimation<Color>(color),
    );
  }
}

class _SnackStepRow extends StatelessWidget {
  const _SnackStepRow({required this.step});

  final EditorSnackBarStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.isError ? EditorTheme.error : EditorTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              step.isError ? Icons.close_rounded : Icons.chevron_right_rounded,
              size: 12,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              step.message,
              style: TextStyle(fontSize: 11, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
