import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/datasources/nearby_diagnostics.dart';
import '../../data/datasources/nearby_permissions.dart';

/// Connection troubleshooting for the offline (Nearby) screens.
///
/// Invisible by default: all a player sees is a small, muted "Connection help"
/// text button. Tapping it expands the full diagnostics panel, which shows —
/// so a screenshot can diagnose a failed pairing without a debugger:
///  * each Nearby permission's status + the Location service (toggle) state,
///  * a live, timestamped log of every advertise/discover/connection event
///    (and any thrown plugin error) from [NearbyDiagnostics].
///
/// Deliberately NOT kDebugMode-gated: pairing problems happen on release
/// builds in the field, and this is the only way to see why.
class NearbyDebugPanel extends StatefulWidget {
  const NearbyDebugPanel({super.key});

  @override
  State<NearbyDebugPanel> createState() => _NearbyDebugPanelState();
}

class _NearbyDebugPanelState extends State<NearbyDebugPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_expanded) {
      // Quiet by default: one muted text button, no icon, no panel chrome.
      return SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                textStyle: theme.textTheme.bodySmall,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => setState(() => _expanded = true),
              child: const Text('Connection help'),
            ),
          ],
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Never swallow the whole screen, even with a long log.
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Connection help',
                          style: theme.textTheme.titleSmall),
                    ),
                    IconButton(
                      tooltip: 'Hide',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.expand_more),
                      onPressed: () => setState(() => _expanded = false),
                    ),
                  ],
                ),
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
                        final text =
                            NearbyDiagnostics.instance.lines.join('\n');
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
          ),
        ),
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
