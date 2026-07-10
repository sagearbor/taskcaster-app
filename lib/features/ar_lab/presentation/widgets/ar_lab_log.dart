import 'package:flutter/material.dart';

/// Severity of a single diagnostic line in the AR Lab status log.
enum ArLabLogLevel { info, step, success, error }

/// One timestamped entry in the AR Lab diagnostic log.
///
/// The AR Lab is a *diagnostic* tool, so every plugin call, callback and error
/// is recorded verbatim with the wall-clock time it happened. Nothing here is
/// summarised or swallowed — verbosity is the whole point.
class ArLabLogLine {
  ArLabLogLine(this.message, this.level) : timestamp = DateTime.now();

  final String message;
  final ArLabLogLevel level;
  final DateTime timestamp;

  String get clock {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// A scrollable, monospace pane that renders the [ArLabLogLine] history with the
/// newest line at the bottom, auto-scrolling as lines arrive. Colour-codes by
/// level so a failed host/resolve is obvious at a glance during a two-phone test.
class ArLabLogPane extends StatefulWidget {
  const ArLabLogPane({super.key, required this.lines});

  final List<ArLabLogLine> lines;

  @override
  State<ArLabLogPane> createState() => _ArLabLogPaneState();
}

class _ArLabLogPaneState extends State<ArLabLogPane> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ArLabLogPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the newest line in view as the log grows.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _colorFor(ArLabLogLevel level) {
    switch (level) {
      case ArLabLogLevel.success:
        return const Color(0xFF34D399);
      case ArLabLogLevel.error:
        return const Color(0xFFFB7185);
      case ArLabLogLevel.step:
        return const Color(0xFFFBBF24);
      case ArLabLogLevel.info:
        return const Color(0xFFB4B0C4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF16121F),
      child: widget.lines.isEmpty
          ? const Center(
              child: Text(
                'Diagnostic log — every step & callback appears here.',
                style: TextStyle(color: Color(0xFF746C8A), fontSize: 12),
              ),
            )
          : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: widget.lines.length,
              itemBuilder: (context, i) {
                final line = widget.lines[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                      children: [
                        TextSpan(
                          text: '${line.clock}  ',
                          style: const TextStyle(color: Color(0xFF5B5470)),
                        ),
                        TextSpan(
                          text: line.message,
                          style: TextStyle(color: _colorFor(line.level)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
