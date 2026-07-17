import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:taskcaster_app/core/services/ar/ar_projection.dart';
import 'package:vector_math/vector_math_64.dart';

/// Pure-math tests for the world→screen clip-space transform, with
/// hand-computed expectations.
///
/// Test camera: a symmetric perspective projection with a 90° vertical field
/// of view and aspect ratio 1, near 0.01, far 100. For fovY = 90°,
/// f = 1/tan(45°) = 1, so (column-major, OpenGL-style):
///
///   proj = | 1  0    0     0 |
///          | 0  1    0     0 |
///          | 0  0   A     B  |   A = (far+near)/(near-far), B = 2*far*near/(near-far)
///          | 0  0   -1     0 |
///
/// With this matrix, for an eye-space point (x, y, z): clip.w = -z, and
/// ndc = (x/-z, y/-z). The camera looks down -z (view = identity ⇒ eye space
/// == world space), so hand-computing screen points is just similar triangles.
void main() {
  const size = Size(400, 600);

  Matrix4 proj90() {
    const near = 0.01;
    const far = 100.0;
    const a = (far + near) / (near - far);
    const b = 2 * far * near / (near - far);
    // Matrix4 column-major constructor: arguments are column 0 first.
    return Matrix4(
      1, 0, 0, 0, // column 0
      0, 1, 0, 0, // column 1
      0, 0, a, -1, // column 2
      0, 0, b, 0, // column 3
    );
  }

  test('point straight ahead lands on the exact screen center', () {
    // World (0,0,-2), camera at origin: ndc = (0/2, 0/2) = (0,0) → center.
    final p = worldToScreen(
        Vector3(0, 0, -2), Matrix4.identity(), proj90(), size);
    expect(p, const Offset(200, 300));
  });

  test('point behind the camera returns null (clip.w <= 0)', () {
    // World (0,0,+2) is BEHIND a camera looking down -z: clip.w = -z = -2.
    final p =
        worldToScreen(Vector3(0, 0, 2), Matrix4.identity(), proj90(), size);
    expect(p, isNull);
  });

  test('point exactly beside the camera (w == 0) returns null', () {
    final p =
        worldToScreen(Vector3(1, 0, 0), Matrix4.identity(), proj90(), size);
    expect(p, isNull);
  });

  test('off-axis point projects into the correct quadrant, hand-computed', () {
    // World (1,1,-2): ndc = (1/2, 1/2) = (0.5, 0.5).
    // Screen x = (0.5+1)/2 * 400 = 300 (right half),
    // screen y = (1-0.5)/2 * 600 = 150 (TOP half — ndc +y is up).
    final p =
        worldToScreen(Vector3(1, 1, -2), Matrix4.identity(), proj90(), size);
    expect(p, isNotNull);
    expect(p!.dx, closeTo(300, 1e-9));
    expect(p.dy, closeTo(150, 1e-9));
  });

  test('the VIEW matrix moves the camera: same point, camera shifted', () {
    // Camera translated to (0,0,+3) looking down -z ⇒ view = translate by -3
    // on z. World (0,0,-2) is 5 m ahead; world (1,0,-2): ndc.x = 1/5 = 0.2.
    final view = Matrix4.translation(Vector3(0, 0, -3));
    final ahead = worldToScreen(Vector3(0, 0, -2), view, proj90(), size);
    expect(ahead, const Offset(200, 300));
    final right = worldToScreen(Vector3(1, 0, -2), view, proj90(), size);
    expect(right!.dx, closeTo((0.2 + 1) / 2 * 400, 1e-9)); // = 240
    expect(right.dy, closeTo(300, 1e-9));
  });

  test('slightly-off-screen point clamps to the screen edge', () {
    // World (2.2,0,-2): ndc.x = 1.1 — outside the cube but within the 1.2
    // overshoot band → clamped to +1 → right edge, vertically centered.
    final p =
        worldToScreen(Vector3(2.2, 0, -2), Matrix4.identity(), proj90(), size);
    expect(p, const Offset(400, 300));
  });

  test('far outside the frustum returns null (beyond the overshoot band)', () {
    // World (3,0,-2): ndc.x = 1.5 > 1.2 → give up, no FX position.
    final p =
        worldToScreen(Vector3(3, 0, -2), Matrix4.identity(), proj90(), size);
    expect(p, isNull);
  });

  test('overshoot band is configurable', () {
    // ndc.x = 1.5: rejected at the default 1.2, clamped at overshoot 2.0.
    final world = Vector3(3, 0, -2);
    expect(
        worldToScreen(world, Matrix4.identity(), proj90(), size), isNull);
    expect(
      worldToScreen(world, Matrix4.identity(), proj90(), size, overshoot: 2),
      const Offset(400, 300),
    );
  });

  test('non-square aspect: projection scales x by 1/aspect', () {
    // fovY 90°, aspect 2 (wide): proj[0][0] = f/aspect = 0.5.
    final proj = proj90();
    proj.setEntry(0, 0, 0.5);
    // World (1,1,-2): ndc = (0.25, 0.5) → x = 1.25/2*400 = 250, y = 150.
    final p = worldToScreen(Vector3(1, 1, -2), Matrix4.identity(), proj, size);
    expect(p!.dx, closeTo(250, 1e-9));
    expect(p.dy, closeTo(150, 1e-9));
  });
}
