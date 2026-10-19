import 'dart:math' as math;

import 'package:just_editor_core/io.dart';
import 'package:just_editor_core/just_editor_core.dart'
    show PackageAssetPaths, ProjectFiles;
import 'package:just_game_engine/graphics_3d.dart';

/// A model's own materials, written out as material files of the project:
/// what an artist painted in the modelling tool, to be changed, shared and
/// made variants of.
abstract final class ModelMaterials {
  /// Writes each material of the model at [path] (a `.glb` or `.gltf`,
  /// project-relative) under [root] as a material file beside it —
  /// `<model>_<material>.material.json` — its images as files in
  /// `<model>_textures/` (an image the model reads from beside it is used
  /// where it is, when that is in the project; one outside it — a `..` out
  /// of it — is copied in). Never writes over a file there already. Gives
  /// the material files made, in the model's order.
  static Future<List<String>> extract(String root, String path) async {
    final file = File(PackageAssetPaths.of(root).absolute(path));
    final folder = file.parent.path;
    final data = await loadModelData(
      await file.readAsBytes(),
      name: path,
      fetch: (uri) => File('$folder/$uri').readAsBytes(),
    );
    final slash = path.lastIndexOf('/');
    final dir = slash < 0 ? '' : path.substring(0, slash);
    final name = path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final model = _safe(dot < 0 ? name : name.substring(0, dot));
    String at(String rel) => dir.isEmpty ? rel : '$dir/$rel';

    // Each image written (or found) once.
    final images = <int, String>{};
    Future<String> imageOf(TextureRef? ref) async {
      if (ref == null || ref.texture >= data.textures.length) return '';
      final index = data.textures[ref.texture].image;
      if (index == null || index >= data.images.length) return '';
      final known = images[index];
      if (known != null) return known;
      final image = data.images[index];
      // A file beside the model: used where it is — when that is inside
      // the project; one a `..` takes out of it is copied in below.
      final uri = image.name;
      if (uri != null && !uri.startsWith('data:')) {
        final rel = Uri.decodeComponent(uri);
        final there = _normal(at(rel));
        if (ProjectFiles.isContained(there) &&
            File('$folder/$rel').existsSync()) {
          return images[index] = there;
        }
      }
      final ending = switch (image.mimeType) {
        'image/jpeg' => '.jpg',
        'image/webp' => '.webp',
        _ => '.png',
      };
      final stem = uri == null || uri.startsWith('data:')
          ? 'image_$index'
          : _safe(uri.split('/').last.split('.').first);
      final out = _free(root, at('${model}_textures/$stem'), ending);
      // Whole or not at all, its folder made when missing.
      await ProjectFiles.writeBytes('$root/$out', image.bytes);
      return images[index] = out;
    }

    final made = <String>[];
    for (var i = 0; i < data.materials.length; i++) {
      final m = data.materials[i];
      final own = m.name == null || m.name!.trim().isEmpty
          ? 'material_$i'
          : _safe(m.name!);
      final colour = m.baseColorTexture;
      final (r, g, b, a) = m.baseColor;
      final (er, eg, eb) = m.emissive;
      final glow = math.max(er, math.max(eg, eb));
      final material = MaterialFile(
        color: _argb(r, g, b, a),
        metallic: m.metallic.clamp(0.0, 1.0),
        roughness: m.roughness.clamp(0.0, 1.0),
        emission: glow <= 0 ? 0xFF000000 : _argb(er, eg, eb, 1),
        emissionStrength: math.max(0, m.emissiveStrength),
        alpha: switch (m.alphaMode) {
          AlphaMode.mask => MaterialAlpha.cutout,
          AlphaMode.blend => MaterialAlpha.blend,
          AlphaMode.opaque => MaterialAlpha.opaque,
        },
        alphaCutoff: m.alphaCutoff.clamp(0.0, 1.0),
        doubleSided: m.doubleSided,
        unlit: m.unlit,
        colorMap: await imageOf(colour),
        metalRoughMap: await imageOf(m.metallicRoughnessTexture),
        normalMap: await imageOf(m.normalTexture),
        normalScale: m.normalScale,
        occlusionMap: await imageOf(m.occlusionTexture),
        occlusionStrength: m.occlusionStrength.clamp(0.0, 1.0),
        emissionMap: await imageOf(m.emissiveTexture),
        tilingX: colour?.scale.$1 ?? 1,
        tilingY: colour?.scale.$2 ?? 1,
        offsetX: colour?.offset.$1 ?? 0,
        offsetY: colour?.offset.$2 ?? 0,
        rotation: (colour?.rotation ?? 0) * 180 / math.pi,
      );
      final out = _free(root, at('${model}_$own'), MaterialFile.ending);
      await ProjectFiles.writeString('$root/$out', material.encode());
      made.add(out);
    }
    return made;
  }

  // Linear colour as sRGB ARGB.
  static int _argb(double r, double g, double b, double a) {
    int srgb(double c) {
      final v = c.clamp(0.0, 1.0);
      final s = v <= 0.0031308
          ? v * 12.92
          : 1.055 * math.pow(v, 1 / 2.4) - 0.055;
      return (s * 255).round().clamp(0, 255);
    }

    final alpha = (a.clamp(0.0, 1.0) * 255).round();
    return (alpha << 24) | (srgb(r) << 16) | (srgb(g) << 8) | srgb(b);
  }

  // [path] with `.` and `..` folded away.
  static String _normal(String path) {
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part == '..' && out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        out.add(part);
      }
    }
    return out.join('/');
  }

  static String _safe(String name) {
    final s = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp('_+'), '_');
    return s.isEmpty ? 'material' : s;
  }

  static String _free(String root, String stem, String ending) {
    var n = 1;
    String path() => '$stem${n == 1 ? '' : '_$n'}$ending';
    while (File('$root/${path()}').existsSync()) {
      n++;
    }
    return path();
  }
}
