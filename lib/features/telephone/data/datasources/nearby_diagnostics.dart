import 'package:flutter/foundation.dart';

/// A tiny in-memory event log for the offline (Nearby Connections) transport, so
/// failures that are otherwise invisible — discovery finding nothing, a
/// connection rejected, a permission/service gap, a thrown plugin exception —
/// become a screenshot the user can send back to debug with.
///
/// It is a process-wide singleton because the transport (the plugin boundary)
/// and the debug panel (the UI) live in different layers and we don't want to
/// thread a logger through every constructor just for diagnostics.
class NearbyDiagnostics extends ChangeNotifier {
  NearbyDiagnostics._();
  static final NearbyDiagnostics instance = NearbyDiagnostics._();

  final List<String> _lines = [];
  static const int _max = 250;

  /// Most-recent-first log lines, each prefixed with a wall-clock time.
  List<String> get lines => List.unmodifiable(_lines);

  void log(String message) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${now.millisecond.toString().padLeft(3, '0')}';
    _lines.insert(0, '$stamp  $message');
    if (_lines.length > _max) _lines.removeRange(_max, _lines.length);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
