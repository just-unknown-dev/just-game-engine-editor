import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'component_codegen_runner.dart';
import 'component_source_index.dart';

Future<ComponentCodegenResult> runComponentIndexScanImpl({
  ComponentCodegenLog? onLog,
}) async {
  final workspaceRoot = Directory.current.path;
  final editorRoot = p.join(
    workspaceRoot,
    'packages',
    'just_game_engine_editor',
    'lib',
    'src',
    'core',
    'ecs',
    'components',
  );
  final projectRoot = p.join(workspaceRoot, 'lib');

  final editorDir = Directory(editorRoot);
  final projectDir = Directory(projectRoot);
  if (!editorDir.existsSync()) {
    const output =
        'Unable to refresh components: editor component root was not found.';
    onLog?.call(output);
    return const ComponentCodegenResult(success: false, output: output);
  }
  if (!projectDir.existsSync()) {
    const output =
        'Unable to refresh components: project lib root was not found.';
    onLog?.call(output);
    return const ComponentCodegenResult(success: false, output: output);
  }

  Process? process;
  final output = StringBuffer();
  try {
    process = await Process.start(
      'dart',
      <String>[
        'run',
        './packages/just_code_gen/bin/just_code_gen.dart',
        'scan',
        '--editor-root',
        editorRoot,
        '--project-root',
        projectRoot,
      ],
      runInShell: true,
      workingDirectory: workspaceRoot,
    );
  } catch (error) {
    final text = 'Failed to start just_code_gen scan: $error';
    onLog?.call(text);
    return ComponentCodegenResult(success: false, output: text);
  }

  final stdoutDone = process.stdout.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    onLog?.call(chunk);
  }).asFuture<void>();

  final stderrDone = process.stderr.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    onLog?.call(chunk);
  }).asFuture<void>();

  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  final exitCode = await process.exitCode;
  final text = output.toString().trim();
  if (exitCode == 0 && text.isNotEmpty) {
    ComponentSourceIndex.instance.updateFromScanJson(text);
  }

  return ComponentCodegenResult(
    success: exitCode == 0,
    output: text.isEmpty
        ? (exitCode == 0
              ? 'just_code_gen scan completed successfully.'
              : 'just_code_gen scan failed with exit code $exitCode.')
        : text,
    exitCode: exitCode,
  );
}

Future<ComponentCodegenResult> runComponentGenerateOneImpl(
  String sourcePath, {
  required bool editorScope,
  ComponentCodegenLog? onLog,
}) async {
  final workspaceRoot = Directory.current.path;
  final output = StringBuffer();

  Process? process;
  try {
    process = await Process.start(
      'dart',
      <String>[
        'run',
        './packages/just_code_gen/bin/just_code_gen.dart',
        'generate-one',
        '--source',
        sourcePath,
        '--scope',
        editorScope ? 'editor' : 'project',
      ],
      runInShell: true,
      workingDirectory: workspaceRoot,
    );
  } catch (error) {
    final text = 'Failed to start just_code_gen generate-one: $error';
    onLog?.call(text);
    return ComponentCodegenResult(success: false, output: text);
  }

  final stdoutDone = process.stdout.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    onLog?.call(chunk);
  }).asFuture<void>();

  final stderrDone = process.stderr.transform(utf8.decoder).listen((chunk) {
    output.write(chunk);
    onLog?.call(chunk);
  }).asFuture<void>();

  await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
  final exitCode = await process.exitCode;
  final text = output.toString().trim();

  return ComponentCodegenResult(
    success: exitCode == 0,
    output: text.isEmpty
        ? (exitCode == 0
              ? 'just_code_gen generate-one completed successfully.'
              : 'just_code_gen generate-one failed with exit code $exitCode.')
        : text,
    exitCode: exitCode,
  );
}
