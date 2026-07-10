import 'dart:async';
import 'dart:io';

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/widgets/ar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../../../../core/services/ar/ar_capability_service.dart';
import '../widgets/ar_lab_log.dart';

/// AR Lab — a hidden, self-contained feasibility spike for ARCore Cloud Anchors.
///
/// NOT a game feature. It exercises the vendored `ar_flutter_plugin_2` cloud
/// anchor API (`initGoogleCloudAnchorMode` / `uploadAnchor` / `downloadAnchor`)
/// end-to-end between two phones so we can measure whether shared-space AR is
/// viable before designing anything around it. It touches no game flow, no
/// Firestore, no repositories — everything lives in this feature folder.
///
/// PLUGIN CALLBACK FLOW (reverse-engineered from the plugin + Android source):
///
///   HOST
///     1. `anchorManager.initGoogleCloudAnchorMode()` at view creation flips the
///        native ARCore session to `CloudAnchorMode.ENABLED`.
///     2. Tap a plane -> `sessionManager.onPlaneOrPointTap(hits)`; take the first
///        plane hit's `worldTransform`.
///     3. `addAnchor(ARPlaneAnchor(transformation: worldTransform))` registers
///        the anchor natively; `addNode(gem, planeAnchor: anchor)` parents the
///        gem model to it.
///     4. `uploadAnchor(anchor)` hosts it. The `Future<bool?>` only completes
///        when hosting FINISHES (true = ok, false = failed/insufficient data).
///        On success the plugin ALSO fires `onAnchorUploaded(anchor)` with
///        `anchor.cloudanchorid` populated — that callback is where the id
///        actually arrives (the bool carries no id). Failures surface on
///        `sessionManager.onError`.
///
///   RESOLVE
///     1. `downloadAnchor(id)` (fire-and-forget) calls `CloudAnchorNode.resolve`
///        natively.
///     2. On success the plugin adds the resolved node to the scene and fires
///        `onAnchorDownloaded(serializedAnchor)` — which must RETURN an ARAnchor
///        whose `.name` the native side then registers. NOTE: the serialized map
///        only contains `{type, cloudanchorid}` (no transformation/name), so we
///        must build the anchor by hand — calling `ARPlaneAnchor.fromJson` would
///        throw on the missing transformation.
///     3. To draw the gem at the resolved anchor we re-parent a gem node to it
///        via `addNode(gem, planeAnchor: resolvedAnchor)`, retried briefly
///        because the native anchor-node map is populated a beat AFTER our
///        callback returns the name. Failures surface on `sessionManager.onError`.
///
/// TTL: `ARPlaneAnchor.ttl` defaults to 1 (day). The vendored `host()` call does
/// NOT forward a ttl, so with API-key auth the lifetime is ARCore's default
/// (~24h). We log the ttl field but flag that it is not honoured here.
class ArLabScreen extends StatefulWidget {
  const ArLabScreen({super.key});

  @override
  State<ArLabScreen> createState() => _ArLabScreenState();
}

enum _ArLabMode { host, resolve }

class _ArLabScreenState extends State<ArLabScreen> {
  // --- Capability gate (detect + explain, never fake) --------------------
  final ArCapabilityService _capability = ArCapabilityServiceImpl();
  ArSupport? _support;

  // --- Plugin managers ---------------------------------------------------
  ARSessionManager? _sessionManager;
  ARObjectManager? _objectManager;
  ARAnchorManager? _anchorManager;

  // --- Mode + diagnostic log --------------------------------------------
  _ArLabMode _mode = _ArLabMode.host;
  final List<ArLabLogLine> _log = [];

  // --- HOST state --------------------------------------------------------
  ARPlaneAnchor? _placedAnchor; // placed, not yet hosted
  bool _hosting = false;
  String? _hostedCloudId;
  Duration? _hostDuration;
  DateTime? _hostStartedAt;

  // --- RESOLVE state -----------------------------------------------------
  final TextEditingController _resolveController = TextEditingController();
  bool _resolving = false;
  DateTime? _resolveStartedAt;

  /// Fail-safe for the fire-and-forget downloadAnchor: onAnchorDownloaded /
  /// onError are the only things that clear [_resolving], so a resolve that
  /// never matches (expired/mistyped id, viewpoint too different) would disable
  /// the Resolve button forever. This timeout re-enables it after 30s.
  Timer? _resolveTimeout;
  static const Duration _resolveTimeoutDuration = Duration(seconds: 30);
  Duration? _resolveDuration;
  bool _resolveSucceeded = false;

