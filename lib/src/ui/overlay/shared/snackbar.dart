import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_signals/just_signals.dart';

import '../../../core/constants/editor_constants.dart';
import '../../../core/theme/editor_metrics.dart';
import '../../kit/buttons.dart';
import '../settings/overlay_ui_settings.dart';

// ── Public types ───────────────────────────────────────────────────────────────

enum EditorSnackBarType { info, success, warning, error }

extension EditorSnackBarTypeX on EditorSnackBarType {
  Color get accentColor => switch (this) {
    EditorSnackBarType.info => EditorTheme.info,
    EditorSnackBarType.success => EditorTheme.success,
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
/// For simple fire-and-forget messages, omit [progressStream] and set
/// [duration]. For task-tracking snackbars, provide a [progressStream] — the
/// bar stays indeterminate until the stream closes, then the snackbar goes
/// after a moment; one that ends in an error stays until it is dismissed.
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

  /// How long a message-only snackbar stays. Ignored when [progressStream]
  /// is provided.
  final Duration duration;

  /// When non-null the snackbar enters progress mode: the bar is
  /// indeterminate and each emitted [EditorSnackBarStep] is listed in a
  /// scrollable step log.
  final Stream<EditorSnackBarStep>? progressStream;
}

/// One snackbar that has been shown and not yet dismissed, with what it has
/// heard from its task so far. Each keeps its own subscription and timer, so
/// showing or minimising another never cuts its task off.
class EditorSnack {
  EditorSnack._(this.entry, this._controller);

  final EditorSnackBarEntry entry;
  final EditorSnackBarController _controller;

  final List<EditorSnackBarStep> _steps = [];
  List<EditorSnackBarStep> get steps => List.unmodifiable(_steps);

  /// The task has finished — or there never was one.
  bool get isDone => _done;
  bool _done = false;

  /// The task ended in an error: the snackbar stays until dismissed.
  bool get failed => _failed;
  bool _failed = false;

  /// Collapsed into the chip on the status strip.
  bool get isMinimized => _minimized;
  bool _minimized = false;

  bool get hasProgress => entry.progressStream != null;

  /// How long a message stays: its own time, longer with longer timings.
  Duration get shownFor => entry.duration * EditorMetrics.messageTimeScale;

  StreamSubscription<EditorSnackBarStep>? _sub;
  Timer? _timer;

  void _start() {
    final stream = entry.progressStream;
    if (stream == null) {
      _done = true;
      _timer = Timer(shownFor, () => _controller.dismiss(this));
      return;
    }
    _sub = stream.listen(
      (step) {
        _steps.add(step);
        if (step.isError) _failed = true;
        _controller._publish();
      },
      onDone: () {
        _done = true;
        _controller._publish();
        if (!_failed) {
          _timer = Timer(
            const Duration(seconds: 3) * EditorMetrics.messageTimeScale,
            () => _controller.dismiss(this),
          );
        }
      },
      onError: (Object err) {
        _steps.add(EditorSnackBarStep(message: 'Error: $err', isError: true));
        _done = true;
        _failed = true;
        _controller._publish();
      },
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
  }
}

// ── Controller ────────────────────────────────────────────────────────────────

class EditorSnackBarController {
  /// Every snackbar not yet dismissed, oldest first.
  final Signal<List<EditorSnack>> snacks = Signal(
    const [],
    debugLabel: 'snacks',
  );

  /// At most this many show at once; older ones make room.
  static const int maxVisible = 3;

  bool _disposed = false;

  /// The snackbars showing over the editor, oldest first.
  List<EditorSnack> get visible => [
    for (final s in snacks.value)
      if (!s.isMinimized) s,
  ];

  /// The snackbars collapsed into the status strip's chip, oldest first.
  List<EditorSnack> get minimized => [
    for (final s in snacks.value)
      if (s.isMinimized) s,
  ];

  /// Whether [entry] shows at [level]. What follows a task always does: it
  /// may end in an error.
  static bool shows(EditorSnackBarEntry entry, MessageLevel level) {
    if (entry.progressStream != null) return true;
    return switch (level) {
      MessageLevel.all => true,
      MessageLevel.important =>
        entry.type == EditorSnackBarType.warning ||
            entry.type == EditorSnackBarType.error,
      MessageLevel.errors => entry.type == EditorSnackBarType.error,
    };
  }

  /// Shows [entry], unless the settings ask for quieter messages than it
  /// is: then it is handed back already gone.
  EditorSnack showSnackBar(EditorSnackBarEntry entry) {
    final snack = EditorSnack._(entry, this);
    if (!shows(entry, EditorMetrics.settings.messageLevel)) return snack;
    snacks.value = List.unmodifiable([...snacks.value, snack]);
    snack._start();
    _makeRoom();
    return snack;
  }

  /// Too many showing: the oldest message goes, or — when every one tracks
  /// a task — the oldest is minimised, its task still followed.
  void _makeRoom() {
    var showing = visible;
    while (showing.length > maxVisible) {
      final oldest = showing.firstWhere(
        (s) => !s.hasProgress,
        orElse: () => showing.first,
      );
      if (oldest.hasProgress) {
        oldest._minimized = true;
        _publish();
      } else {
        dismiss(oldest);
      }
      showing = visible;
    }
  }

  /// Collapses [snack] into the status strip's chip. Its task goes on.
  void minimize(EditorSnack snack) {
    snack._minimized = true;
    _publish();
  }

  /// Brings back every minimised snackbar.
  void expandAll() {
    for (final s in snacks.value) {
      s._minimized = false;
    }
    _publish();
    _makeRoom();
  }

