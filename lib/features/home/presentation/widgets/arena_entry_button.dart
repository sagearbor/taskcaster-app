import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Home zone 2 — the Arena row. Deliberately an OUTLINED row, never a filled
/// button: Home has exactly one primary action above the fold, and that is
/// the next-task hero (WP-05).
///
/// Pure: [HomeView] works out what to show and supplies [onTap].
///  - [unreadCount] > 0: "Arena — N new to grade" with a count badge;
///  - [tease]: the viewer has posted nothing yet, so the Arena is a peek at
///    other people's entries rather than a grading queue;
///  - otherwise the plain "Arena — grade the crowd".
class ArenaEntryButton extends StatelessWidget {
  final VoidCallback onTap;

  /// Ungraded entries waiting in the viewer's queue. Null while unknown.
  final int? unreadCount;

  /// True when the viewer has posted nothing yet.
  final bool tease;

  /// The queue read is capped, so a full page reads as "30+".
  final int countCap;

  const ArenaEntryButton({
    super.key,
    required this.onTap,
    this.unreadCount,
    this.tease = false,
    this.countCap = 30,
  });

  @override
  Widget build(BuildContext context) {
    final count = unreadCount ?? 0;
    // scheme.primary: deep violet on light, lavender on dark (violetDeep was
    // unreadable on the dark surface).
    final primary = Theme.of(context).colorScheme.primary;
    final label =
        tease ? 'Arena — see how others did' : 'Arena — grade the crowd';
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.theater_comedy, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (!tease && count > 0)
              Container(
                key: const Key('arena-unread-badge'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.coral,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count >= countCap ? '$countCap+ new' : '$count new',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: AppTheme.violet),
          ],
        ),
      ),
    );
  }
}
