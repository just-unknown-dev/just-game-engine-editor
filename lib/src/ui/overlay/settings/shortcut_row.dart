import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:just_editor_core/host.dart';

/// One command on the Keyboard page: what it is called, the keys that run
/// it, and a way to change them — click, then press the new chord.
///
/// While it listens every key is its own, Esc included: Esc cancels. A
/// chord another command has is not simply taken: the row says whose it is
/// and asks.
class ShortcutRow extends StatefulWidget {
  const ShortcutRow({
    super.key,
    required this.scope,
    required this.command,
    required this.keys,
    required this.isModified,
    required this.accent,
    required this.onChanged,
    required this.onReset,
  });

  final EditorScope scope;
  final DesignerCommand command;

  /// The chords that run it now, as they read: `Ctrl+Shift+S`, and
  /// `Cmd+Shift+S` on macOS.
  final List<String> keys;

  /// Whether its keys are not the ones it was built with.
  final bool isModified;
  final Color accent;

  /// [chords] now run the command. With [takeFrom], that command gives up
  /// [chord], which it had. Chords come as settings store them
  /// ([KeyBinding.savedChord]): `Ctrl+S` on every platform.
  final void Function(List<String> chords, {String? takeFrom, String? chord})
  onChanged;

  /// Back to the keys it was built with.
  final VoidCallback onReset;

