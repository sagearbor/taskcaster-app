import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/datasources/nearby_diagnostics.dart';
import '../../data/datasources/nearby_permissions.dart';

/// A collapsible "Connection debug" panel for the offline (Nearby) screens.
///
/// Shows, so a screenshot can diagnose a failed pairing without a debugger:
///  * each Nearby permission's status + the Location service (toggle) state,
///  * a live, timestamped log of every advertise/discover/connection event
///    (and any thrown plugin error) from [NearbyDiagnostics].
///
/// Collapsed by default so it never gets in the way of play.
class NearbyDebugPanel extends StatelessWidget {
  const NearbyDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('Connection debug'),
        subtitle: const Text('Tap to see permissions + live pairing log'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          FutureBuilder<Map<String, String>>(
            future: NearbyPermissions.snapshot(),
            builder: (context, snap) {
              final data = snap.data;
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: LinearProgressIndicator(),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Permissions & services',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  ...data.entries.map((e) => _Row(k: e.key, v: e.value)),
                  const Divider(height: 20),
                ],
              );
            },
          ),
          Row(
            children: [
              Text('Live log', style: theme.textTheme.labelLarge),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  final text = NearbyDiagnostics.instance.lines.join('\n');
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Debug log copied')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              TextButton.icon(
                onPressed: NearbyDiagnostics.instance.clear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
          AnimatedBuilder(
            animation: NearbyDiagnostics.instance,
            builder: (context, _) {
              final lines = NearbyDiagnostics.instance.lines;
              if (lines.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No events yet…'),
                );
              }
              return Container(
                constraints: const BoxConstraints(maxHeight: 220),
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    lines.join('\n'),
                    style: const TextStyle(
                      color: Color(0xFF9CFF9C),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String k;
  final String v;
  const _Row({required this.k, required this.v});

  @override
  Widget build(BuildContext context) {
    final bad = v == 'denied' ||
        v == 'permanentlyDenied' ||
        v == 'restricted' ||
        v == 'disabled';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 12.5))),
          Text(
            v,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: bad ? Colors.red : Colors.green,
            ),
          ),
        ],
      ),
    );
  }
}
