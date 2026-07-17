import 'package:flutter/widgets.dart';

import 'ar_projection.dart';

export 'ar_projection.dart' show ArCameraProjection;

/// A plain (plugin-agnostic) 3D position in AR world space, in meters relative
/// to the session origin. Right-handed: +x right, +y up, -z forward (away from
/// the device at session start). Kept free of any vector-math/plugin type so
/// the mini-game logic and its tests never import an AR plugin.
class ArVector3 {
  final double x;
  final double y;
  final double z;

  const ArVector3(this.x, this.y, this.z);
}

/// The camera's position AND facing in AR world space — for games that need to
/// know where the player is AIMING (e.g. Tower Trials' preview block), not just
/// where they stand. [forward] is the unit vector the camera looks along.
/// Plugin-agnostic like everything else at this boundary.
class ArCameraPose {
  final ArVector3 position;
  final ArVector3 forward;

  const ArCameraPose({required this.position, required this.forward});
}

/// A detected AR plane (e.g. a floor or table) the player can place objects on.
class ArPlane {
  final String id;

  const ArPlane(this.id);
}

/// A tap on an AR object (e.g. popping a balloon), identified by the spawned
/// node's id.
class ArTap {
  final String nodeId;

  const ArTap(this.nodeId);
}

/// A handle to a spawned AR object so it can be referenced later.
class ArNode {
  final String id;

  const ArNode(this.id);
}

/// Plugin-AGNOSTIC boundary for AR rendering. Nothing above this interface may
/// import an AR plugin — only the concrete engine implementation does. This
/// keeps the AR mini-game logic, the capability gating, and all tests free of
/// any plugin dependency, and lets us swap the underlying plugin (or fall back
/// to model_viewer_plus) without touching callers.
abstract class ArEngine {
  /// Build the platform AR view widget. Must be hosted by the engine impl.
  Widget buildView();

  /// Initialize the AR session (camera + tracking). Throws nothing the caller
  /// must handle for capability — capability is decided upstream by
  /// ArCapabilityService; this is the render-session bring-up.
  Future<void> initSession();

  /// Stream of detected planes as tracking discovers surfaces.
  Stream<ArPlane> get planes;

  /// Spawn an object (e.g. a balloon) at a world [position], returning its
  /// node handle. [modelRef] is the asset path of the 3D model. When [onPlane]
  /// is given the object is anchored to that plane; otherwise it is placed at
  /// [position] relative to the session origin.
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  });

  /// Move an already-spawned [node] to a new world [position] (used for the
  /// gentle bob/float animation). Best-effort: never throws.
  Future<void> move(ArNode node, ArVector3 position);

  /// Remove a spawned [node] from the scene (e.g. popping a balloon).
  Future<void> remove(ArNode node);

  /// Stream of taps on spawned objects (e.g. balloon pops).
  Stream<ArTap> get taps;

  /// The current camera position in AR world space (translation only), or null
  /// when tracking is unavailable/lost. The native side returns null unless
  /// ARCore is actively TRACKING (see the vendored-plugin patch in
  /// third_party/.../ArView.kt handleGetCameraPose), so a null result is the
  /// canonical "tracking lost" signal for Treasure Hunt's geiger. Never throws.
  Future<ArVector3?> cameraPosition();

  /// The current camera view + projection matrices for world→screen
  /// projection (see [worldToScreen] in ar_projection.dart), or null when
  /// tracking is unavailable/lost — mirroring [cameraPosition]'s null-unless-
  /// tracking contract (native: the vendored getCameraProjection patches in
  /// third_party/.../ArView.kt and IosARView.swift). One call serves projecting
  /// many objects, so query once per FX burst, not once per object.
  /// Never throws.
  Future<ArCameraProjection?> cameraProjection();

  /// The current camera position + facing direction, or null when tracking is
  /// unavailable/lost (same null contract as [cameraPosition]). Used by games
  /// that aim with the camera (Tower Trials): the view computes where the
  /// camera ray meets the tower-top plane. Never throws.
  Future<ArCameraPose?> cameraPose();

  /// Spawn [modelRef] roughly [distance] metres in FRONT of the current camera
  /// (using the live camera orientation), dropped [drop] metres for eye comfort,
  /// and return its node handle — or null if there is no pose / the spawn failed.
  ///
  /// Deliberately camera-relative (NOT a stored world spot): AR drift means a
  /// spot stored earlier may be off by a metre, so the object is placed relative
  /// to where the seeker is looking NOW. This is the load-bearing, drift-immune
  /// "reveal" for Treasure Hunt. Best-effort: never throws.
  Future<ArNode?> spawnInFrontOfCamera({
    required String modelRef,
    double distance,
    double drop,
  });

  /// Tear down the AR session and release the camera.
  Future<void> dispose();
}
