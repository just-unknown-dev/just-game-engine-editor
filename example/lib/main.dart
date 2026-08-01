import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine();
  final plugin = await JustGameEditorPlugin.register(engine: engine);

  runApp(_ExampleApp(engine: engine, plugin: plugin));
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp({required this.engine, required this.plugin});

  final Engine engine;
  final JustGameEditorPlugin? plugin;

  @override
  Widget build(BuildContext context) {
    // GameEditorAdapter automatically composes GameWidget + JustGameEditorOverlay
    // and handles focus routing, update ticker, and render hook lifecycle.
    // When plugin is null (release builds) it renders a plain GameWidget.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: JustGameEngineEditor(
          engine: engine,
          plugin: plugin,
          showFPS: true,
          showTerminal: true,
        ),
      ),
    );
  }
}
