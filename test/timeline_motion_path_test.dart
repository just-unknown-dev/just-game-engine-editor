// Motion paths: where the open timeline takes things, and dragging a key's
// dot in the viewport.

import 'package:flutter_test/flutter_test.dart';
import 'package:just_game_engine/just_game_engine.dart';
import 'package:just_game_engine_editor/just_game_engine_editor.dart';
import 'package:just_game_engine_editor/src/ui/timeline/motion_path.dart';
import 'package:just_game_engine_editor/src/ui/timeline/timeline_session.dart';

import 'support/test_scope.dart';

TimelineKey _k(double t, double v) =>
    TimelineKey(time: t, value: v, interpolation: KeyInterpolation.linear);

PropertyTrack _position(
  String channel,
  List<TimelineKey> keys, {
  PropertyTrackMode mode = PropertyTrackMode.relative,
  TrackBinding binding = TrackBinding.owner,
}) => PropertyTrack(
  component: 'TransformComponent',
  field: 'position',
  channel: channel,
  mode: mode,
  binding: binding,
  curve: KeyCurve(keys),
);

void main() {
  setUpAll(registerCoreCodecs);

  late EditorScope scope;
  late TimelineSession s;
  late Entity lift;

  setUp(() async {
    scope = testScope();
    s = TimelineSession(scope, root: '.');
    addTearDown(s.dispose);
    scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(-50, -50, 0)),
    ], name: 'Bird');
    lift = scope.world.createEntityWithComponents([
      TransformComponent(position: Vector3(100, 200, 0)),
      TimelinePlayerComponent(
        inline: TimelineAsset(
          duration: 2,
          fps: 10,
          tracks: [
            _position('x', [_k(0, 0), _k(2, 80)]),
            _position('y', [_k(0, 0), _k(1, -60), _k(2, 0)]),
            _position(
              'x',
              [_k(0, 0), _k(2, 500)],
              mode: PropertyTrackMode.absolute,
              binding: const TrackBinding.name('Bird'),
            ),
            PropertyTrack(
              component: 'TransformComponent',
              field: 'rotation',
              curve: KeyCurve([_k(0, 0)]),
            ),
          ],
        ),
      ),
    ], name: 'Lift');
    await s.follow(lift);
  });

  test('one path per bound entity, from where the scene has it', () {
    final paths = MotionPath.of(s);
    expect(paths, hasLength(2));
    final own = paths.first, bird = paths.last;
    expect(own.entity, lift);
    expect(own.keyTimes, [0, 1, 2], reason: 'the key times of both channels');
    expect(own.at(0), const Offset(100, 200));
    expect(own.at(1), const Offset(140, 140));
    expect(own.at(2), const Offset(180, 200));

    // Absolute x, no y track: y stays where the bird is.
    expect(bird.at(1), const Offset(250, -50));

    // A preview moves the transform; the path stays on the scene's value.
    s.scrubTo(1);
    expect(lift.getComponent<TransformComponent>()!.position.x, 140);
    expect(MotionPath.of(s).first.at(0), const Offset(100, 200));
  });

  test('dragging a dot keys both channels at that time, as one step', () {
    final path = MotionPath.of(s).first;
    final start = s.beginDrag()!;
    s.dragPathPoint(start, path, 1, const Offset(150, 120));
    s.dragPathPoint(start, path, 1, const Offset(160, 100));
    s.endDrag(start);

    final x = s.asset.value!.propertyTracks.first.curve;
    final y = s.asset.value!.propertyTracks.elementAt(1).curve;
    expect(x.keys.map((k) => k.time), [0, 1, 2], reason: 'x gained a key at 1');
    expect(x.numberAt(1), 60, reason: '160 as an offset from 100');
    expect(y.numberAt(1), -100);
    expect(MotionPath.of(s).first.at(1), const Offset(160, 100));

    s.undo();
    expect(s.asset.value!.propertyTracks.first.curve.keys, hasLength(2));
    expect(s.canUndo, isFalse);
  });
}
