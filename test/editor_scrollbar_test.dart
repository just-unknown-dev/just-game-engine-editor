// The editor's scroll bars show whenever a list holds more than it shows —
// not only while it scrolls — and never twice.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)),
);

void main() {
  testWidgets('a long list shows its thumb before it is scrolled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EditorScrollbar(
          builder: (_, scroll) => ListView(
            controller: scroll,
            children: [for (var i = 0; i < 40; i++) Text('row $i')],
          ),
        ),
      ),
    );
    await tester.pump();
    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
  });

  testWidgets('on the desktop there is one bar, not the default as well', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      _host(
        EditorScrollbar(
          builder: (_, scroll) => ListView(
            controller: scroll,
            children: [for (var i = 0; i < 40; i++) Text('row $i')],
          ),
        ),
      ),
    );
    await tester.pump();
    // Material draws its bar as a subclass of RawScrollbar.
    expect(find.byWidgetPredicate((w) => w is RawScrollbar), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('something scrolling both ways has a bar on each edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        EditorScrollbar2D(
          builder: (_, vertical, horizontal) => SingleChildScrollView(
            controller: vertical,
            child: SingleChildScrollView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              child: const SizedBox(width: 800, height: 800),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final bars = tester.widgetList<Scrollbar>(find.byType(Scrollbar)).toList();
    expect(bars, hasLength(2));
    expect(bars.every((b) => b.thumbVisibility == true), isTrue);
  });
}
