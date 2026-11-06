import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_editor_core/host.dart';
import 'problem_scan.dart';

/// The Problems dock: each thing wrong with the scene, and who it is about.
class ProblemsDock extends StatefulWidget {
  const ProblemsDock({super.key, required this.scope, required this.scan});

  final EditorScope scope;
  final ProblemScan scan;

  @override
  State<ProblemsDock> createState() => _ProblemsDockState();
}

class _ProblemsDockState extends State<ProblemsDock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      // Checked here, between frames, if it is due — not in the build
      // that follows, which only reads what was found.
      widget.scan.problems;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final problems = widget.scan.problems;
    if (!widget.scope.sceneState.hasScene) {
      return const EditorEmptyState(
        icon: Icons.rule_rounded,
        title: 'No scene open',
        hint: 'Problems are checked for the scene being edited.',
      );
    }
    if (problems.isEmpty) {
      return const EditorEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Nothing wrong that the editor can see',
        hint:
            'Missing files, broken references, animator clips that do not '
            'exist and cameras with nothing to follow show up here.',
      );
    }
    return ListView.builder(
      itemCount: problems.length,
      itemBuilder: (context, i) {
        final p = problems[i];
        final color = p.severity == ProblemSeverity.error
            ? EditorTheme.error
            : EditorTheme.warning;
        return InkWell(
          onTap: p.entity == null
              ? null
              : () => widget.scope.sceneState.selectEntity(p.entity!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(width: 2, color: color)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  p.severity == ProblemSeverity.error
                      ? Icons.error_outline_rounded
                      : Icons.warning_amber_rounded,
                  size: 13,
                  color: color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.message,
                        style: TextStyle(
                          color: EditorTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                      if (p.hint != null)
                        Text(
                          p.hint!,
                          style: TextStyle(
                            color: EditorTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      if (p.fixes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              for (final fix in p.fixes)
                                _FixButton(
                                  label: fix.label,
                                  onTap: () {
                                    fix.apply();
                                    widget.scan.refresh();
                                    setState(() {});
                                  },
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (p.entity != null)
                  Icon(
                    Icons.my_location_rounded,
                    size: 12,
                    color: EditorTheme.primaryBright,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One way to fix a problem, as a small button under it.
class _FixButton extends StatelessWidget {
  const _FixButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: EditorTheme.primary.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(3),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_fix_high_rounded,
              size: 11,
              color: EditorTheme.primaryBright,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: EditorTheme.primaryBright,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
