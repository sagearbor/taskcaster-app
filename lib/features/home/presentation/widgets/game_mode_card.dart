import 'package:flutter/material.dart';

/// One tappable gradient banner on the home screen for a game mode (Quick
/// Play, Drawing Telephone, Trivia Buzzer, Balloon Blitz, AR Games, Discover…).
///
/// Replaces four near-identical hand-rolled banner builders that each
/// duplicated the same gradient/padding/row markup with inline hex colors.
/// Colors come in as a gradient pair — pass theme/AppTheme tokens.
class GameModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Two-stop gradient (top-left → bottom-right). Use AppTheme tokens where
  /// they exist.
  final List<Color> gradientColors;
  final VoidCallback onTap;

  /// Hero variant: the larger treatment used by the top Quick Play banner.
  final bool hero;

  const GameModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: hero ? 4 : 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(hero ? 20 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(hero ? 12 : 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: hero ? 32 : 26, color: Colors.white),
              ),
              SizedBox(width: hero ? 16 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: hero ? 22 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: hero ? 4 : 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: hero ? 14 : 13,
                        color:
                            hero ? Colors.white.withOpacity(0.9) : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: hero ? 20 : 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