  @override
  State<ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends State<ShortcutRow> {
  final FocusNode _focus = FocusNode(debugLabel: 'shortcutCapture');
  bool _listening = false;

  /// The row listening for keys, per editor. Moving from one row to another
  /// starts the second before the first hears it lost the focus: the first
  /// must not then tell the editor nobody is listening.
  static final Expando<_ShortcutRowState> _capturing = Expando(
    'shortcutCapture',
  );

  void _capture(bool on) {
    final scope = widget.scope;
    if (on) {
      _capturing[scope] = this;
      scope.chrome.capturingKeys = true;
    } else if (identical(_capturing[scope], this)) {
      _capturing[scope] = null;
      scope.chrome.capturingKeys = false;
    }
  }

  /// Why the last chord was not taken.
  String? _note;

  /// A chord another command has, waiting on "Use it anyway".
  KeyBinding? _pending;
  DesignerCommand? _owner;

  @override
  void dispose() {
    if (_listening) _capture(false);
    _focus.dispose();
    super.dispose();
  }

  void _listen() {
    _capture(true);
    setState(() {
      _listening = true;
      _note = null;
      _pending = null;
      _owner = null;
    });
    _focus.requestFocus();
  }

  void _stop() {
    _capture(false);
    if (!mounted) return;
    setState(() {
      _listening = false;
      _note = null;
      _pending = null;
      _owner = null;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_listening) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    // Held on the way to a chord: wait for the key it is held for.
    if (KeyBinding.isModifier(key)) return KeyEventResult.handled;
    final keyboard = HardwareKeyboard.instance;
    // The primary modifier: Cmd on macOS, Ctrl elsewhere — what a binding's
    // `control` means.
    final control = EditorKeys.primaryPressed;
    final shift = keyboard.isShiftPressed;
    final alt = keyboard.isAltPressed;
    if (key == LogicalKeyboardKey.escape && !control && !shift && !alt) {
      _stop();
      return KeyEventResult.handled;
    }
    // Ctrl on a Mac, the Windows key elsewhere: no binding is made with it,
    // and none runs while it is held — recorded, it would be dropped.
    if (EditorKeys.otherPressed) {
      _refuse(
        'Shortcuts are made with ${EditorKeys.primaryLabel}, Shift and Alt.',
      );
      return KeyEventResult.handled;
    }
    if (widget.scope.chrome.reservedKeys.contains(key)) {
      _refuse('${KeyBinding.nameOf(key)} is kept for the editor itself.');
      return KeyEventResult.handled;
    }
    // A command that runs even while typing (Save) on a key that types
    // something would take that character from every text field: a letter,
    // a digit, Shift and one — and on a Mac Option and one, which types too
    // (Option+S is ß).
    if (widget.command.scope == CommandScope.always &&
        !control &&
        (!alt || EditorKeys.isMac) &&
        _types(key)) {
      final typed = shift || alt
          ? KeyBinding.chord(key, shift: shift, alt: alt)
          : '${KeyBinding.nameOf(key)} alone';
      _refuse(
        '$typed would stop it being typed: add '
        '${EditorKeys.isMac ? 'Cmd' : 'Ctrl or Alt'}.',
      );
      return KeyEventResult.handled;
    }
    final binding = KeyBinding(
      key,
      widget.command.id,
      control: control,
      shift: shift,
      alt: alt,
    );
    final owner = widget.scope.commands.conflictWith(binding);
    if (owner != null) {
      setState(() {
        _pending = binding;
        _owner = owner;
        _note = null;
      });
      return KeyEventResult.handled;
    }
    _use(binding);
    return KeyEventResult.handled;
  }

  /// Says why the chord just pressed is not taken, and keeps listening.
  void _refuse(String why) => setState(() {
    _note = why;
    _pending = null;
  });

  /// Whether [key] types a character: a letter, a digit, a sign, space.
  static bool _types(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.space ||
      key.keyLabel.runes.length == 1 && key.keyLabel.trim().isNotEmpty;

  /// Hands on the chord as settings store it: `Ctrl+` on every platform.
  void _use(KeyBinding binding, {DesignerCommand? takingFrom}) {
    widget.onChanged(
      [binding.savedChord],
      takeFrom: takingFrom?.id,
      chord: binding.savedChord,
    );
    _stop();
  }

  void _clear() {
    widget.onChanged(const []);
    _stop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: EditorTheme.textMuted, fontSize: 11);
    return Container(
      constraints: BoxConstraints(minHeight: EditorMetrics.minTarget + 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.command.label,
                    style: TextStyle(
                      color: EditorTheme.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.isModified) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Not the keys it came with',
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: _listening ? _listeningArea(muted) : _keysArea(muted),
            ),
          ),
        ],
      ),
    );
  }

  /// The keys as they are, a click away from changing.
  Widget _keysArea(TextStyle muted) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Semantics(
          button: true,
          label: 'Change the keys for ${widget.command.label}',
          child: InkWell(
            onTap: _listen,
            borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: widget.keys.isEmpty
                  ? Text('No key', style: muted)
                  : Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [for (final k in widget.keys) KeyCap(k)],
                    ),
            ),
          ),
        ),
      ),
      EditorIconButton(
        icon: Icons.edit_outlined,
        tooltip: 'Change the keys',
        onTap: _listen,
      ),
      if (widget.isModified)
        EditorIconButton(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Back to the keys it came with',
          onTap: widget.onReset,
        )
      else
        SizedBox(width: EditorMetrics.controlSm),
    ],
  );

  /// Waiting for a chord — or asking about one another command has.
  Widget _listeningArea(TextStyle muted) {
    final pending = _pending;
    final owner = _owner;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      onFocusChange: (has) {
        // Clicked away while only listening: stop. A question stays until
        // it is answered.
        if (!has && pending == null) _stop();
      },
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (pending != null && owner != null) ...[
            KeyCap(pending.shortcut),
            Text(
              'runs “${owner.label}”.',
              style: TextStyle(color: EditorTheme.warning, fontSize: 11),
            ),
            EditorButton(
              label: 'Use it anyway',
              kind: EditorButtonKind.primary,
              onPressed: () => _use(pending, takingFrom: owner),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(EditorMetrics.radiusSm),
                border: Border.all(color: widget.accent),
              ),
              child: Text(
                _note ?? 'Press the new keys…',
                style: TextStyle(
                  color: _note == null
                      ? EditorTheme.textPrimary
                      : EditorTheme.warning,
                  fontSize: 11,
                ),
              ),
            ),
            EditorButton(label: 'No key', onPressed: _clear),
          ],
          EditorButton(
            label: 'Cancel',
            kind: EditorButtonKind.ghost,
            onPressed: _stop,
          ),
        ],
      ),
    );
  }
}