  /// Set when an error string smells like the ARCore Cloud Anchor API is not
  /// enabled / the app is not authorized (missing API key). Drives an in-screen
  /// explanation instead of a silent failure.
  bool _looksLikeConfigError = false;

  // --- Gem model cache ---------------------------------------------------
  /// `file://` URI of the gem model copied into app documents. The plugin's
  /// bundled-asset (`localGLTF2`) loader fails on-device, so — exactly like the
  /// Balloon Blitz engine — we copy `gem.glb` into the app documents folder once
  /// and load it via `fileSystemAppFolderGLB` + a `file://` URI.
  Future<String>? _gemUri;
  int _nodeCounter = 0;

  @override
  void initState() {
    super.initState();
    _probeCapability();
  }

  @override
  void dispose() {
    _resolveTimeout?.cancel();
    _sessionManager?.dispose();
    _resolveController.dispose();
    super.dispose();
  }

  Future<void> _probeCapability() async {
    final support = await _capability.check();
    if (!mounted) return;
    setState(() => _support = support);
  }

  // ======================================================================
  // Logging
  // ======================================================================

  void _addLog(String message,
      [ArLabLogLevel level = ArLabLogLevel.info]) {
    if (!mounted) return;
    setState(() => _log.add(ArLabLogLine(message, level)));
  }

  // ======================================================================
  // AR view creation — the ONLY place cloud anchor mode is wired
  // ======================================================================

  void _onViewCreated(
    ARSessionManager sessionManager,
    ARObjectManager objectManager,
    ARAnchorManager anchorManager,
    ARLocationManager locationManager,
  ) {
    _sessionManager = sessionManager;
    _objectManager = objectManager;
    _anchorManager = anchorManager;

    // Show planes + feature points: this is a diagnostic tool, so the user needs
    // to SEE how much visual data ARCore has before hosting (hosting fails
    // without enough features).
    sessionManager.onInitialize(
      showAnimatedGuide: true,
      showFeaturePoints: true,
      showPlanes: true,
      handleTaps: true,
      // Opens the native transform gate so anchored nodes render where placed
      // (see ArFlutterEngine for the full rationale).
      handleRotation: true,
    );
    objectManager.onInitialize();

    // THE cloud-anchor switch. Scoped to this screen only.
    anchorManager.initGoogleCloudAnchorMode();
    _addLog('initGoogleCloudAnchorMode() — cloud anchor mode requested',
        ArLabLogLevel.step);

    sessionManager.onError = _onSessionError;
    sessionManager.onPlaneDetected = _onPlaneDetected;
    sessionManager.onPlaneOrPointTap = _onPlaneOrPointTap;
    anchorManager.onAnchorUploaded = _onAnchorUploaded;
    anchorManager.onAnchorDownloaded = _onAnchorDownloaded;

    _addLog('AR view created; managers wired', ArLabLogLevel.info);
  }

  // ======================================================================
  // Session callbacks
  // ======================================================================

  void _onSessionError(String error) {
    _addLog('onError: $error', ArLabLogLevel.error);
    final lower = error.toLowerCase();
    if (lower.contains('not_authorized') ||
        lower.contains('authoriz') ||
        lower.contains('api key') ||
        lower.contains('api_key') ||
        lower.contains('error_')) {
      if (mounted) setState(() => _looksLikeConfigError = true);
    }
    _resolveTimeout?.cancel();
    if (mounted) {
      setState(() {
        _hosting = false;
        _resolving = false;
      });
    }
  }

  int _lastPlaneCount = -1;
  void _onPlaneDetected(int planeCount) {
    // Throttle: only log when the count changes so the pane isn't flooded.
    if (planeCount != _lastPlaneCount) {
      _lastPlaneCount = planeCount;
      _addLog('onPlaneDetected — $planeCount plane(s) tracked',
          ArLabLogLevel.info);
    }
  }

  void _onPlaneOrPointTap(List<ARHitTestResult> hits) {
    if (_mode != _ArLabMode.host) return;
    if (_hosting) return;
    if (hits.isEmpty) return;
    final planeHit = hits.firstWhere(
      (h) => h.type == ARHitTestResultType.plane,
      orElse: () => hits.first,
    );
    _placeAnchorAndGem(planeHit);
  }

  // ======================================================================
  // HOST flow
  // ======================================================================

