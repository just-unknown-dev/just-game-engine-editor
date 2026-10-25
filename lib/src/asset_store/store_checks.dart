import 'package:just_asset_store/just_asset_store.dart';
import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart';

import 'store_controller.dart';

/// The store's entries in the Problems dock.
///
/// The dock asks every second or so, on the UI thread, so the answer is
/// worked out at most once every few seconds and kept: these checks read
/// files, and the dock must stay cheap.
class StoreChecks {
  StoreChecks(this.controller, {this.every = const Duration(seconds: 5)});

  final StoreController controller;

  /// How long an answer is kept.
  final Duration every;

  DateTime? _at;
  List<SceneProblem> _last = const [];

  /// The problems, as the Problems dock wants them.
  List<SceneProblem> check(ValidationContext context) {
    final now = DateTime.now();
    if (_at != null && now.difference(_at!) < every) return _last;
    _at = now;
    try {
      _last = _check();
    } on Object catch (e) {
      _last = [
        SceneProblem(
          message: 'The Asset Store cannot read this project: $e',
          hint: 'Look at just_store.lock.json.',
        ),
      ];
    }
    return _last;
  }

  /// Forgets the kept answer: the next check works it out again.
  void invalidate() => _at = null;

  List<SceneProblem> _check() {
    final project = controller.project;
    if (!project.file(StoreLock.fileName).existsSync()) return const [];
    final lock = project.readLock();
    final out = <SceneProblem>[];

    for (final e in lock.items.entries) {
      final path = e.value.path;
      if (e.value.origin != ItemOrigin.vendored || path == null) continue;
      if (!project.dir(path).existsSync()) {
        out.add(
          SceneProblem(
            message: '${e.key} is installed, but $path is missing.',
            hint:
                'Open the Asset Store, then Sources → Restore missing '
                'packages.',
          ),
        );
      }
    }

    final stale = StoreRegistry.outdated(project);
    if (stale.isNotEmpty) {
      out.add(
        SceneProblem(
          message:
              "The store's generated ${stale.length == 1 ? 'file is' : 'files are'} "
              'out of date: ${stale.join(', ')}.',
          hint: 'Run `just store generate`.',
        ),
      );
    }

    final manifests = StoreRegistry.manifests(project, lock);
    final registersModules = manifests.entries.any(
      (e) => lock.items[e.key]!.registerModules && e.value.modules.isNotEmpty,
    );
    final registersExtensions = manifests.entries.any(
      (e) =>
          lock.items[e.key]!.registerExtensions &&
          e.value.extensions.isNotEmpty,
    );
    if (registersModules || registersExtensions) {
      final uses = _libUses(project);
      if (registersModules && !uses.contains('storeModules')) {
        out.add(
          const SceneProblem(
            message:
                "The editor's entry point does not register the store's "
                'editor tools.',
            hint:
                'In lib/main_editor.dart, import '
                "'editor/store_modules.g.dart' and add ...storeModules() to "
                'the modules list.',
          ),
        );
      }
      if (registersExtensions && !uses.contains('storeExtensions')) {
        out.add(
          const SceneProblem(
            message:
                "The game does not register the store's kits: their "
                'components will not load.',
            hint:
                "Import 'store_extensions.g.dart' (in lib/game/) and add "
                '...storeExtensions to the EngineConfig extensions.',
          ),
        );
      }
    }

    final catalog = controller.catalog?.catalog;
    if (catalog != null) {
      for (final e in lock.items.entries) {
        final removal = catalog.removal(e.key, source: e.value.source);
        if (removal != null) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              message: '${e.key} was taken down by the store: '
                  '${removal.reason}',
              hint: 'Uninstall it in the Asset Store.',
            ),
          );
          continue;
        }
        final item = catalog.entry(e.key)?.item;
        if (item != null && item.stage == ItemStage.deprecated) {
          final by = item.replacedBy;
          out.add(
            SceneProblem(
              message: '${item.name} is deprecated: it is no longer '
                  'developed.',
              hint: by == null
                  ? 'Look for another in the Asset Store.'
                  : 'Install ${catalog.entry(by)?.item.name ?? by} instead, '
                        'in the Asset Store.',
            ),
          );
        }
        final version = Version.tryParse(e.value.version);
        final listed = version == null ? null : item?.versionOf(version);
        if (listed != null && listed.blocked) {
          out.add(
            SceneProblem(
              severity: ProblemSeverity.error,
              message:
                  '${item!.name} ${e.value.version} was taken down by the '
                  'store (a licence or safety problem).',
              hint: 'Uninstall it in the Asset Store.',
            ),
          );
        }
      }
    }
    return out;
  }

  /// Which of the generated lists the project's code names.
  static Set<String> _libUses(StoreProject project) {
    final out = <String>{};
    final lib = project.dir('lib');
    if (!lib.existsSync()) return out;
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final text = f.readAsStringSync();
      if (text.contains('storeModules()')) out.add('storeModules');
      if (text.contains('storeExtensions')) out.add('storeExtensions');
      if (out.length == 2) break;
    }
    return out;
  }
}
