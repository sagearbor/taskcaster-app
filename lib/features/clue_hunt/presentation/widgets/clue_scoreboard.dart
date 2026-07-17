import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/clue_hunt_session.dart';

/// Running-totals scoreboard, ranked highest first. Highlights the viewer's own
/// row and marks the current hider. Used mid-game (compact) and on the winner
/// ceremony (full).
class ClueScoreboard extends StatelessWidget {
  final ClueHuntSession session;
  final String selfId;

  /// When true, renders as a translucent overlay card for the play screens.
  final bool overlay;

  const ClueScoreboard({
    super.key,
    required this.session,
    required this.selfId,
    this.overlay = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ranked = session.leaderboard;
    final rows = <Widget>[];
    for (var i = 0; i < ranked.length; i++) {
      final p = ranked[i];
      final isSelf = p.id == selfId;
      final isHider = p.id == session.hiderId;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('${i + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: AppTheme.inkSoft)),
            ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      p.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            isSelf ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelf)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('(you)',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.inkSoft)),
                    ),
                  if (isHider)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('🫥',
                          style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
            Text('${p.totalScore}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ));
    }

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );

    if (!overlay) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Theme(
          data: theme.copyWith(
            textTheme: theme.textTheme.apply(
                bodyColor: Colors.white, displayColor: Colors.white),
          ),
          child: content,
        ),
      ),
    );
  }
}
