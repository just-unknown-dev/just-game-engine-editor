import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:just_game_engine/just_game_engine.dart';

/// Drives [AnimatedSpriteComponent] in the editor.
///
/// Each frame this system:
///  1. Loads / reloads the sprite-sheet when [spritePath] changes.
///  2. Loads the JSON config when [jsonPath] changes.
///  3. Seeds [playOnStart] the first time the component is seen.
///  4. Advances [elapsed] and [frameIndex] according to FPS.
///  5. Syncs the [Sprite.sourceRect] on the entity's [RenderableComponent].
///  6. Interpolates [TransformKeyframe]s onto the entity's [TransformComponent].
///  7. Handles cross-fade blending between clips.
class EditorAnimatedSpriteSystem extends System {
  final Map<Entity, String> _loadedSpritePaths = {};
  final Map<Entity, String> _loadedJsonPaths = {};
  final Set<Entity> _loadingSprite = {};
  final Set<Entity> _loadingJson = {};

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => [
    TransformComponent,
    AnimatedSpriteComponent,
  ];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final asc = entity.getComponent<AnimatedSpriteComponent>()!;

      _handleJsonLoad(entity, asc);
      _handleSpriteLoad(entity, asc);
      _initPlayOnStart(asc);

      if (asc.isPlaying) _advance(asc, deltaTime);

