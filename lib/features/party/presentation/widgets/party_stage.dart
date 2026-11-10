import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// The party "stage": a fixed, high-contrast deep-violet surface with big
/// white type, readable from across a table in any room light. Deliberately
/// the same in light and dark theme (it is a game-show set, not a page).
class PartyColors {
  static const Color bgTop = Color(0xFF2A1260);
  static const Color bgBottom = Color(0xFF120A24);
  static const Color text = Colors.white;
  static const Color muted = Color(0xFFCBC0E6);
  static const Color gold = AppTheme.goldBright;
  static const Color onGold = Color(0xFF2A1A00);
  static const Color coral = AppTheme.coral;
  static const Color card = Color(0x1FFFFFFF);
  static const Color cardBorder = Color(0x33FFFFFF);
}

/// Full-bleed stage with a slim header row and a scrollable body over a
/// pinned bottom action area, so nothing overflows at 360x640.
class PartyStage extends StatelessWidget {
  final String header;
  final VoidCallback? onClose;
  final Widget body;
  final List<Widget> actions;
  final Widget? overlay;

  /// Centre a short body vertically (clock, missions) instead of pinning
  /// it to the top (lists, forms).
  final bool centerBody;

  const PartyStage({
    super.key,
    required this.header,
    required this.body,
    this.onClose,
    this.actions = const [],
    this.overlay,
    this.centerBody = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PartyColors.bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [PartyColors.bgTop, PartyColors.bgBottom],
          ),
        ),
        child: Stack(
          children: [
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        if (onClose != null)
                          IconButton(
                            tooltip: 'Leave the party',
                            onPressed: onClose,
                            icon: const Icon(Icons.close,
                                color: PartyColors.muted),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: Text(
                            header,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Fredoka',
                              color: PartyColors.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: centerBody
                            ? ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: max(0, box.maxHeight - 24)),
                                child: Center(child: body),
                              )
                            : body,
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            actions[i],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (overlay != null) Positioned.fill(child: overlay!),
          ],
        ),
      ),
    );
  }
}

/// The main call to action: a tall gold slab with dark type.
class PartyButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final IconData? icon;

  const PartyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final style = secondary
        ? OutlinedButton.styleFrom(
            foregroundColor: PartyColors.text,
            side: const BorderSide(color: PartyColors.cardBorder, width: 2),
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 19,
                fontWeight: FontWeight.w600),
          )
        : FilledButton.styleFrom(
            backgroundColor: PartyColors.gold,
            foregroundColor: PartyColors.onGold,
            disabledBackgroundColor: const Color(0x33FFFFFF),
            disabledForegroundColor: PartyColors.muted,
            minimumSize: const Size.fromHeight(64),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            textStyle: const TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 22,
                fontWeight: FontWeight.w700),
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return secondary
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}

/// Rotated rubber-stamp label ("TWIST", "TIME", "CHAMPION").
class PartyStamp extends StatelessWidget {
  final String text;
  final Color color;
  final double size;
  const PartyStamp(this.text,
      {super.key, this.color = PartyColors.coral, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.08,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: size * 0.6, vertical: size * 0.22),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Fredoka',
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: size,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

/// Headline type for the stage.
TextStyle partyTitle([double size = 34]) => TextStyle(
      fontFamily: 'Fredoka',
      color: PartyColors.text,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

/// Body type for the stage: big enough to read aloud from arm's length.
TextStyle partyBody([double size = 22, Color color = PartyColors.text]) =>
    TextStyle(
      fontFamily: 'PlusJakartaSans',
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );
