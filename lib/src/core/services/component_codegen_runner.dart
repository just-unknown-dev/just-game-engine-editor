import 'component_codegen_runner_stub.dart'
    if (dart.library.io) 'component_codegen_runner_io.dart';

typedef ComponentCodegenLog = void Function(String line);

class ComponentCodegenResult {
  const ComponentCodegenResult({
    required this.success,
    required this.output,
    this.exitCode,
  });

  final bool success;
  final String output;
  final int? exitCode;
}

Future<ComponentCodegenResult> runComponentIndexScan({
  ComponentCodegenLog? onLog,
}) async {
  return runComponentIndexScanImpl(onLog: onLog);
}

Future<ComponentCodegenResult> runComponentGenerateOne(
  String sourcePath, {
  required bool editorScope,
  ComponentCodegenLog? onLog,
}) async {
  return runComponentGenerateOneImpl(
    sourcePath,
    editorScope: editorScope,
    onLog: onLog,
  );
}
