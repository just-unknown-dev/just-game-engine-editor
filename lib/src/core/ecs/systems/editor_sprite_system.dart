import 'package:just_game_engine/just_game_engine.dart';

/// Bridges [SpriteComponent.spritePath] → [RenderableComponent] in the editor.
///
/// The engine's [RenderSystem] only processes [RenderableComponent] entities.
/// [SpriteComponent] is a plain data container — this system watches for path
/// changes and (re-)loads the image, then installs a [Sprite] wrapped in a
/// [RenderableComponent] on the entity so it becomes visible in the viewport.
class EditorSpriteSystem extends System {
  final Map<Entity, String> _trackedPaths = {};
  final Set<Entity> _loading = {};

  @override
  int get priority => SystemPriorities.animation - 1;

  @override
  List<Type> get requiredComponents => [TransformComponent, SpriteComponent];

  @override
  void update(double deltaTime) {
    forEach((entity) {
      final sc = entity.getComponent<SpriteComponent>()!;
      final path = sc.spritePath.trim();

      if (_loading.contains(entity)) return;
      if (_trackedPaths[entity] == path) return;

      _trackedPaths[entity] = path;

      if (path.isEmpty) {
        entity.removeComponent<RenderableComponent>();
        return;
      }

      _loading.add(entity);
      _loadAndApply(entity, path);
    });
  }

  Future<void> _loadAndApply(Entity entity, String path) async {
    try {
      final image = await Sprite.loadImageFromAsset(path);

      // Re-check: entity may have been removed or path may have changed.
      final sc = entity.getComponent<SpriteComponent>();
      if (sc == null || sc.spritePath.trim() != path) {
        _loading.remove(entity);
        return;
      }

      final renderable = Sprite(
        image: image,
        flipX: sc.flipX,
        flipY: sc.flipY,
        tint: sc.tint,
      );

      final existing = entity.getComponent<RenderableComponent>();
      if (existing != null) {
        existing.renderable = renderable;
      } else {
        entity.addComponent(
          RenderableComponent(renderable: renderable, syncTransform: true),
        );
      }
    } catch (_) {
      // Path invalid or asset missing — clear tracking so the user can
      // correct the path and the system will retry automatically.
      _trackedPaths.remove(entity);
    } finally {
      _loading.remove(entity);
    }
  }
}
