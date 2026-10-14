import 'package:flutter/material.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final engine = Engine();
  // The editor attaches to a ready engine: its world and camera exist.
  await engine.initialize();
  final plugin = await JustGameEditorPlugin.register(engine: engine);
  // The game loop drives the editor too: Play, autosave and the 3-D fly
  // keys all run on its frames.
  engine.start();

  runApp(_ExampleApp(engine: engine, plugin: plugin));
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp({required this.engine, required this.plugin});

  final Engine engine;
  final JustGameEditorPlugin? plugin;

  @override
  Widget build(BuildContext context) {
    // JustGameEngineEditor puts the editor overlay over the GameWidget and
    // routes focus between them. When plugin is null (release builds, or a
    // platform the editor does not run on) it is a plain GameWidget.
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