      _syncSourceRect(entity, asc);
      _applyKeyframes(entity, asc);
    });
  }

  // ── JSON config loading ──────────────────────────────────────────────────

  void _handleJsonLoad(Entity entity, AnimatedSpriteComponent asc) {
    final path = asc.jsonPath.trim();
    if (path.isEmpty) return;
    if (_loadedJsonPaths[entity] == path) return;
    if (_loadingJson.contains(entity)) return;

    _loadedJsonPaths[entity] = path;
    _loadingJson.add(entity);
    _loadJson(entity, path);
  }

  Future<void> _loadJson(Entity entity, String path) async {
    try {
      final base = Directory.current.path.replaceAll(r'\', '/');
      final file = File('$base/$path');
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      final asc = entity.getComponent<AnimatedSpriteComponent>();
      if (asc == null || asc.jsonPath.trim() != path) return;
      asc.loadFromJson(json);
    } catch (_) {
      _loadedJsonPaths.remove(entity);
    } finally {
      _loadingJson.remove(entity);
    }
  }

  // ── Sprite sheet loading ─────────────────────────────────────────────────

  void _handleSpriteLoad(Entity entity, AnimatedSpriteComponent asc) {
    final path = asc.spritePath.trim();
    if (_loadedSpritePaths[entity] == path) return;
    if (_loadingSprite.contains(entity)) return;

    _loadedSpritePaths[entity] = path;

    if (path.isEmpty) {
      entity.removeComponent<RenderableComponent>();
      return;
    }

    _loadingSprite.add(entity);
    _loadSprite(entity, path, asc);
  }

  Future<void> _loadSprite(
    Entity entity,
    String path,
    AnimatedSpriteComponent asc,
  ) async {
    try {
      final image = await Sprite.loadImageFromAsset(path);

      final current = entity.getComponent<AnimatedSpriteComponent>();
      if (current == null || current.spritePath.trim() != path) return;

      final sprite = Sprite(
        image: image,
        sourceRect: Rect.fromLTWH(
          0,
          0,
          asc.frameWidth.toDouble(),
          asc.frameHeight.toDouble(),
        ),
      );

      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = sprite;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: sprite, syncTransform: true),
        );
      }
    } catch (_) {
      _loadedSpritePaths.remove(entity);
    } finally {
      _loadingSprite.remove(entity);
    }
  }

  // ── Initialisation ───────────────────────────────────────────────────────

  void _initPlayOnStart(AnimatedSpriteComponent asc) {
    if (asc.initialized) return;
    // If a JSON file is set but clips haven't loaded yet, wait.
    if (asc.jsonPath.trim().isNotEmpty && asc.clips.isEmpty) return;

    asc.initialized = true;
    if (!asc.playOnStart || asc.clips.isEmpty) return;
    if (asc.activeClip.isEmpty) asc.activeClip = asc.clips.keys.first;
    asc.isPlaying = true;
  }

  // ── Frame advancement ────────────────────────────────────────────────────

  void _advance(AnimatedSpriteComponent asc, double dt) {
    // Advance blend timer
    if (asc.blendingToClip != null) {
      asc.blendElapsed += dt;
      if (asc.blendElapsed >= asc.blendDuration) {
        asc.activeClip = asc.blendingToClip!;
        asc.blendingToClip = null;
        asc.blendElapsed = 0.0;
        asc.elapsed = 0.0;
        asc.frameIndex = 0;
      }
    }

    final clip = asc.activeClipData;
    if (clip == null || clip.frames.isEmpty) return;

    final fps = (clip.fps ?? asc.defaultFps).clamp(0.1, 240.0);
    final frameDuration = 1.0 / fps;
    final clipLoop = clip.loop ?? asc.loop;
    final clipDuration = clip.frames.length * frameDuration;

    asc.elapsed += dt;

    if (!clipLoop && asc.elapsed >= clipDuration) {
      asc.elapsed = clipDuration - 0.0001;
      asc.isPlaying = false;
    } else if (clipLoop && asc.elapsed >= clipDuration) {
      asc.elapsed = asc.elapsed % clipDuration;
    }

    asc.frameIndex = (asc.elapsed / frameDuration)
        .floor()
        .clamp(0, clip.frames.length - 1);
  }

  // ── Source rect sync ─────────────────────────────────────────────────────

  void _syncSourceRect(Entity entity, AnimatedSpriteComponent asc) {
    final rc = entity.getComponent<RenderableComponent>();
    if (rc == null) return;
    final sprite = rc.renderable;
    if (sprite is! Sprite) return;

    sprite.sourceRect = Rect.fromLTWH(
      (asc.currentColumn * asc.frameWidth).toDouble(),
      (asc.currentRow * asc.frameHeight).toDouble(),
      asc.frameWidth.toDouble(),
      asc.frameHeight.toDouble(),
    );
  }

  // ── Transform keyframe interpolation ─────────────────────────────────────

  void _applyKeyframes(Entity entity, AnimatedSpriteComponent asc) {
    final clip = asc.activeClipData;
    if (clip == null || clip.keyframes.isEmpty) return;

    final transform = entity.getComponent<TransformComponent>();
    if (transform == null) return;

    _interpolateAtTime(transform, clip.keyframes, asc.elapsed);

    // Cross-blend: lerp current pose toward the next clip's t=0 pose
    if (asc.blendingToClip != null) {
      final nextClip = asc.clips[asc.blendingToClip!];
      if (nextClip != null && nextClip.keyframes.isNotEmpty) {
        final blendT =
            (asc.blendElapsed / asc.blendDuration).clamp(0.0, 1.0);
        _blendToward(transform, nextClip.keyframes.first, blendT);
      }
    }
  }

  void _interpolateAtTime(
    TransformComponent transform,
    List<TransformKeyframe> keyframes,
    double t,
  ) {
    TransformKeyframe? prev;
    TransformKeyframe? next;

    for (final kf in keyframes) {
      if (kf.time <= t) {
        prev = kf;
      } else {
        next ??= kf;
      }
    }

    if (prev == null && next == null) return;

    if (prev == null) {
      _applyValues(transform, next!, 1.0, next);
      return;
    }
    if (next == null) {
      _applyValues(transform, prev, 1.0, prev);
      return;
    }

    final span = next.time - prev.time;
    final localT =
        span > 0 ? ((t - prev.time) / span).clamp(0.0, 1.0) : 1.0;
    final easedT = prev.easing.apply(localT);
    _applyValues(transform, prev, easedT, next);
  }

  void _applyValues(
    TransformComponent transform,
    TransformKeyframe from,
    double t,
    TransformKeyframe to,
  ) {
    double lerp(double? a, double? b, double fallback) {
      if (a == null && b == null) return fallback;
      final fa = a ?? fallback;
      final fb = b ?? fallback;
      return fa + (fb - fa) * t;
    }

    final newRot = lerp(from.rotation, to.rotation, transform.rotation);
    final newSX = lerp(from.scaleX, to.scaleX, transform.scale.x);
    final newSY = lerp(from.scaleY, to.scaleY, transform.scale.y);

    if (from.rotation != null || to.rotation != null) {
      transform.rotation = newRot;
    }
    if (from.scaleX != null || to.scaleX != null ||
        from.scaleY != null || to.scaleY != null) {
      transform.scale = Vector3(newSX, newSY, transform.scale.z);
    }
  }

  void _blendToward(
    TransformComponent transform,
    TransformKeyframe target,
    double t,
  ) {
    if (target.rotation != null) {
      transform.rotation +=
          (target.rotation! - transform.rotation) * t;
    }
    if (target.scaleX != null) {
      transform.scale = Vector3(
        transform.scale.x + (target.scaleX! - transform.scale.x) * t,
        transform.scale.y,
        transform.scale.z,
      );
    }
    if (target.scaleY != null) {
      transform.scale = Vector3(
        transform.scale.x,
        transform.scale.y + (target.scaleY! - transform.scale.y) * t,
        transform.scale.z,
      );
    }
  }
}