  /// Takes [snack] away for good, and stops following its task.
  void dismiss(EditorSnack snack) {
    snack._stop();
    if (_disposed) return;
    snacks.value = List.unmodifiable([
      for (final s in snacks.value)
        if (!identical(s, snack)) s,
    ]);
  }

  /// Takes every minimised snackbar away.
  void dismissMinimized() {
    for (final s in minimized) {
      dismiss(s);
    }
  }

  void _publish() {
    if (!_disposed) snacks.forceSet(snacks.value);
  }

  void dispose() {
    _disposed = true;
    for (final s in snacks.value) {
      s._stop();
    }
    snacks.dispose();
  }
}

// ── InheritedWidget host ──────────────────────────────────────────────────────

/// Wraps the editor overlay and provides [EditorSnackBarController] to the
/// subtree; [EditorSnackBarLayer] draws what it holds.
///
/// Usage: `EditorMessenger.of(context).showSnackBar(EditorSnackBarEntry(...))`
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

/// The snackbars showing, stacked newest at the bottom. Drop it in a
/// [Stack], positioned against the corner of the canvas it should sit in.
class EditorSnackBarLayer extends StatelessWidget {
  const EditorSnackBarLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = EditorMessenger.of(context);
    return SignalBuilder<List<EditorSnack>>(
      signal: controller.snacks,
      builder: (context, _, _) {
        final showing = controller.visible;
        if (showing.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < showing.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _SnackCard(
                key: ObjectKey(showing[i]),
                snack: showing[i],
                controller: controller,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The status strip's word on minimised snackbars: the latest one's title,
/// how many there are, and a click to bring them back.
class MinimizedSnacksChip extends StatelessWidget {
  const MinimizedSnacksChip({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = EditorMessenger.of(context);
    return SignalBuilder<List<EditorSnack>>(
      signal: controller.snacks,
      builder: (context, _, _) {
        final hidden = controller.minimized;
        if (hidden.isEmpty) return const SizedBox.shrink();
        final latest = hidden.last;
        final failed = hidden.any((s) => s.failed);
        final running = hidden.any((s) => !s.isDone);
        final accent = failed
            ? EditorTheme.error
            : latest.entry.type.accentColor;
        final label = latest.entry.title ?? latest.entry.message;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: hidden.length == 1
                ? 'Show the message again'
                : 'Show ${hidden.length} messages again',
            child: Material(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: controller.expandAll,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 240),
                  height: 20,
                  padding: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accent.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (running)
                        SizedBox.square(
                          dimension: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: accent,
                          ),
                        )
                      else
                        Icon(
                          failed
                              ? Icons.error_outline_rounded
                              : latest.entry.type.iconData,
                          size: 11,
                          color: accent,
                        ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          hidden.length == 1
                              ? label
                              : '$label  +${hidden.length - 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: EditorTheme.textSecondary,
                            height: 1.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Tooltip(
                        message: 'Dismiss',
                        child: InkWell(
                          onTap: controller.dismissMinimized,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: Icon(
                              Icons.close_rounded,
                              size: 11,
                              color: EditorTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
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

// ── Snackbar card ─────────────────────────────────────────────────────────────

class _SnackCard extends StatefulWidget {
  const _SnackCard({super.key, required this.snack, required this.controller});

  final EditorSnack snack;
  final EditorSnackBarController controller;

  @override
  State<_SnackCard> createState() => _SnackCardState();
}

class _SnackCardState extends State<_SnackCard>
    with SingleTickerProviderStateMixin {
  // The time a message has left, drawn as the bar running down.
  late final AnimationController _left = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    final entry = widget.snack.entry;
    if (entry.progressStream == null) {
      _left
        ..duration = widget.snack.shownFor
        ..forward();
    }
  }

  @override
  void dispose() {
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snack = widget.snack;
    final entry = snack.entry;
    final steps = snack.steps;
    final finished = snack.hasProgress && snack.isDone;
    final accent = snack.failed
        ? EditorTheme.error
        : finished
        ? EditorTheme.success
        : entry.type.accentColor;
    final icon = snack.failed
        ? Icons.error_outline_rounded
        : finished
        ? Icons.check_circle_outline_rounded
        : entry.type.iconData;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        constraints: const BoxConstraints(maxHeight: 240),
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
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          // The accent down the left edge; the card is as tall as what it
          // says, up to its limit.
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(icon, size: 15, color: accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              if (entry.title != null) ...<Widget>[
                                Text(
                                  entry.title!,
                                  style: TextStyle(
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
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      EditorIconButton(
                        icon: Icons.keyboard_arrow_down_rounded,
                        tooltip: 'Minimise to the status bar',
                        onTap: () => widget.controller.minimize(snack),
                      ),
                      EditorIconButton(
                        icon: Icons.close_rounded,
                        tooltip: 'Dismiss',
                        onTap: () => widget.controller.dismiss(snack),
                      ),
                    ],
                  ),
                ),
                if (snack.hasProgress)
                  _SnackProgressBar(
                    color: accent,
                    isIndeterminate: !snack.isDone,
                  )
                else
                  AnimatedBuilder(
                    animation: _left,
                    builder: (context, _) => _SnackProgressBar(
                      color: accent,
                      value: 1 - _left.value,
                    ),
                  ),
                if (steps.isNotEmpty)
                  Flexible(
                    child: SingleChildScrollView(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final s in steps) _SnackStepRow(step: s),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
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
      minHeight: 2,
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
