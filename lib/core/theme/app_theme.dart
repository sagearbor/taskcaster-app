import 'package:flutter/material.dart';

/// "Trophy" — playful game-show energy. Deep violet + gold + coral, a rounded
/// display face (Fredoka) for headings and a clean grotesque (Plus Jakarta
/// Sans) for body. Fonts are bundled assets (no runtime fetch).
class AppTheme {
  // Brand palette
  static const Color violet = Color(0xFF6D28D9);
  static const Color violetDeep = Color(0xFF4C1D95);
  static const Color violetSoft = Color(0xFFEDE4FF);
  static const Color gold = Color(0xFFF59E0B);
  static const Color goldBright = Color(0xFFFBBF24);
  static const Color coral = Color(0xFFFB5779);
  static const Color ink = Color(0xFF211B33);
  static const Color inkSoft = Color(0xFF746C8A);
  static const Color cream = Color(0xFFFAF6FF);
  static const Color surface = Color(0xFFFFFFFF);

  // Back-compat aliases (older screens reference these)
  static const Color primaryColor = violet;
  static const Color secondaryColor = gold;
  static const Color backgroundColor = cream;
  static const Color surfaceColor = surface;
  static const Color errorColor = Color(0xFFE0395E);

  // Dark palette — tuned for contrast on dark surfaces rather than inverted.
  // Violet is lightened to a readable lavender (deep violet is unreadable on
  // dark); gold/coral stay vivid as game-show accents. Surfaces layer from the
  // scaffold background up through cards to elevated sheets/dialogs.
  static const Color darkBg = Color(0xFF17121F); // scaffold background
  static const Color darkSurface = Color(0xFF221C33); // cards, app bar
  static const Color darkSurfaceHigh = Color(0xFF2C2542); // sheets, dialogs, menus
  static const Color darkAppBar = Color(0xFF2A2150); // violet-tinted brand bar
  static const Color violetLight = Color(0xFFB79CFF); // primary on dark
  static const Color onDark = Color(0xFFEDE9F5); // primary text on dark
  static const Color onDarkMuted = Color(0xFFAEA4C6); // secondary text on dark
  static const Color darkError = Color(0xFFFF8A9B); // readable red on dark

  static const String _display = 'Fredoka';
  static const String _body = 'PlusJakartaSans';

  /// Signature gradient used on hero surfaces and the auth backdrop.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9), Color(0xFF4C1D95)],
  );

  static TextTheme _textTheme(Color onColor) {
    TextStyle d(double size, [FontWeight w = FontWeight.w600, double ls = -0.3]) =>
        TextStyle(
            fontFamily: _display,
            fontWeight: w,
            fontSize: size,
            color: onColor,
            letterSpacing: ls);
    TextStyle b(double size, [FontWeight w = FontWeight.w400, double h = 1.4]) =>
        TextStyle(
            fontFamily: _body, fontWeight: w, fontSize: size, color: onColor, height: h);
    return TextTheme(
      displayLarge: d(40, FontWeight.w600, -0.5),
      displayMedium: d(32),
      displaySmall: d(28),
      headlineMedium: d(25),
      headlineSmall: d(21),
      titleLarge: d(20),
      titleMedium: d(17, FontWeight.w600, -0.2),
      titleSmall: d(15, FontWeight.w500, 0),
      bodyLarge: b(16),
      bodyMedium: b(14),
      bodySmall: b(12.5),
      labelLarge: TextStyle(
          fontFamily: _body,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: onColor,
          letterSpacing: 0.2),
      labelMedium: b(12.5, FontWeight.w600),
    );
  }

  static ThemeData get lightTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
    ).copyWith(
      primary: violet,
      onPrimary: Colors.white,
      primaryContainer: violetSoft,
      onPrimaryContainer: violetDeep,
      secondary: gold,
      onSecondary: Colors.white,
      tertiary: coral,
      surface: surface,
      onSurface: ink,
      error: errorColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cream,
      fontFamily: _body,
      textTheme: _textTheme(ink),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: violet,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontWeight: FontWeight.w600,
          fontSize: 22,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 6,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shadowColor: violet.withOpacity(0.13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: _display,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violet,
          side: BorderSide(color: violet.withOpacity(0.28), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: _display, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: violet,
          textStyle:
              const TextStyle(fontFamily: _body, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: violetSoft.withOpacity(0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: violet, width: 2)),
        labelStyle: const TextStyle(color: inkSoft, fontFamily: _body),
        hintStyle: const TextStyle(color: inkSoft, fontFamily: _body),
        prefixIconColor: violet,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: violetSoft.withOpacity(0.6),
        labelStyle: const TextStyle(
            fontFamily: _body, fontWeight: FontWeight.w600, color: violetDeep),
        side: BorderSide.none,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
        foregroundColor: Colors.white,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle:
            const TextStyle(fontFamily: _body, color: Colors.white),
      ),
      dividerColor: violet.withOpacity(0.08),
    );
  }

  static ThemeData get darkTheme {
    final scheme = ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.dark,
    ).copyWith(
      primary: violetLight,
      onPrimary: violetDeep,
      primaryContainer: violetDeep,
      onPrimaryContainer: violetSoft,
      secondary: goldBright,
      onSecondary: const Color(0xFF3A2600),
      secondaryContainer: const Color(0xFF4A3A12),
      onSecondaryContainer: goldBright,
      tertiary: coral,
      onTertiary: Colors.white,
      surface: darkSurface,
      onSurface: onDark,
      surfaceContainerHighest: darkSurfaceHigh,
      onSurfaceVariant: onDarkMuted,
      outline: const Color(0xFF4A4360),
      outlineVariant: const Color(0xFF352E4A),
      error: darkError,
      onError: const Color(0xFF3A0011),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBg,
      fontFamily: _body,
      textTheme: _textTheme(onDark),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: darkAppBar,
        foregroundColor: Colors.white,
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontWeight: FontWeight.w600,
          fontSize: 22,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: violetLight,
          foregroundColor: violetDeep,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: _display,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.3),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: violetLight,
          side: BorderSide(color: violetLight.withOpacity(0.42), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
              fontFamily: _display, fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: violetLight,
          textStyle:
              const TextStyle(fontFamily: _body, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: violetLight, width: 2)),
        labelStyle: const TextStyle(color: onDarkMuted, fontFamily: _body),
        hintStyle: const TextStyle(color: onDarkMuted, fontFamily: _body),
        prefixIconColor: violetLight,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceHigh,
        labelStyle: const TextStyle(
            fontFamily: _body, fontWeight: FontWeight.w600, color: onDark),
        side: BorderSide.none,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 4,
        backgroundColor: violetLight,
        foregroundColor: violetDeep,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: darkSurfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurfaceHigh,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: darkSurfaceHigh,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: darkSurfaceHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: _body, color: onDark),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: darkSurfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle:
            const TextStyle(fontFamily: _body, color: onDark),
      ),
      dividerColor: Colors.white.withOpacity(0.08),
    );
  }
}