  Future<void> _placeAnchorAndGem(ARHitTestResult hit) async {
    final anchorManager = _anchorManager;
    final objectManager = _objectManager;
    if (anchorManager == null || objectManager == null) return;

    _addLog('plane tapped — creating anchor at hit (dist '
        '${hit.distance.toStringAsFixed(2)}m)', ArLabLogLevel.step);

    // ttl defaults to 1 day; recorded for visibility (see class doc re: TTL).
    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
    final added = await anchorManager.addAnchor(anchor);
    if (added != true) {
      _addLog('addAnchor() returned false — could not create anchor',
          ArLabLogLevel.error);
      return;
    }
    _addLog('addAnchor() ok — anchor "${anchor.name}" (ttl ${anchor.ttl}d)',
        ArLabLogLevel.success);

    final gemUri = await _ensureGemUri();
    final node = ARNode(
      type: NodeType.fileSystemAppFolderGLB,
      uri: gemUri,
      name: 'gem_${_nodeCounter++}',
      scale: vm.Vector3(0.15, 0.15, 0.15),
      position: vm.Vector3.zero(),
    );
    final nodeAdded = await objectManager.addNode(node, planeAnchor: anchor);
    if (nodeAdded == true) {
      _addLog('addNode(gem) attached to anchor', ArLabLogLevel.success);
    } else {
      _addLog('addNode(gem) returned false — gem not shown '
          '(anchor still hostable)', ArLabLogLevel.error);
    }

    if (mounted) {
      setState(() {
        _placedAnchor = anchor;
        _hostedCloudId = null;
        _hostDuration = null;
      });
    }
  }

  Future<void> _hostAnchor() async {
    final anchorManager = _anchorManager;
    final anchor = _placedAnchor;
    if (anchorManager == null || anchor == null) return;

    setState(() {
      _hosting = true;
      _hostedCloudId = null;
      _looksLikeConfigError = false;
    });
    _hostStartedAt = DateTime.now();
    _addLog('uploadAnchor() — hosting "${anchor.name}"…', ArLabLogLevel.step);

    // NOTE: this Future only completes once hosting actually finishes.
    final ok = await anchorManager.uploadAnchor(anchor);
    if (ok != true && _hostedCloudId == null) {
      // The plugin swallows the platform error message, so explain the two most
      // likely causes honestly rather than inventing a specific reason.
      _addLog('uploadAnchor() returned false — host failed', ArLabLogLevel.error);
      _addLog('  likely: insufficient visual data (scan the area more) OR the '
          'ARCore Cloud Anchor API is not enabled / no API key (see doc)',
          ArLabLogLevel.error);
      if (mounted) {
        setState(() {
          _hosting = false;
          _looksLikeConfigError = true;
        });
      }
    }
  }

  /// Fired by the plugin once hosting succeeds; [anchor.cloudanchorid] is set.
  void _onAnchorUploaded(ARAnchor anchor) {
    final id = (anchor as ARPlaneAnchor).cloudanchorid;
    final elapsed = _hostStartedAt == null
        ? null
        : DateTime.now().difference(_hostStartedAt!);
    _addLog('onAnchorUploaded — cloud anchor id: $id', ArLabLogLevel.success);
    if (elapsed != null) {
      _addLog('  hosted in ${elapsed.inMilliseconds} ms', ArLabLogLevel.info);
    }
    if (mounted) {
      setState(() {
        _hosting = false;
        _hostedCloudId = id;
        _hostDuration = elapsed;
      });
    }
  }

  // ======================================================================
  // RESOLVE flow
  // ======================================================================

