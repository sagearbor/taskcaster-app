import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// Five big tappable chips, 1..5, with "tragic" / "legendary" under the ends.
/// Tapping calls [onGrade] once, highlights the chosen chip and bounces it —
/// the caller decides what happens next (advance the queue, etc).
class GradeBar extends StatefulWidget {
  final ValueChanged<int> onGrade;

  /// Optional: highlight this score as already-chosen (e.g. mid-transition).
  final int? selected;

  const GradeBar({super.key, required this.onGrade, this.selected});

  /// How long the chosen chip's scale-bounce (1.0 -> 1.25 -> 1.0) takes.
  static const Duration bounceDuration = Duration(milliseconds: 220);

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

/// One grade chip. When it becomes the chosen one it does a quick
/// scale-bounce so the tap feels like it landed.
class _GradeChip extends StatefulWidget {
  final int score;
  final bool isSelected;
  final VoidCallback onTap;

  const _GradeChip({
    required this.score,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_GradeChip> createState() => _GradeChipState();
}

class _GradeChipState extends State<_GradeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: GradeBar.bounceDuration,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 1.25).chain(CurveTween(curve: Curves.easeOut)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.25, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 55,
    ),
  ]).animate(_bounce);

  @override
  void didUpdateWidget(covariant _GradeChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final isSelected = widget.isSelected;
    return Semantics(
      button: true,
      selected: isSelected,
      label: 'Grade $score point${score == 1 ? '' : 's'}',
      child: ScaleTransition(
        scale: _scale,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: widget.onTap,
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
      ),
    );
  }
}
