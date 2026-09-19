// Pure geometry used by the Level Designer's tools. No World, no Engine — if
// any of this needs one, the layering has gone wrong.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';

void main() {
  group('snapping', () {
    test('snapValue rounds to the nearest multiple', () {
      expect(DesignerGeometry.snapValue(31, 32), 32);
      expect(DesignerGeometry.snapValue(47, 32), 32);
      expect(DesignerGeometry.snapValue(49, 32), 64);
      expect(DesignerGeometry.snapValue(-17, 32), -32);
    });

    test('a step of zero leaves the value alone', () {
      expect(DesignerGeometry.snapValue(17.3, 0), 17.3);
    });

    test('snapRectEdges puts every edge on a grid line', () {
      final snapped = DesignerGeometry.snapRectEdges(
        const Rect.fromLTRB(5, 7, 99, 101),
        32,
      );

      for (final edge in [
        snapped.left,
        snapped.top,
        snapped.right,
        snapped.bottom,
      ]) {
        expect(edge % 32, 0, reason: '$edge should sit on the grid');
      }
    });

    test('a sub-cell drag becomes one cell rather than nothing', () {
      final snapped = DesignerGeometry.snapRectEdges(
        const Rect.fromLTRB(10, 10, 12, 12),
        32,
      );

      expect(snapped.width, 32);
      expect(snapped.height, 32);
    });

    test('edge snapping beats centre snapping for odd sizes', () {
      // A 100-wide platform on a 32 grid: its centre can never sit on a grid
      // line, but its left edge can — and the edges are what have to line up
      // for platforms to tile against each other.
      const size = Size(100, 32);
      final center = DesignerGeometry.snapCenterForSize(
        const Offset(50, 50),
        size,
        32,
      );
      final rect = Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      );

      expect(rect.left % 32, 0);
    });
  });

  group('greedyMerge', () {
    test('an empty set merges to nothing', () {
      expect(DesignerGeometry.greedyMerge({}), isEmpty);
    });

    test('a single cell becomes a 1x1 rect', () {
      final rects = DesignerGeometry.greedyMerge({const Point2(3, 4)});

      expect(rects, hasLength(1));
      expect(rects.single, const Rect.fromLTWH(3, 4, 1, 1));
    });

    test('a horizontal run becomes one rect', () {
      final rects = DesignerGeometry.greedyMerge({
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(2, 0),
        const Point2(3, 0),
      });

      expect(rects, hasLength(1));
      expect(rects.single, const Rect.fromLTWH(0, 0, 4, 1));
    });

    test('a solid block becomes one rect', () {
      final cells = <Point2>{};
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 6; x++) {
          cells.add(Point2(x, y));
        }
      }

      final rects = DesignerGeometry.greedyMerge(cells);

      expect(
        rects,
        hasLength(1),
        reason: '24 painted cells must not become 24 physics bodies',
      );
      expect(rects.single, const Rect.fromLTWH(0, 0, 6, 4));
    });

    test('covers every input cell exactly once', () {
      // An L shape, which cannot be one rectangle.
      final cells = <Point2>{
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(0, 1),
        const Point2(0, 2),
        const Point2(1, 2),
        const Point2(2, 2),
      };

      final rects = DesignerGeometry.greedyMerge(cells);

      final covered = <Point2>{};
      for (final rect in rects) {
        for (var y = 0; y < rect.height; y++) {
          for (var x = 0; x < rect.width; x++) {
            final cell = Point2(rect.left.toInt() + x, rect.top.toInt() + y);
            expect(
              covered.add(cell),
              isTrue,
              reason: 'overlapping rects would double up colliders at $cell',
            );
          }
        }
      }

      expect(covered, equals(cells));
      expect(rects.length, lessThan(cells.length), reason: 'some merging');
    });

    test('is deterministic, so saved scenes stay stable', () {
      final cells = <Point2>{
        const Point2(2, 1),
        const Point2(0, 0),
        const Point2(1, 0),
        const Point2(1, 1),
        const Point2(0, 1),
        const Point2(2, 0),
      };

      final first = DesignerGeometry.greedyMerge(Set.of(cells));
      final second = DesignerGeometry.greedyMerge(Set.of(cells));

      expect(first, equals(second));
    });

    test('disjoint islands stay separate', () {
      final rects = DesignerGeometry.greedyMerge({
        const Point2(0, 0),
        const Point2(10, 10),
      });

      expect(rects, hasLength(2));
    });
  });

  group('cells', () {
    test('cellAt floors toward negative infinity', () {
      expect(
        DesignerGeometry.cellAt(const Offset(33, 65), 32),
        const Point2(1, 2),
      );
      expect(
        DesignerGeometry.cellAt(const Offset(-1, -1), 32),
        const Point2(-1, -1),
      );
    });

    test('cellsIn covers a rect spanning several cells', () {
      final cells = DesignerGeometry.cellsIn(
        const Rect.fromLTWH(0, 0, 64, 64),
        32,
      );

      expect(cells, hasLength(4));
      expect(cells, contains(const Point2(0, 0)));
      expect(cells, contains(const Point2(1, 1)));
    });

    test('a zero-size rect still yields the cell it sits in', () {
      final cells = DesignerGeometry.cellsIn(
        const Rect.fromLTWH(40, 40, 0, 0),
        32,
      );

      expect(cells, hasLength(1));
      expect(cells.single, const Point2(1, 1));
    });
  });

  group('measurement', () {
    test('distance and angle', () {
      expect(
        DesignerGeometry.distance(Offset.zero, const Offset(3, 4)),
        closeTo(5, 1e-9),
      );
      expect(
        DesignerGeometry.angleDegrees(Offset.zero, const Offset(1, 0)),
        closeTo(0, 1e-9),
      );
      // +Y is down in screen space, so due "south" is +90.
      expect(
        DesignerGeometry.angleDegrees(Offset.zero, const Offset(0, 1)),
        closeTo(90, 1e-9),
      );
    });
  });
}
