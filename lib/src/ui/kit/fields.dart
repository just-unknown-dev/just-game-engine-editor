import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/editor_constants.dart';
import '../../core/theme/editor_metrics.dart';

/// The decoration every small field in the editor shares: a dark fill, a
/// line that shows, the accent when it has the keyboard.
InputDecoration editorFieldDecoration({
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
  EdgeInsetsGeometry? contentPadding,
  String? suffixText,
}) {
  OutlineInputBorder line(Color colour) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(EditorMetrics.radiusSm + 1),
    borderSide: BorderSide(color: colour),
  );
  return InputDecoration(
    isDense: true,
    filled: true,
    fillColor: EditorTheme.surfaceDarker,
    hintText: hint,
    hintStyle: TextStyle(color: EditorTheme.textMuted, fontSize: 11),
    prefixIcon: prefixIcon,
    prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 24),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    suffixText: suffixText,
    suffixStyle: TextStyle(color: EditorTheme.textMuted, fontSize: 10),
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    border: line(EditorTheme.borderStrong.withValues(alpha: 0.6)),
    enabledBorder: line(EditorTheme.borderStrong.withValues(alpha: 0.6)),
    focusedBorder: line(EditorTheme.primaryMutedLight),
  );
}

/// A compact search box. [onChanged] fires as the text changes; the clear
/// button empties it.
class EditorSearchField extends StatefulWidget {
  const EditorSearchField({
    super.key,
    required this.onChanged,
    this.initial = '',
    this.hint = 'Search',
    this.width = 220,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
  });

  final ValueChanged<String> onChanged;

  /// Enter pressed in the field: do the obvious thing with what it found.
  final ValueChanged<String>? onSubmitted;
  final String initial;
  final String hint;

  /// Null fills the width it is given.
  final double? width;

  /// The field's text, when the owner wants to read or clear it.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<EditorSearchField> createState() => _EditorSearchFieldState();
}

class _EditorSearchFieldState extends State<EditorSearchField> {
  TextEditingController? _own;
  TextEditingController get _text =>
      widget.controller ??
      (_own ??= TextEditingController(text: widget.initial));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: EditorMetrics.minTarget,
    child: TextField(
      controller: _text,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      cursorColor: EditorTheme.primaryBright,
      onChanged: (v) {
        widget.onChanged(v);
        setState(() {});
      },
      onSubmitted: widget.onSubmitted,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      decoration: editorFieldDecoration(
        hint: widget.hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 13,
          color: EditorTheme.textMuted,
        ),
        suffixIcon: _text.text.isEmpty
            ? null
            : Tooltip(
                message: 'Clear',
                child: InkWell(
                  onTap: _clear,
                  borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
                  child: SizedBox.square(
                    dimension: 22,
                    child: Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: EditorTheme.textMuted,
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

/// The typed fields that have the keyboard, and what each keeps.
///
/// A field keeps what was typed when it is left; a command that runs while
/// one is still being typed in — Save works even then — calls [flush]
/// first, so what was typed is in what it acts on rather than lost behind
/// it. A field [join]s while it has the focus and [leave]s when it goes.
abstract final class PendingFieldEdits {
  static final Set<VoidCallback> _keepers = {};

  /// Keeps what every focused field holds, as leaving it would.
  static void flush() {
    for (final keep in [..._keepers]) {
      keep();
    }
  }

  /// [keep] is called by [flush] until [leave].
  static void join(VoidCallback keep) => _keepers.add(keep);

  /// Stops calling [keep].
  static void leave(VoidCallback keep) => _keepers.remove(keep);
}

/// Whether [event] is Esc going down: what puts a field's value back.
bool isEscapeDown(KeyEvent event) =>
    event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;

/// A text field that keeps what was typed when Enter is pressed or when it
/// loses the focus — Tab, a click anywhere else — the one rule every typed
/// field in the editor follows, and shows a value changed from outside, an
/// undo say, whenever it is not being typed in. Esc puts back what was
/// there and leaves the field.
///
/// [onCommit] runs once per change: not again for the focus leaving right
/// after an Enter, and not at all when the text is what it was.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.accept,
    this.style,
    this.decoration,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.autofocus = false,
  });

  final String value;
  final ValueChanged<String> onCommit;

  /// Whether typed text can be kept — a number that reads as one, say.
  /// Text it refuses is not passed to [onCommit]: the field shows what it
  /// had again. Null keeps any text.
  final bool Function(String text)? accept;
  final TextStyle? style;

  /// [editorFieldDecoration] when null.
  final InputDecoration? decoration;
  final TextInputType keyboardType;

  /// More than one wraps a long value onto more lines; Enter still keeps
  /// it rather than starting a new line.
  final int maxLines;
  final TextAlign textAlign;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  /// What was last kept or shown from outside: the text that is not a
  /// change.
  late String _kept = widget.value;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant CommitTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _text.text = widget.value;
      _kept = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    PendingFieldEdits.leave(_commit);
    _ownFocus?.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      PendingFieldEdits.join(_commit);
    } else {
      PendingFieldEdits.leave(_commit);
      if (mounted) _commit();
    }
  }

  void _commit() {
    final text = _text.text;
    if (text == _kept) return;
    if (widget.accept?.call(text) == false) {
      _text.text = _kept;
      return;
    }
    _kept = text;
    widget.onCommit(text);
  }

  /// Esc, with a change typed: what was there, and out of the field. With
  /// nothing typed Esc is left to whoever wants it — a dialog closing.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isEscapeDown(event) || _text.text == _kept) {
      return KeyEventResult.ignored;
    }
    _text.text = _kept;
    _focus.unfocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: TextField(
      controller: _text,
      focusNode: _focus,
      autofocus: widget.autofocus,
      style:
          widget.style ??
          TextStyle(color: EditorTheme.textPrimary, fontSize: 11),
      decoration: widget.decoration ?? editorFieldDecoration(),
      cursorColor: EditorTheme.primaryBright,
      keyboardType: widget.keyboardType,
      textAlign: widget.textAlign,
      minLines: 1,
      maxLines: widget.maxLines,
      // Enter keeps the value, even in a field that wraps onto more lines.
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _focus.unfocus(),
    ),
  );
}
