import 'dart:async';
import 'dart:io';

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/widgets/ar_view.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import 'ar_engine.dart';

/// The ONE file that imports the AR plugin (`ar_flutter_plugin_2`). Everything
/// else in the app talks to [ArEngine] only, so the plugin can be swapped or
/// replaced with a fallback (e.g. model_viewer_plus) by editing just this file.
///
/// PLUGIN API USED (ar_flutter_plugin_2 0.0.3):
///   - [ARView] widget with `onARViewCreated` + `planeDetectionConfig`.
///   - `ARSessionManager.onInitialize(...)`, `.onPlaneDetected = (int count)`,
///     `.dispose()`.
///   - `ARObjectManager.onInitialize()`, `.onNodeTap = (List<String> names)`,
///     `.addNode(ARNode) -> Future<bool?>`, `.removeNode(ARNode)`.
///   - `ARNode(type: NodeType.localGLTF2, uri: <asset .gltf>, position, scale)`;
///     moving a node = mutating `node.position` (its `transformNotifier`
///     pushes the new transform to the platform automatically).
///
/// The plugin has NO physics and NO primitive shapes: every object is a glTF
/// model placed as a node, and "popping" is simply removing the tapped node.
class ArFlutterEngine implements ArEngine {
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  ARAnchorManager? _anchorManager;

  /// Spawned plugin nodes, keyed by node name, so [move]/[remove] can find the
  /// concrete [ARNode] behind an [ArNode] handle.
  final Map<String, ARNode> _nodes = {};

  /// Asset path -> an in-flight/completed copy of the model into the app
  /// documents folder. The plugin's `localGLTF2` loader fails to add bundled
  /// models on-device (addNode returns false); writing a `.glb` to the app's
  /// own documents dir and loading it via `fileSystemAppFolderGLB` is the
  /// robust, fully-offline path.
  ///
  /// We cache the *Future*, not the result, so that N concurrent spawns share a
  /// SINGLE file write. Caching the result let every spawn race to write the
  /// same path at once, producing a torn/truncated `.glb` that `addNode` then
  /// rejected intermittently ("Failed to add AR node node_N").
  final Map<String, Future<String>> _modelCopies = {};

  /// Serializes `addNode` calls. The native (Filament/SceneView) object manager
  /// is not safe to hammer with concurrent adds; chaining them one-at-a-time
  /// makes placement deterministic.
  Future<void> _addQueue = Future<void>.value();

  int _spawnCounter = 0;

  /// Completes when the platform AR view has been created and the managers are
  /// live. [initSession] awaits this so callers never spawn before the view
  /// exists.
  final Completer<void> _ready = Completer<void>();

  final StreamController<ArPlane> _planeController =
      StreamController<ArPlane>.broadcast();
  final StreamController<ArTap> _tapController =
      StreamController<ArTap>.broadcast();

  @override
  Widget buildView() {
    return ARView(
      onARViewCreated: _onViewCreated,
      planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
    );
  }

  void _onViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    sessionManager.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      handleTaps: true,
    );
    objectManager.onInitialize();

    // Bridge plugin callbacks onto the plugin-agnostic streams.
    // onPlaneDetected gives a running count of detected planes; we surface each
    // detection so the mini-game knows tracking has warmed up enough to spawn.
    sessionManager.onPlaneDetected = (int planeCount) {
      _planeController.add(ArPlane('plane_$planeCount'));
    };
    objectManager.onNodeTap = (List<String> nodeNames) {
      for (final name in nodeNames) {
        _tapController.add(ArTap(name));
      }
    };

    if (!_ready.isCompleted) _ready.complete();
  }

  @override
  Future<void> initSession() {
    // Resolves once [_onViewCreated] has wired the managers, so the caller can
    // safely spawn nodes afterwards. The ARView widget (from [buildView]) must
    // be in the tree for this to complete.
    return _ready.future;
  }

  @override
  Stream<ArPlane> get planes => _planeController.stream;

  @override
  Stream<ArTap> get taps => _tapController.stream;

  /// Copies a bundled `.glb` asset into the app documents folder once and
  /// returns its bare filename for [NodeType.fileSystemAppFolderGLB]. Concurrent
  /// callers share one copy via the [_modelCopies] future-cache.
  Future<String> _ensureLocalModel(String assetPath) {
    return _modelCopies.putIfAbsent(assetPath, () => _copyModel(assetPath));
  }

  Future<String> _copyModel(String assetPath) async {
    final fileName = assetPath.split('/').last;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    // Rewrite if the file is missing OR its length doesn't match the bundled
    // asset. The length check heals a torn `.glb` left behind by the old
    // concurrent-write bug (a truncated file otherwise persists forever and
    // keeps failing addNode). `flush: true` guarantees the bytes are on disk
    // before the native loader reads them.
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    // IMPORTANT: return the ABSOLUTE path, not the bare filename. The plugin's
    // native `fileSystemAppFolderGLB` (type 2) branch does NO path resolution —
    // it passes `uri` straight to `modelLoader.loadModelInstance(...)`. A bare
    // filename can't be found there, so addNode returns false (the long-standing
    // "Failed to add AR node node_N" bug). getApplicationDocumentsDirectory()
    // on Android is `<dataDir>/app_flutter`, the exact dir the plugin reads.
    return file.path;
  }

  /// Adds a node on the serialized queue, retrying a couple of times because the
  /// native object manager occasionally returns false on the first attempt for a
  /// freshly-written model.
  Future<bool> _addNodeSerialized(ARNode node) {
    final next = _addQueue.then((_) => _addNodeWithRetry(node));
    // Keep the chain alive even if this add fails, so later spawns still run.
    _addQueue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _addNodeWithRetry(ARNode node) async {
    final manager = _objectManager;
    if (manager == null) return false;
    for (var attempt = 0; attempt < 3; attempt++) {
      final added = await manager.addNode(node);
      if (added == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return false;
  }

  @override
  Future<ArNode> spawn({
    required String modelRef,
    required ArVector3 position,
    ArPlane? onPlane,
  }) async {
    final objectManager = _objectManager;
    if (objectManager == null) {
      throw StateError('AR view not created yet — cannot spawn.');
    }

    final localPath = await _ensureLocalModel(modelRef);
    final name = 'node_${_spawnCounter++}';
    final node = ARNode(
      type: NodeType.fileSystemAppFolderGLB,
      uri: localPath,
      name: name,
      position: vm.Vector3(position.x, position.y, position.z),
      scale: vm.Vector3(1.0, 1.0, 1.0),
    );

    final added = await _addNodeSerialized(node);
    if (added != true) {
      throw StateError('Failed to add AR node "$name" ($modelRef).');
    }
    _nodes[name] = node;
    return ArNode(name);
  }

  @override
  Future<void> move(ArNode node, ArVector3 position) async {
    final concrete = _nodes[node.id];
    if (concrete == null) return;
    // Mutating position updates the node's transformNotifier, which the object
    // manager listens to and forwards to the platform as a transform change.
    concrete.position = vm.Vector3(position.x, position.y, position.z);
  }

  @override
  Future<void> remove(ArNode node) async {
    final concrete = _nodes.remove(node.id);
    if (concrete == null) return;
    _objectManager?.removeNode(concrete);
  }

  @override
  Future<void> dispose() async {
    for (final node in _nodes.values) {
      _objectManager?.removeNode(node);
    }
    _nodes.clear();
    _sessionManager?.dispose();
    await _planeController.close();
    await _tapController.close();
    _sessionManager = null;
    _objectManager = null;
    _anchorManager = null;
  }
}
