import 'package:flutter/widgets.dart';

/// Keys a focused panel keeps for itself, ahead of the editor's shortcuts.
///
/// The editor hears every key before the focused widget does, so F2 would
/// open the docks and Delete would delete the selection even while a list
/// has the focus and means those keys as its own: rename, delete this row.
/// A panel wraps itself in this and says which keys are its; while the
/// focus is inside it, the editor lets exactly those through to the
/// panel's own `Focus.onKeyEvent`, and handles every other key as usual.
/// Ctrl+S still saves.
class EditorKeyClaim extends StatelessWidget {
  const EditorKeyClaim({super.key, required this.claims, required this.child});

  /// Whether the panel wants [event], with the modifiers as they are now.
  final bool Function(KeyEvent event) claims;
  final Widget child;

  /// Whether the widget that has the focus sits in a claim that wants
  /// [event].
  static bool focusedClaims(KeyEvent event) {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || !context.mounted) return false;
    final claim = context.widget is EditorKeyClaim
        ? context.widget as EditorKeyClaim
        : context.findAncestorWidgetOfExactType<EditorKeyClaim>();
    return claim != null && claim.claims(event);
  }

  @override
  Widget build(BuildContext context) => child;
}
