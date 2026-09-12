import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// Five big tappable chips, 1..5, with "tragic" / "legendary" under the ends.
/// Tapping calls [onGrade] once and (briefly) highlights the chosen chip —
/// the caller decides what happens next (advance the queue, etc).
class GradeBar extends StatefulWidget {
  final ValueChanged<int> onGrade;

  /// Optional: highlight this score as already-chosen (e.g. mid-transition).
  final int? selected;

  const GradeBar({super.key, required this.onGrade, this.selected});

  @override
  State<GradeBar> createState() => _GradeBarState();
}

class _GradeBarState extends State<GradeBar> {
  int? _justTapped;

  @override
  Widget build(BuildContext context) {
    final selected = _justTapped ?? widget.selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var score = 1; score <= 5; score++)
              _GradeChip(
                score: score,
                isSelected: selected == score,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _justTapped = score);
                  widget.onGrade(score);
                },
              ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'tragic',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
              Text(
                'legendary',
                style: TextStyle(fontSize: 12, color: AppTheme.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GradeChip extends StatelessWidget {
  final int score;
  final bool isSelected;
  final VoidCallback onTap;

  const _GradeChip({
    required this.score,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Grade $score point${score == 1 ? '' : 's'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppTheme.violet : AppTheme.violetSoft,
            border: Border.all(
              color: AppTheme.violet,
              width: isSelected ? 0 : 2,
            ),
          ),
          child: Text(
            '$score',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppTheme.violetDeep,
                ),
          ),
        ),
      ),
    );
  }
}
