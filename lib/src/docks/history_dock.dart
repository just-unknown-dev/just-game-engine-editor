import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_editor_core/host.dart';

/// The undo stack as a list: what was done, in order, and a click to go back
/// to any point of it.
class HistoryDock extends StatelessWidget {
  const HistoryDock({super.key, required this.history});

  /// The editor's undo stack. Null only if a module swaps in none.
  final ValueListenable<EditorHistory?> history;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<EditorHistory?>(
    valueListenable: history,
    builder: (context, h, _) {
      if (h == null) {
        return const EditorEmptyState(
          icon: Icons.history_rounded,
          title: 'No history',
          hint: 'Nothing is keeping an undo history for this editor.',
        );
      }
      return ValueListenableBuilder<int>(
        valueListenable: h.revision,
        builder: (context, _, _) {
          final done = h.undoEntries;
          final undone = h.redoEntries.reversed.toList();
          if (done.isEmpty && undone.isEmpty) {
            return const EditorEmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing done yet',
              hint: 'Every edit is a step here: click one to go back to it.',
            );
          }
          return ListView(
            children: [
              _HistoryRow(
                label: 'Scene as opened',
                isCurrent: done.isEmpty,
                isUndone: false,
                onTap: () => h.jumpTo(0),
              ),
              for (var i = 0; i < done.length; i++)
                _HistoryRow(
                  label: done[i].label,
                  isCurrent: i == done.length - 1,
                  isUndone: false,
                  onTap: () => h.jumpTo(i + 1),
                ),
              for (var i = 0; i < undone.length; i++)
                _HistoryRow(
                  label: undone[i].label,
                  isCurrent: false,
                  isUndone: true,
                  onTap: () => h.jumpTo(done.length + i + 1),
                ),
            ],
          );
        },
      );
    },
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.isCurrent,
    required this.isUndone,
    required this.onTap,
  });

  final String label;
  final bool isCurrent;
  final bool isUndone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 22,
      color: isCurrent ? EditorTheme.selectionBg : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(
            isCurrent
                ? Icons.arrow_right_rounded
                : isUndone
                ? Icons.redo_rounded
                : Icons.check_rounded,
            size: 13,
            color: isCurrent
                ? EditorTheme.primaryBright
                : EditorTheme.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isUndone
                    ? EditorTheme.textMuted
                    : EditorTheme.textPrimary,
                fontStyle: isUndone ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
