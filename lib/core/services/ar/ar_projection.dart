import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

/// The camera's view + projection matrices for ONE moment in time, as shipped
/// by the vendored plugin's `getCameraProjection` method channel (see the
/// patches in third_party/ar_flutter_plugin_2: ArView.kt and IosARView.swift).
///
/// [view] is world→eye (the inverse of the camera pose), [proj] is eye→clip
/// (perspective). Both are column-major, matching vector_math's [Matrix4].
/// One query serves any number of [worldToScreen] projections, so callers can
/// fetch this once per burst/frame and project many objects for free.
class ArCameraProjection {
  final Matrix4 view;
  final Matrix4 proj;

  const ArCameraProjection({required this.view, required this.proj});
}

/// How far outside the normalized device cube a point may fall (per axis)
/// before [worldToScreen] gives up instead of clamping to the screen edge.
/// 1.2 = up to 20% overshoot still snaps to the nearest edge, which keeps FX
/// for "just off screen" pops pinned believably at the border.
const double kArNdcOvershoot = 1.2;

/// Projects a [world]-space point to screen coordinates via the standard
/// clip-space transform: `clip = proj * view * (world, 1)`.
///
/// Returns null when the point is BEHIND the camera (`clip.w <= 0` — the
/// projection would be a meaningless mirror image) or far outside the view
/// frustum (|ndc| > [overshoot] on either axis). Points slightly off screen
/// (within the overshoot band) are clamped to the nearest screen edge so
/// near-miss FX still render at a sensible spot.
///
/// [screenSize] is the size of the widget overlaying the AR view (assumed to
/// share the camera viewport's aspect ratio, which holds for our full-screen
/// AR surfaces). NDC +y points UP while screen +y points DOWN, hence the flip.
Offset? worldToScreen(
  Vector3 world,
  Matrix4 view,
  Matrix4 proj,
  Size screenSize, {
  double overshoot = kArNdcOvershoot,
}) {
  final clip = (proj.multiplied(view))
      .transform(Vector4(world.x, world.y, world.z, 1.0));
  if (clip.w <= 0) return null; // behind the camera
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (ndcX.abs() > overshoot || ndcY.abs() > overshoot) return null;
  final cx = ndcX.clamp(-1.0, 1.0);
  final cy = ndcY.clamp(-1.0, 1.0);
  return Offset(
    (cx + 1) / 2 * screenSize.width,
    (1 - cy) / 2 * screenSize.height,
  );
}
