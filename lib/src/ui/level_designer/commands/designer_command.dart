import 'package:flutter/services.dart';

import '../../../core/plugin/editor_plugin.dart';
import '../../../core/scope/editor_scope.dart';
import '../level_designer_session.dart';

/// When a command may run.
enum CommandScope {
  /// Needs an open designer session and authoring; the session dispatches.
  designer,

  /// Runs against the editor whenever it is open, after the designer has had
  /// its chance and never while typing in a text field.
  editor,

  /// Runs whenever the editor is open, even while typing (Save).
  always,
}

/// What a command is handed when it runs.
class CommandContext {
  const CommandContext({
    required this.scope,
    required this.modifiers,
    this.session,
    this.plugin,
    this.gridSize = 32,
  });

  final EditorScope scope;
  final ModifierKeys modifiers;

  /// The open designer session, if any.
  final LevelDesignerSession? session;

  /// The plugin, when dispatched from the editor rather than a bare session.
  final JustGameEditorPlugin? plugin;

  /// The authoring grid, for commands that move by a cell.
  final double gridSize;
}

/// Something the editor can do on request: from a key, a menu, a module's
/// own button. Identified by id so a binding can name it.
class DesignerCommand {
  const DesignerCommand({
    required this.id,
    required this.label,
    required this.run,
    this.scope = CommandScope.designer,
    this.isEnabled,
    this.repeats = false,
  });

  /// Stable id, namespaced: `'designer.nudgeLeft'`, `'mygame.spawnWave'`.
  final String id;

  /// Shown wherever commands are listed.
  final String label;

  final CommandScope scope;

  /// Whether the command can run right now; null means always.
  final bool Function(CommandContext context)? isEnabled;

  /// Whether a held key keeps firing it (nudging does; flipping must not).
  final bool repeats;

  final void Function(CommandContext context) run;

  bool enabledIn(CommandContext context) => isEnabled?.call(context) ?? true;
}

/// A key chord that runs a command.
///
/// Matched on the exact modifier set, so `Shift+Z` and `Z` are different
/// bindings — which is what lets one key mean two things.
class KeyBinding {
  const KeyBinding(
    this.key,
    this.commandId, {
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;
  final String commandId;
  final bool control;
  final bool shift;
  final bool alt;

  bool matches(LogicalKeyboardKey pressed, ModifierKeys mods) =>
      pressed == key &&
      mods.control == control &&
      mods.shift == shift &&
      mods.alt == alt;

  @override
  String toString() =>
      '${control ? 'Ctrl+' : ''}${shift ? 'Shift+' : ''}${alt ? 'Alt+' : ''}'
      '${key.keyLabel.isEmpty ? key.debugName : key.keyLabel} → $commandId';
}

/// The commands one editor knows and the keys that run them.
///
/// Bindings are resolved last-registered-first, so a module's binding for a
/// chord replaces a built-in's without the built-in having to know.
class CommandRegistry {
  CommandRegistry();

  final Map<String, DesignerCommand> _commands = {};
  final List<KeyBinding> _bindings = [];

  List<DesignerCommand> get all => List.unmodifiable(_commands.values);
  List<KeyBinding> get bindings => List.unmodifiable(_bindings);

  DesignerCommand? byId(String id) => _commands[id];

  /// Registers [command]; a second registration of the same id replaces the
  /// first only with [override].
  void register(DesignerCommand command, {bool override = false}) {
    if (!override && _commands.containsKey(command.id)) {
      throw StateError(
        'Command "${command.id}" is already registered; pass override: true',
      );
    }
    _commands[command.id] = command;
  }

  void registerAll(
    Iterable<DesignerCommand> commands, {
    bool override = false,
  }) {
    for (final c in commands) {
      register(c, override: override);
    }
  }

  /// Adds [binding]. It takes precedence over any earlier binding of the
  /// same chord.
  void bind(KeyBinding binding) => _bindings.add(binding);

  void bindAll(Iterable<KeyBinding> bindings) => _bindings.addAll(bindings);

  /// Removes every binding of [commandId].
  void unbind(String commandId) =>
      _bindings.removeWhere((b) => b.commandId == commandId);

  /// The bindings that run [commandId], for tooltips.
  List<KeyBinding> bindingsFor(String commandId) => [
    for (final b in _bindings)
      if (b.commandId == commandId) b,
  ];

  /// The command bound to [key] with [mods], or null.
  DesignerCommand? resolve(LogicalKeyboardKey key, ModifierKeys mods) {
    for (final b in _bindings.reversed) {
      if (b.matches(key, mods)) return _commands[b.commandId];
    }
    return null;
  }

  /// Runs the command bound to [key], if it is in one of [scopes], enabled,
  /// and (on a repeat) repeatable. Returns whether anything ran.
  bool dispatch(
    LogicalKeyboardKey key,
    CommandContext context, {
    required Set<CommandScope> scopes,
    bool isRepeat = false,
  }) {
    final command = resolve(key, context.modifiers);
    if (command == null || !scopes.contains(command.scope)) return false;
    if (isRepeat && !command.repeats) return false;
    if (!command.enabledIn(context)) return false;
    command.run(context);
    return true;
  }

  void clear() {
    _commands.clear();
    _bindings.clear();
  }
}
