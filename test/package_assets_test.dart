// Packages' assets, `packages/<name>/…`, wherever the package is installed:
// found, loaded, listed in the Assets dock (and kept read-only there),
// checked by the validators — plus the hooks the Asset Store uses: a batch
// reload and progress messages.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/src/core/assets/file_sprite_asset_loader.dart';
import 'package:just_editor_core/host.dart';

import 'support/test_scope.dart';
import 'package:just_game_engine_editor/src/core/validation/built_in_validators.dart';

const String png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  late Directory dir;
  late String root;

  void write(String path, Object content) {
    final f = File('$root/$path')..parent.createSync(recursive: true);
    content is List<int>
        ? f.writeAsBytesSync(content)
        : f.writeAsStringSync('$content');
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('package_assets');
    root = dir.path.replaceAll(r'\', '/');
    // A store item, installed where the store installs them…
    write(
      'packages/characters/knight/pubspec.yaml',
      'name: knight\nversion: 1.0.0\nflutter:\n  assets:\n'
          '    - sprites/\n    - "sounds/" # quoted, with a comment\n',
    );
    write('packages/characters/knight/sprites/knight.png', base64Decode(png));
    write(
      'packages/characters/knight/sprites/knight.tileset.json',
      '{"image": "packages/knight/sprites/knight.png"}',
    );
    write('packages/characters/knight/sprites/deep/hidden.png', 'x');
    write('packages/characters/knight/sounds/hit.wav', 'wav');
    write('packages/characters/knight/notes.md', 'not shipped');
    // …and a package from pub's cache that ships nothing.
    write(
      'cache/pub/cache/hosted/pub.dev/plain-1.0.0/pubspec.yaml',
      'name: plain\n',
    );
    write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
          {
            'name': 'knight',
            'rootUri': '../packages/characters/knight',
            'packageUri': 'lib/',
          },
          {
            'name': 'plain',
            'rootUri': '../cache/pub/cache/hosted/pub.dev/plain-1.0.0',
            'packageUri': 'lib/',
          },
        ],
      }),
    );
    write('assets/sprites/hero.png', base64Decode(png));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('PackageAssetPaths', () {
    test('finds a package wherever it is installed', () {
      final paths = PackageAssetPaths.of(root);
      expect(
        paths.absolute('packages/knight/sprites/knight.png'),
        '$root/packages/characters/knight/sprites/knight.png',
      );
      expect(
        paths.file('packages/knight/sprites/knight.png').existsSync(),
        isTrue,
      );
      // Project paths, and unknown packages, stay under the project.
      expect(
        paths.absolute('assets/sprites/hero.png'),
        '$root/assets/sprites/hero.png',
      );
      expect(
        paths.absolute('packages/nobody/x.png'),
        '$root/packages/nobody/x.png',
      );
      expect(PackageAssetPaths.packageOf('packages/knight/a.png'), 'knight');
      expect(PackageAssetPaths.packageOf('assets/a.png'), isNull);
      expect(PackageAssetPaths.isPackageKey('packages/'), isFalse);
    });

    test('turns a file back into its key', () {
      final paths = PackageAssetPaths.of(root);
      expect(
        paths.keyFor('$root/packages/characters/knight/sprites/knight.png'),
        'packages/knight/sprites/knight.png',
      );
      expect(
        paths.keyFor(
          '$root/assets/sprites/hero.png'.replaceAll(
            '/',
            Platform.pathSeparator,
          ),
        ),
        'assets/sprites/hero.png',
      );
      expect(paths.keyFor(Directory.systemTemp.parent.path), isNull);
    });

    test('knows what ships: only the listed folders, not below', () {
      final paths = PackageAssetPaths.of(root);
      expect(paths.packages['knight']!.assetFolders, ['sprites/', 'sounds/']);
      expect(paths.ships('packages/knight/sprites/knight.png'), isTrue);
      expect(paths.ships('packages/knight/sounds/hit.wav'), isTrue);
      expect(paths.ships('packages/knight/sprites/deep/hidden.png'), isFalse);
      expect(paths.ships('packages/knight/notes.md'), isFalse);
      expect(paths.ships('packages/nobody/x.png'), isFalse);
      expect(
        paths.ships('assets/sprites/hero.png'),
        isNull,
        reason: "pubspec.yaml's business",
      );
      expect(paths.withAssets.map((p) => p.name), ['knight']);
      expect(
        paths.packages.containsKey('plain'),
        isFalse,
        reason: 'pub cache, no assets',
      );
    });

    test('lists the files packages ship', () {
      expect(PackageAssetPaths.of(root).packageFiles(), [
        'packages/knight/sounds/hit.wav',
        'packages/knight/sprites/knight.png',
        'packages/knight/sprites/knight.tileset.json',
      ]);
      expect(
        PackageAssetPaths.of(root).packageFiles(endings: ['.tileset.json']),
        ['packages/knight/sprites/knight.tileset.json'],
      );
    });

    test("the store's lockfile finds an item before pub has run", () async {
      File('$root/.dart_tool/package_config.json').deleteSync();
      write(
        'just_store.lock.json',
        jsonEncode({
          'schema': 1,
          'items': {
            'knight': {
              'version': '1.0.0',
              'kind': 'content',
              'origin': 'vendored',
              'path': 'packages/characters/knight',
            },
          },
        }),
      );
      final paths = PackageAssetPaths.of(root)..invalidate();
      expect(paths.packages['knight']!.fromStore, isTrue);
      expect(
        paths.file('packages/knight/sprites/knight.png').existsSync(),
        isTrue,
      );
    });

    test('pub-cache packages are read-only', () {
      write(
        'cache/pub/cache/hosted/pub.dev/plain-1.0.0/pubspec.yaml',
        'name: plain\nflutter:\n  assets:\n    - a/\n',
      );
      final paths = PackageAssetPaths.of(root)..invalidate();
      expect(paths.packages['plain']!.inPubCache, isTrue);
      expect(paths.isWritable('packages/plain/a/x.png'), isFalse);
      expect(paths.isWritable('packages/knight/sprites/x.png'), isTrue);
      expect(paths.isWritable('assets/x.png'), isTrue);
    });
  });

  testWidgets('the editor reads package files from disk', (tester) async {
    await tester.runAsync(() async {
      final loader = FileSpriteAssetLoader(root: root);
      final image = await loader.loadImage(
        'packages/knight/sprites/knight.png',
      );
      expect(image.width, 1);
      expect(
        await loader.readText('packages/knight/sprites/knight.tileset.json'),
        contains('"image"'),
      );
    });
  });

  test('validators see package files; pubspec parsing is shared', () {
    final scope = testScope();
    final context = ValidationContext(scope: scope, projectRoot: root);
    expect(context.fileExists('packages/knight/sprites/knight.png'), isTrue);
    expect(context.fileExists('packages/knight/sprites/gone.png'), isFalse);
    expect(
      context.readJson('packages/knight/sprites/knight.tileset.json')!['image'],
      'packages/knight/sprites/knight.png',
    );
    write(
      'pubspec.yaml',
      "name: app\nflutter:\n  assets:\n    - assets/sprites/\n    - 'assets/a.png'\n",
    );
    expect(BuiltInValidators.shippedAssets(context), [
      'assets/sprites/',
      'assets/a.png',
    ]);
    expect(
      context.packages.ships('packages/knight/sprites/knight.png'),
      isTrue,
    );
  });

  group('the Assets dock', () {
    late AssetIndex index;
    setUp(() async {
      index = AssetIndex(projectRoot: root);
      await index.scan();
    });
    tearDown(() => index.dispose());

    test('lists what packages ship under packages/', () {
      expect(index.hasPackages, isTrue);
      expect(index.childrenOf('packages').map((e) => e.path), [
        'packages/knight',
      ]);
      expect(index.childrenOf('packages/knight').map((e) => e.name), [
        'sounds',
        'sprites',
      ]);
      expect(index.childrenOf('packages/knight/sprites').map((e) => e.name), [
        'knight.png',
        'knight.tileset.json',
      ]);
      expect(
        index.entryAt('packages/knight/sprites/deep'),
        isNull,
        reason: 'not shipped',
      );
      expect(index.entryAt('packages/knight/notes.md'), isNull);
      final png = index.entryAt('packages/knight/sprites/knight.png')!;
      expect(png.isPackage, isTrue);
      expect(png.kind, AssetKind.image);
      expect(File(index.absolute(png.path)).existsSync(), isTrue);
      expect(
        index.search('knight').map((e) => e.path),
        contains('packages/knight/sprites/knight.png'),
      );
      expect(index.entryAt('assets/sprites/hero.png')!.isPackage, isFalse);
    });

    test(
      'package files cannot be renamed, duplicated, deleted or added to',
      () async {
        const key = 'packages/knight/sprites/knight.png';
        await expectLater(
          index.rename(key, 'x.png'),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          index.duplicate(key),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          index.trash(key),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          index.newFolder('packages/knight'),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          File(
            '$root/packages/characters/knight/sprites/knight.png',
          ).existsSync(),
          isTrue,
        );
      },
    );

    test('references inside package files are found', () async {
      expect(
        await AssetReferences.find(index, 'packages/knight/sprites/knight.png'),
        ['packages/knight/sprites/knight.tileset.json'],
      );
    });
  });

  test('scope.reloadAssets reaches whoever the plugin connected', () {
    final scope = testScope();
    final got = <String>[];
    scope.reloadAssets(['a']); // nothing connected yet: no error
    scope.assetReloader = got.addAll;
    scope.reloadAssets(['packages/knight/sprites/knight.png', 'x.json']);
    expect(got, ['packages/knight/sprites/knight.png', 'x.json']);
  });

  group('messages for long tasks', () {
    late EditorSnackBarController c;
    setUp(() => c = EditorSnackBarController());
    tearDown(() => c.dispose());

    test(
      'progress is shown, and repeats of one step update it in place',
      () async {
        final task = StreamController<EditorSnackBarStep>();
        final snack = c.showSnackBar(
          EditorSnackBarEntry(
            message: 'Installing',
            progressStream: task.stream,
          ),
        );
        expect(snack.progress, isNull);
        task.add(
          const EditorSnackBarStep(message: 'Downloading', progress: 0.25),
        );
        task.add(
          const EditorSnackBarStep(message: 'Downloading', progress: 0.5),
        );
        task.add(const EditorSnackBarStep(message: 'Checking'));
        await Future<void>.delayed(Duration.zero);
        expect(snack.steps.map((s) => s.message), ['Downloading', 'Checking']);
        expect(snack.progress, 0.5);
        await task.close();
        await Future<void>.delayed(Duration.zero);
        expect(snack.progress, 1);
      },
    );

    test('a task can be cancelled from its message', () async {
      var cancelled = false;
      final task = StreamController<EditorSnackBarStep>();
      final snack = c.showSnackBar(
        EditorSnackBarEntry(
          message: 'Installing',
          progressStream: task.stream,
          onCancel: () => cancelled = true,
        ),
      );
      snack.cancel();
      expect(cancelled, isTrue);
      await task.close();
    });

    testWidgets('a sticky message stays', (tester) async {
      c.showSnackBar(
        const EditorSnackBarEntry(message: 'Restart the editor', sticky: true),
      );
      await tester.pump(const Duration(minutes: 1));
      expect(c.visible.single.entry.message, 'Restart the editor');
    });
  });
}
