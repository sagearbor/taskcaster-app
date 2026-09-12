import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Home zone 2 — the full-width "Arena — grade the crowd" button. Pure: the
/// navigation target (the real ArenaScreen, or the placeholder until
/// feat/arena-ui lands) is decided by the caller via [onTap].
class ArenaEntryButton extends StatelessWidget {
  final VoidCallback onTap;

  const ArenaEntryButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.theater_comedy, color: AppTheme.violet),
        label: const Text(
          'Arena — grade the crowd',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.violetDeep,
          side: const BorderSide(color: AppTheme.violet, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
