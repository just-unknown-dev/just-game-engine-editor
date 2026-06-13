import 'component_codegen_runner.dart';

Future<ComponentCodegenResult> runComponentIndexScanImpl({
  ComponentCodegenLog? onLog,
}) async {
  const message =
      'Component refresh via just_code_gen is only supported on desktop targets.';
  onLog?.call(message);
  return const ComponentCodegenResult(success: false, output: message);
}

Future<ComponentCodegenResult> runComponentGenerateOneImpl(
  String sourcePath, {
  required bool editorScope,
  ComponentCodegenLog? onLog,
}) async {
  const message =
      'Component generation via just_code_gen is only supported on desktop targets.';
  onLog?.call(message);
  return const ComponentCodegenResult(success: false, output: message);
}