  Future<void> _resolveAnchor() async {
    final anchorManager = _anchorManager;
    final id = _resolveController.text.trim();
    if (anchorManager == null || id.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _resolving = true;
      _resolveSucceeded = false;
      _resolveDuration = null;
      _looksLikeConfigError = false;
    });
    _resolveStartedAt = DateTime.now();
    _resolveTimeout?.cancel();
    _resolveTimeout = Timer(_resolveTimeoutDuration, _onResolveTimeout);
    _addLog('downloadAnchor("$id") — resolving…', ArLabLogLevel.step);
    await anchorManager.downloadAnchor(id);
  }

  /// The resolve never called back within the window — re-enable the button and
  /// explain the likely causes, instead of leaving it disabled forever.
  void _onResolveTimeout() {
    if (!mounted || !_resolving) return;
    setState(() => _resolving = false);
    _addLog(
      'Resolve timed out after 30s (anchor may be expired, id mistyped, or '
      'viewpoint too different)',
      ArLabLogLevel.error,
    );
  }

  /// Fired by the plugin when a resolve succeeds. Must return an [ARAnchor]
  /// whose name the native side registers. We build it by hand (the serialized
  /// map lacks a transformation) and schedule the gem attach.
  ARAnchor _onAnchorDownloaded(Map<String, dynamic> serialized) {
    final id = serialized['cloudanchorid']?.toString() ??
        _resolveController.text.trim();
    final anchor = ARPlaneAnchor(
      transformation: vm.Matrix4.identity(),
      cloudanchorid: id,
    );
    final elapsed = _resolveStartedAt == null
        ? null
        : DateTime.now().difference(_resolveStartedAt!);
    _addLog('onAnchorDownloaded — resolved anchor "${anchor.name}" '
        '(cloud id $id)', ArLabLogLevel.success);
    if (elapsed != null) {
      _addLog('  resolved in ${elapsed.inMilliseconds} ms', ArLabLogLevel.info);
    }
    _resolveTimeout?.cancel();
    if (mounted) {
      setState(() {
        _resolving = false;
        _resolveSucceeded = true;
        _resolveDuration = elapsed;
      });
    }
    _scheduleGemAttach(anchor);
    return anchor;
  }

  /// Re-parents a gem to the freshly-resolved anchor. Retried because the native
  /// anchor-node map is populated a beat after [_onAnchorDownloaded] returns.
  Future<void> _scheduleGemAttach(ARPlaneAnchor anchor) async {
    final objectManager = _objectManager;
    if (objectManager == null) return;
    final gemUri = await _ensureGemUri();
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final node = ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: gemUri,
        name: 'gem_resolved_${_nodeCounter++}',
        scale: vm.Vector3(0.15, 0.15, 0.15),
        position: vm.Vector3.zero(),
      );
      final added = await objectManager.addNode(node, planeAnchor: anchor);
      if (added == true) {
        _addLog('addNode(gem) attached to resolved anchor', ArLabLogLevel.success);
        return;
      }
    }
    _addLog('addNode(gem) failed after retries — resolve OK but gem not drawn',
        ArLabLogLevel.error);
  }

  // ======================================================================
  // Gem model copy (bundled-asset -> app documents file:// URI)
  // ======================================================================

  Future<String> _ensureGemUri() => _gemUri ??= _copyGem();

  Future<String> _copyGem() async {
    const asset = 'assets/ar/gem.glb';
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/gem.glb');
    final data = await rootBundle.load(asset);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return Uri.file(file.path).toString();
  }

  // ======================================================================
  // UI
  // ======================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Lab — Cloud Anchors'),
        backgroundColor: const Color(0xFF211B33),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF211B33),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final support = _support;
    if (support == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (support != ArSupport.supported) {
      return _buildUnsupported(support);
    }
    return Column(
      children: [
        // AR camera surface.
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              ARView(
                onARViewCreated: _onViewCreated,
                planeDetectionConfig:
                    PlaneDetectionConfig.horizontalAndVertical,
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: _modeSwitch(),
              ),
            ],
          ),
        ),
        // Controls + log.
        Expanded(
          flex: 4,
          child: Container(
            color: const Color(0xFF1B1526),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _mode == _ArLabMode.host
                        ? _hostControls()
                        : _resolveControls(),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF322A44)),
                SizedBox(
                  height: 140,
                  child: ArLabLogPane(lines: _log),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeSwitch() {
    return Center(
      child: SegmentedButton<_ArLabMode>(
        segments: const [
          ButtonSegment(
              value: _ArLabMode.host,
              label: Text('Host'),
              icon: Icon(Icons.cloud_upload_outlined)),
          ButtonSegment(
              value: _ArLabMode.resolve,
              label: Text('Resolve'),
              icon: Icon(Icons.cloud_download_outlined)),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
    );
  }

  // ---- HOST controls ----------------------------------------------------

  Widget _hostControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '1. Point at a feature-rich, well-lit surface and move the phone '
          'slowly ~10s to build tracking.\n'
          '2. Tap a detected plane to drop a gem.\n'
          '3. Host it to the cloud.',
          style: TextStyle(color: Color(0xFFB4B0C4), fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        if (_placedAnchor != null && _hostedCloudId == null)
          Text('Anchor placed: ${_placedAnchor!.name}',
              style: const TextStyle(color: Color(0xFF34D399), fontSize: 12)),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed:
              (_placedAnchor == null || _hosting) ? null : _hostAnchor,
          icon: _hosting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(_hosting
              ? 'Hosting…'
              : _placedAnchor == null
                  ? 'Tap a plane first'
                  : 'Host anchor to cloud'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6D28D9),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_hostedCloudId != null) _hostedResult(_hostedCloudId!),
        if (_looksLikeConfigError) _configHint(),
      ],
    );
  }

  Widget _hostedResult(String id) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16121F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF34D399)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF34D399), size: 18),
              const SizedBox(width: 6),
              Text(
                _hostDuration == null
                    ? 'Hosted'
                    : 'Hosted in ${_hostDuration!.inMilliseconds} ms',
                style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('CLOUD ANCHOR ID',
              style: TextStyle(
                  color: Color(0xFF746C8A),
                  fontSize: 10,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          SelectableText(
            id,
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Cloud anchor id copied'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF6D28D9))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.white,
              child: QrImageView(
                data: id,
                version: QrVersions.auto,
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'On phone B: scan this QR with the camera app to read the id, then '
            'type/paste it into the Resolve tab.',
            style: TextStyle(color: Color(0xFF746C8A), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ---- RESOLVE controls -------------------------------------------------

  Widget _resolveControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste/type the cloud anchor id from phone A, then look at the SAME '
          'physical spot from a similar viewpoint and resolve.',
          style: TextStyle(color: Color(0xFFB4B0C4), fontSize: 12.5),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tip: scan phone A\'s QR with your normal camera app to read the id.',
          style: TextStyle(color: Color(0xFF746C8A), fontSize: 11),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _resolveController,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'Cloud anchor id',
            hintStyle: const TextStyle(color: Color(0xFF5B5470)),
            filled: true,
            fillColor: const Color(0xFF16121F),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF322A44)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF6D28D9)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _resolving ? null : _resolveAnchor,
          icon: _resolving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.cloud_download_outlined),
          label: Text(_resolving ? 'Resolving…' : 'Resolve anchor'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6D28D9),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (_resolveSucceeded)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF16121F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF34D399)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: Color(0xFF34D399), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resolveDuration == null
                        ? 'Resolved — gem placed at the shared anchor.'
                        : 'Resolved in ${_resolveDuration!.inMilliseconds} ms '
                            '— gem placed at the shared anchor.',
                    style: const TextStyle(
                        color: Color(0xFF34D399), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (_looksLikeConfigError) _configHint(),
      ],
    );
  }

  // ---- Shared explanations ---------------------------------------------

  Widget _configHint() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1520),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB7185)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFB7185), size: 18),
              SizedBox(width: 6),
              Text('Cloud Anchor API may not be configured',
                  style: TextStyle(
                      color: Color(0xFFFB7185),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Cloud anchor hosting needs the "ARCore API" enabled in the '
            'taskmaster-app-3d480 Google Cloud project AND an Android API key '
            'added as a <meta-data> tag in AndroidManifest.xml '
            '(com.google.android.ar.API_KEY).\n\n'
            'See docs/cloud-anchors-spike.md for the exact one-time setup. '
            'If the API key is missing, hosting will keep failing with an '
            'authorization error — that is expected until setup is done.',
            style: TextStyle(color: Color(0xFFD8B4C0), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupported(ArSupport support) {
    late final String title;
    late final String body;
    Widget? action;
    switch (support) {
      case ArSupport.unsupportedPlatform:
        title = 'AR not available on this platform';
        body =
            'Cloud Anchors need a physical ARCore (Android) or ARKit (iOS) '
            'device. This build is running somewhere AR is unavailable (web / '
            'desktop / simulator).';
        break;
      case ArSupport.needsArCoreUpdate:
        title = 'Google Play Services for AR needed';
        body =
            'Install or update "Google Play Services for AR" (ARCore) from the '
            'Play Store, then reopen this screen.';
        break;
      case ArSupport.cameraDenied:
        title = 'Camera permission required';
        body =
            'The AR Lab needs the camera to track the world and place anchors.';
        action = ElevatedButton(
          onPressed: () async {
            final granted = await _capability.requestCamera();
            if (granted) {
              _probeCapability();
            } else {
              await _capability.openSettings();
            }
          },
          child: const Text('Grant camera access'),
        );
        break;
      case ArSupport.supported:
      case ArSupport.unknownError:
        title = 'Could not start AR';
        body =
            'Something went wrong probing AR support. Try reopening the screen '
            'on a physical AR-capable device.';
        break;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_outlined,
                color: Color(0xFF746C8A), size: 56),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFB4B0C4), fontSize: 13)),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
