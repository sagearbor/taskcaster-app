import 'package:flutter/material.dart';

/// Brand + semantic colour tokens that Material's [ColorScheme] has no slot
/// for: success / warning / info / late states, the gold + coral game-show
/// accents, medal colours and the hero gradient.
///
/// Read them with `context.tokens` (see [AppTokensContext]). Every token pair
/// (`x` on `onX`, `onXContainer` on `xContainer`, and `xText` on the theme's
/// surface) is chosen to clear WCAG AA (4.5:1) for body text. The light and
/// dark sets are registered on [AppTheme.lightTheme] / [AppTheme.darkTheme].
///
/// Screens should never reach for `Colors.green` / `Colors.amber` etc. —
/// pick the semantic token instead so both themes stay coherent.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Positive outcome: submitted, done, joined, correct.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Needs attention soon: in progress, time running low, pending.
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Neutral information: waiting on others, tips.
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Late / overtime / penalty.
  final Color late;
  final Color onLate;
  final Color lateContainer;
  final Color onLateContainer;

  /// Gold accent as a FILL (stars, trophies, timer pill border). Not for
  /// small text on light surfaces — use [goldText].
  final Color gold;

  /// Gold that is readable as text on the theme's surfaces.
  final Color goldText;

  /// Coral accent as a FILL (hero call-to-action, stamps).
  final Color coral;

  /// Coral that is readable as text on the theme's surfaces.
  final Color coralText;

  /// Rubber-stamp ink ("LATE", "CROWD'S PICK"…).
  final Color stamp;

  /// Podium medals (used as fills; put [onMedal] text on them).
  final Color medalGold;
  final Color medalSilver;
  final Color medalBronze;
  final Color onMedal;

  /// The signature violet → coral hero surface (home hero, "Up next" card).
  final Gradient heroGradient;

  /// Text / icons on [heroGradient].
  final Color onHero;
  final Color onHeroMuted;

  /// Scrim behind text that sits over photos / video.
  final Color mediaScrim;

  const AppTokens({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.late,
    required this.onLate,
    required this.lateContainer,
    required this.onLateContainer,
    required this.gold,
    required this.goldText,
    required this.coral,
    required this.coralText,
    required this.stamp,
    required this.medalGold,
    required this.medalSilver,
    required this.medalBronze,
    required this.onMedal,
    required this.heroGradient,
    required this.onHero,
    required this.onHeroMuted,
    required this.mediaScrim,
  });

  static const Color _ink = Color(0xFF211B33);

  static const LinearGradient _hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // Violet into a deep coral: white text clears 4.5:1 along the whole ramp
    // (pure coral #FB5779 only manages 3.1:1).
    colors: [Color(0xFF6D28D9), Color(0xFFD02B63)],
  );

  static const AppTokens light = AppTokens(
    success: Color(0xFF15803D),
    onSuccess: Colors.white,
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    warning: Color(0xFFB45309),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF78350F),
    info: Color(0xFF4C1D95),
    onInfo: Colors.white,
    infoContainer: Color(0xFFEDE4FF),
    onInfoContainer: Color(0xFF4C1D95),
    late: Color(0xFFC2410C),
    onLate: Colors.white,
    lateContainer: Color(0xFFFFEDD5),
    onLateContainer: Color(0xFF7C2D12),
    gold: Color(0xFFF59E0B),
    goldText: Color(0xFFB45309),
    coral: Color(0xFFFB5779),
    coralText: Color(0xFFD61F4A),
    stamp: Color(0xFFD61F4A),
    medalGold: Color(0xFFF59E0B),
    medalSilver: Color(0xFFB8B2C9),
    medalBronze: Color(0xFFD19A6E),
    onMedal: _ink,
    heroGradient: _hero,
    onHero: Colors.white,
    onHeroMuted: Color(0xE6FFFFFF),
    mediaScrim: Color(0x99000000),
  );

  static const AppTokens dark = AppTokens(
    success: Color(0xFF4ADE80),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF14361F),
    onSuccessContainer: Color(0xFFBBF7D0),
    warning: Color(0xFFFBBF24),
    onWarning: Color(0xFF3A2600),
    warningContainer: Color(0xFF4A3A12),
    onWarningContainer: Color(0xFFFDE68A),
    info: Color(0xFFB79CFF),
    onInfo: Color(0xFF4C1D95),
    infoContainer: Color(0xFF2E2552),
    onInfoContainer: Color(0xFFDDD0FF),
    late: Color(0xFFFDBA74),
    onLate: Color(0xFF431407),
    lateContainer: Color(0xFF4A2412),
    onLateContainer: Color(0xFFFED7AA),
    gold: Color(0xFFFBBF24),
    goldText: Color(0xFFFBBF24),
    coral: Color(0xFFFB5779),
    coralText: Color(0xFFFF8FA6),
    stamp: Color(0xFFFF8FA6),
    medalGold: Color(0xFFFBBF24),
    medalSilver: Color(0xFFC9C3DA),
    medalBronze: Color(0xFFD9A47A),
    onMedal: _ink,
    heroGradient: _hero,
    onHero: Colors.white,
    onHeroMuted: Color(0xE6FFFFFF),
    mediaScrim: Color(0x99000000),
  );

  @override
  AppTokens copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? late,
    Color? onLate,
    Color? lateContainer,
    Color? onLateContainer,
    Color? gold,
    Color? goldText,
    Color? coral,
    Color? coralText,
    Color? stamp,
    Color? medalGold,
    Color? medalSilver,
    Color? medalBronze,
    Color? onMedal,
    Gradient? heroGradient,
    Color? onHero,
    Color? onHeroMuted,
    Color? mediaScrim,
  }) {
    return AppTokens(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      late: late ?? this.late,
      onLate: onLate ?? this.onLate,
      lateContainer: lateContainer ?? this.lateContainer,
      onLateContainer: onLateContainer ?? this.onLateContainer,
      gold: gold ?? this.gold,
      goldText: goldText ?? this.goldText,
      coral: coral ?? this.coral,
      coralText: coralText ?? this.coralText,
      stamp: stamp ?? this.stamp,
      medalGold: medalGold ?? this.medalGold,
      medalSilver: medalSilver ?? this.medalSilver,
      medalBronze: medalBronze ?? this.medalBronze,
      onMedal: onMedal ?? this.onMedal,
      heroGradient: heroGradient ?? this.heroGradient,
      onHero: onHero ?? this.onHero,
      onHeroMuted: onHeroMuted ?? this.onHeroMuted,
      mediaScrim: mediaScrim ?? this.mediaScrim,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      success: c(success, other.success),
      onSuccess: c(onSuccess, other.onSuccess),
      successContainer: c(successContainer, other.successContainer),
      onSuccessContainer: c(onSuccessContainer, other.onSuccessContainer),
      warning: c(warning, other.warning),
      onWarning: c(onWarning, other.onWarning),
      warningContainer: c(warningContainer, other.warningContainer),
      onWarningContainer: c(onWarningContainer, other.onWarningContainer),
      info: c(info, other.info),
      onInfo: c(onInfo, other.onInfo),
      infoContainer: c(infoContainer, other.infoContainer),
      onInfoContainer: c(onInfoContainer, other.onInfoContainer),
      late: c(late, other.late),
      onLate: c(onLate, other.onLate),
      lateContainer: c(lateContainer, other.lateContainer),
      onLateContainer: c(onLateContainer, other.onLateContainer),
      gold: c(gold, other.gold),
      goldText: c(goldText, other.goldText),
      coral: c(coral, other.coral),
      coralText: c(coralText, other.coralText),
      stamp: c(stamp, other.stamp),
      medalGold: c(medalGold, other.medalGold),
      medalSilver: c(medalSilver, other.medalSilver),
      medalBronze: c(medalBronze, other.medalBronze),
      onMedal: c(onMedal, other.onMedal),
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      onHero: c(onHero, other.onHero),
      onHeroMuted: c(onHeroMuted, other.onHeroMuted),
      mediaScrim: c(mediaScrim, other.mediaScrim),
    );
  }

  /// Medal fill for a 1-based podium [rank]; null past third.
  Color? medalFor(int rank) => switch (rank) {
        1 => medalGold,
        2 => medalSilver,
        3 => medalBronze,
        _ => null,
      };
}

extension AppTokensContext on BuildContext {
  /// The active theme's [AppTokens]. Falls back to the light/dark default set
  /// (by brightness) when a test wraps a widget in a bare `ThemeData()`.
  AppTokens get tokens {
    final theme = Theme.of(this);
    return theme.extension<AppTokens>() ??
        (theme.brightness == Brightness.dark ? AppTokens.dark : AppTokens.light);
  }
}
